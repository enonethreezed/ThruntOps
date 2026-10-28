#!/usr/bin/env python3
"""Selectively apply ThruntOps AD vulnerability roles to a deployed Ludus range."""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print(
        "Missing PyYAML. Install it with `python3 -m pip install PyYAML` "
        "and rerun this command.",
        file=sys.stderr,
    )
    raise SystemExit(2)


ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_ADCS_ROLE = "badsectorlabs.ludus_adcs"
UPSTREAM_ADCS_VERSION = "1.6.0"
ADCS_DEFAULT_FLAGS = {
    "ludus_adcs_esc1": True,
    "ludus_adcs_esc2": True,
    "ludus_adcs_esc3": True,
    "ludus_adcs_esc3_cra": True,
    "ludus_adcs_esc4": True,
    "ludus_adcs_esc5": True,
    "ludus_adcs_esc6": True,
    "ludus_adcs_esc7": True,
    "ludus_adcs_esc8": True,
    "ludus_adcs_esc9": True,
    "ludus_adcs_esc10": True,
    "ludus_adcs_esc10_case1": True,
    "ludus_adcs_esc10_case2": True,
    "ludus_adcs_esc11": True,
    "ludus_adcs_esc13": True,
    "ludus_adcs_esc14": True,
    "ludus_adcs_esc15": True,
    "ludus_adcs_esc16": True,
}


def local_scenario(
    name: str, label: str, role: str, host_kinds: tuple[str, ...], description: str
) -> dict[str, Any]:
    return {
        "name": name,
        "label": label,
        "role": role,
        "host_kinds": host_kinds,
        "description": description,
        "role_vars": {f"{role}_enabled": True},
        "external": False,
    }


SCENARIOS: dict[str, dict[str, Any]] = {
    "asrep": local_scenario(
        "asrep",
        "AS-REP roasting",
        "thruntops_ad_asrep_roasting",
        ("dc",),
        "Create a user without Kerberos preauthentication.",
    ),
    "timeroasting": local_scenario(
        "timeroasting",
        "Timeroasting",
        "thruntops_ad_timeroasting",
        ("dc",),
        "Create an enabled computer account with a deliberately weak password.",
    ),
    "shadow-credentials": local_scenario(
        "shadow-credentials",
        "Shadow Credentials",
        "thruntops_ad_shadow_credentials",
        ("dc",),
        "Create a low-privilege actor with explicit WriteProperty access limited to the target's msDS-KeyCredentialLink attribute.",
    ),
    "kerberoasting": local_scenario(
        "kerberoasting",
        "Kerberoasting",
        "thruntops_ad_kerberoasting",
        ("dc", "workstation"),
        "Create an SPN-bearing RC4 service account and grant workstation local admin.",
    ),
    "targeted-kerberoasting": local_scenario(
        "targeted-kerberoasting",
        "Targeted Kerberoasting",
        "thruntops_ad_targeted_kerberoasting",
        ("dc",),
        "Grant a delegated account WriteProperty on a privileged user's SPN.",
    ),
    "ntlm-relay": local_scenario(
        "ntlm-relay",
        "NTLM relay",
        "thruntops_ad_ntlm_relay",
        ("dc", "workstation"),
        "Relax LDAP relay protections on the DC and SMB signing on the workstation.",
    ),
    "coercion": local_scenario(
        "coercion",
        "Authentication coercion (MS-RPRN)",
        "thruntops_ad_coercion",
        ("dc",),
        "Enable Print Spooler on the DC and create a low-privilege test identity.",
    ),
    "dpapi": local_scenario(
        "dpapi",
        "DPAPI Secrets",
        "thruntops_ad_dpapi_secrets",
        ("dc", "workstation"),
        "Create a domain identity and a CurrentUser DPAPI-protected secret in its workstation profile.",
    ),
}


def adcs_scenario(name: str, label: str, flag: str, description: str) -> dict[str, Any]:
    return {
        "name": name,
        "label": label,
        "role": UPSTREAM_ADCS_ROLE,
        "host_kinds": ("dc",),
        "description": description,
        "role_vars": {flag: True},
        "external": True,
    }


ADCS_SCENARIOS = [
    ("ESC1", "ESC1", "ludus_adcs_esc1", "Template permits requester-supplied identity attributes."),
    ("ESC2", "ESC2", "ludus_adcs_esc2", "Overly broad certificate template purpose."),
    ("ESC3", "ESC3", "ludus_adcs_esc3", "Certificate request-agent enrollment misconfiguration."),
    ("ESC3-CRA", "ESC3 CRA variant", "ludus_adcs_esc3_cra", "Certificate request-agent variant."),
    ("ESC4", "ESC4", "ludus_adcs_esc4", "Weak permissions on a certificate template."),
    ("ESC5", "ESC5", "ludus_adcs_esc5", "Weak permissions on the CA's AD object."),
    ("ESC6", "ESC6", "ludus_adcs_esc6", "CA accepts request-supplied subject alternative names."),
    ("ESC7", "ESC7", "ludus_adcs_esc7", "Misconfigured CA manager permissions."),
    ("ESC8", "ESC8", "ludus_adcs_esc8", "Web enrollment endpoint available for NTLM relay testing."),
    ("ESC9", "ESC9", "ludus_adcs_esc9", "Template omits the SID security extension."),
    ("ESC10-CASE1", "ESC10 case 1", "ludus_adcs_esc10_case1", "Weak KDC certificate-binding enforcement."),
    ("ESC10-CASE2", "ESC10 case 2", "ludus_adcs_esc10_case2", "Weak Schannel certificate mapping methods."),
    ("ESC11", "ESC11", "ludus_adcs_esc11", "CA RPC enrollment endpoint does not enforce encryption."),
    ("ESC13", "ESC13", "ludus_adcs_esc13", "Certificate issuance policy linked to a privileged group."),
    ("ESC14", "ESC14", "ludus_adcs_esc14", "Weak explicit certificate mapping permissions."),
    ("ESC15", "ESC15", "ludus_adcs_esc15", "Vulnerable WebServer template configuration."),
    ("ESC16", "ESC16", "ludus_adcs_esc16", "CA omits the SID security extension globally."),
]

for esc_id, label, flag, description in ADCS_SCENARIOS:
    key = "adcs-" + esc_id.lower()
    SCENARIOS[key] = adcs_scenario(key, label, flag, description)


def run_ludus(args: list[str], *, capture: bool = False) -> str:
    command = ["ludus", *args]
    try:
        result = subprocess.run(
            command,
            check=True,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("Ludus CLI not found; install and configure it first.") from exc
    except subprocess.CalledProcessError as exc:
        details = (exc.stderr or exc.stdout or "").strip()
        raise RuntimeError(
            f"Ludus command failed: {' '.join(command)}"
            + (f"\n{details}" if details else "")
        ) from exc
    return result.stdout if capture else ""


def get_range_config(range_id: str) -> tuple[dict[str, Any], str]:
    output = run_ludus(
        ["range", "config", "get", "--json", "--range", range_id], capture=True
    )
    try:
        payload = json.loads(output)
        config_text = payload.get("result", output) if isinstance(payload, dict) else output
        config = yaml.safe_load(config_text) if isinstance(config_text, str) else config_text
    except (json.JSONDecodeError, yaml.YAMLError, AttributeError) as exc:
        raise RuntimeError("Could not parse the active range configuration from Ludus.") from exc
    if not isinstance(config, dict) or not isinstance(config.get("ludus"), list):
        raise RuntimeError("The active range configuration has no 'ludus' VM list.")
    return config, output


def range_nodes(config: dict[str, Any], range_id: str) -> dict[str, dict[str, Any]]:
    nodes = config.get("ludus", [])
    dc = next(
        (node for node in nodes if node.get("domain", {}).get("role") == "primary-dc"),
        None,
    )
    workstation = next(
        (
            node
            for node in nodes
            if node.get("domain", {}).get("role") == "member"
            and "win11" in str(node.get("template", "")).lower()
        ),
        None,
    )
    if dc is None:
        raise RuntimeError("Could not identify the primary domain controller in this range.")

    def rendered_name(node: dict[str, Any]) -> str:
        value = str(node.get("vm_name", ""))
        value = re.sub(r"\{\{\s*range_id\s*\}\}", range_id, value)
        if not value or "{{" in value:
            raise RuntimeError(f"Could not resolve VM name from range config: {value}")
        return value

    result = {"dc": {**dc, "vm_name": rendered_name(dc)}}
    if workstation is not None:
        result["workstation"] = {
            **workstation,
            "vm_name": rendered_name(workstation),
        }
    return result


def roles_and_vars(node: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    roles = node.setdefault("roles", [])
    role_vars = node.setdefault("role_vars", {})
    if not isinstance(roles, list) or not isinstance(role_vars, dict):
        raise RuntimeError(f"Invalid roles or role_vars in VM {node.get('vm_name')}.")
    return roles, role_vars


def adcs_vars_for_new_install() -> dict[str, bool]:
    return {name: False for name in ADCS_DEFAULT_FLAGS}


def prepare_config(
    original_config: dict[str, Any], range_id: str, selected: list[dict[str, Any]]
) -> tuple[dict[str, Any], list[str], list[str]]:
    config = copy.deepcopy(original_config)
    hosts = range_nodes(config, range_id)

    # Initialize ADCS switches to false only when first adding the upstream role.
    adcs_role_vars = None
    if any(item["external"] for item in selected):
        adcs_roles, adcs_role_vars = roles_and_vars(hosts["dc"])
        if UPSTREAM_ADCS_ROLE not in adcs_roles:
            adcs_role_vars.update(adcs_vars_for_new_install())

    roles_to_deploy = []
    targets_to_limit = []

    for scenario in selected:
        role_name = scenario["role"]
        for host_kind in scenario["host_kinds"]:
            node = hosts.get(host_kind)
            if node is None:
                raise RuntimeError(
                    f"Scenario {scenario['name']} requires a {host_kind}, "
                    "but none was found in this range configuration."
                )
            roles, role_vars = roles_and_vars(node)
            if role_name not in roles:
                roles.append(role_name)
            role_vars.update(scenario["role_vars"])
            if node["vm_name"] not in targets_to_limit:
                targets_to_limit.append(node["vm_name"])

        if scenario["external"]:
            assert adcs_role_vars is not None
            # Keep all upstream ADCS switches explicitly selected, instead of
            # accidentally inheriting the upstream role's all-enabled defaults.
            adcs_role_vars.update(scenario["role_vars"])
            # ESC10 cases require the parent toggle as well.
            if scenario["name"].startswith("adcs-esc10-"):
                adcs_role_vars["ludus_adcs_esc10"] = True
        if role_name not in roles_to_deploy:
            roles_to_deploy.append(role_name)

    return config, roles_to_deploy, targets_to_limit


def require_running_targets(range_id: str, target_names: list[str]) -> None:
    output = run_ludus(["range", "inventory", "--range", range_id], capture=True)
    try:
        inventory = yaml.safe_load(output)
        running_hosts = (
            inventory.get("all", {})
            .get("children", {})
            .get("running", {})
            .get("hosts", {})
        )
    except (yaml.YAMLError, AttributeError) as exc:
        raise RuntimeError("Could not verify target VM state from the Ludus inventory.") from exc
    if not isinstance(running_hosts, dict):
        raise RuntimeError("Ludus inventory has no running-host group; refusing to apply scenarios.")
    not_running = [name for name in target_names if name not in running_hosts]
    if not_running:
        raise RuntimeError(
            "All scenario target VMs must already be running. Not running or not found: "
            + ", ".join(not_running)
        )


def install_if_missing(role_name: str, external: bool, range_id: str) -> None:
    installed_roles = json.loads(
        run_ludus(["ansible", "role", "list", "--json", "--range", range_id], capture=True)
    )
    if external:
        installed = next(
            (
                item
                for item in installed_roles
                if isinstance(item, dict)
                and item.get("type") == "role"
                and item.get("name") == role_name
            ),
            None,
        )
        if installed and str(installed.get("version")) != UPSTREAM_ADCS_VERSION:
            raise RuntimeError(
                f"{role_name} version {installed.get('version')} is installed, but this CLI "
                f"catalog targets {UPSTREAM_ADCS_VERSION}. Update that role explicitly, then retry."
            )
        if installed:
            return
        print(f"Installing upstream role {role_name} version {UPSTREAM_ADCS_VERSION}.")
        run_ludus(
            [
                "ansible",
                "role",
                "add",
                role_name,
                "--version",
                UPSTREAM_ADCS_VERSION,
                "--range",
                range_id,
            ]
        )
        return

    role_path = ROOT / "roles" / role_name
    if not role_path.is_dir():
        raise RuntimeError(f"Local role directory not found: {role_path}")
    print(f"Registering local role {role_name} with Ludus.")
    run_ludus(
        ["ansible", "role", "add", "-d", str(role_path), "--force", "--range", range_id]
    )


def select_scenarios(names: list[str]) -> list[dict[str, Any]]:
    if names:
        selected_names = names
    else:
        catalog = list(SCENARIOS.values())
        print("Available scenarios:")
        for index, scenario in enumerate(catalog, start=1):
            print(f"  {index:2}. {scenario['name']:<26} {scenario['label']}")
        choice = input("Select scenario number(s), comma-separated (q to cancel): ").strip()
        if choice.lower() in {"q", "quit", "cancel"}:
            raise SystemExit(0)
        try:
            selected_names = [catalog[int(part.strip()) - 1]["name"] for part in choice.split(",")]
        except (ValueError, IndexError) as exc:
            raise RuntimeError("Invalid scenario selection.") from exc

    result = []
    seen = set()
    for name in selected_names:
        key = name.lower()
        if key not in SCENARIOS:
            raise RuntimeError(f"Unknown scenario '{name}'. Run 'list' to see valid names.")
        if key not in seen:
            result.append(SCENARIOS[key])
            seen.add(key)
    if not result:
        raise RuntimeError("Select at least one scenario.")
    return result


def apply_scenarios(range_id: str, names: list[str]) -> None:
    selected = select_scenarios(names)
    original_config, _ = get_range_config(range_id)
    config, roles_to_deploy, targets_to_limit = prepare_config(
        original_config, range_id, selected
    )
    require_running_targets(range_id, targets_to_limit)

    print(f"\nRange: {range_id}")
    print("Selected scenarios:")
    for scenario in selected:
        host_labels = ", ".join(scenario["host_kinds"])
        source = "upstream ADCS role" if scenario["external"] else "local role"
        print(f"  - {scenario['label']} ({source}; {host_labels})")
        print(f"    {scenario['description']}")
    print("Targets: " + ", ".join(targets_to_limit))
    print("Ludus operation: update range config, then run only selected roles on these targets.")
    print("No VM destruction or full range deployment is requested.")
    if any(item["external"] for item in selected):
        print("Warning: upstream ludus_adcs is not idempotent; existing vulnerable state is not removed by disabling a flag.")
    if not sys.stdin.isatty():
        raise RuntimeError("Interactive confirmation required; refusing to modify the range non-interactively.")
    confirmation = input("Type APPLY to continue: ").strip()
    if confirmation != "APPLY":
        print("Cancelled; no range configuration was changed.")
        return

    for role_name in roles_to_deploy:
        external = role_name == UPSTREAM_ADCS_ROLE
        install_if_missing(role_name, external, range_id)

    serialized = yaml.safe_dump(config, sort_keys=False, allow_unicode=True)
    temp_path = None
    try:
        descriptor, temp_name = tempfile.mkstemp(prefix="thruntops-range-", suffix=".yml")
        temp_path = Path(temp_name)
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(serialized)
        run_ludus(
            ["range", "config", "set", "--file", str(temp_path), "--range", range_id]
        )
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)

    try:
        run_ludus(
            [
                "range",
                "deploy",
                "--only-roles",
                ",".join(roles_to_deploy),
                "--limit",
                ",".join(targets_to_limit),
                "--range",
                range_id,
            ]
        )
    except RuntimeError:
        print(
            "The updated range configuration remains saved. The role run may have "
            "partially applied changes; inspect Ludus logs before retrying.",
            file=sys.stderr,
        )
        raise

    print("Selected scenario role(s) completed. Vulnerable states persist until explicitly cleaned up or the range is restored.")


def show_status(range_id: str) -> None:
    config, _ = get_range_config(range_id)
    hosts = range_nodes(config, range_id)
    print(f"Scenario roles configured for range {range_id}:")
    found = False
    for scenario in SCENARIOS.values():
        active = True
        for host_kind in scenario["host_kinds"]:
            node = hosts.get(host_kind)
            if node is None:
                active = False
                break
            roles = node.get("roles", [])
            role_vars = node.get("role_vars", {})
            if scenario["role"] not in roles:
                active = False
                break
            if not scenario["external"] and not role_vars.get(f"{scenario['role']}_enabled", False):
                active = False
                break
            if scenario["external"] and not role_vars.get(
                next(iter(scenario["role_vars"])), ADCS_DEFAULT_FLAGS[next(iter(scenario["role_vars"]))]
            ):
                active = False
                break
            if scenario["name"].startswith("adcs-esc10-") and not role_vars.get(
                "ludus_adcs_esc10", ADCS_DEFAULT_FLAGS["ludus_adcs_esc10"]
            ):
                active = False
                break
        if active:
            print(f"  - {scenario['name']}: configured")
            found = True
    if not found:
        print("  (none detected in the current range configuration)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Selectively provision ThruntOps AD scenarios on an existing Ludus range."
    )
    parser.add_argument("--range", dest="range_id", help="Explicit Ludus range ID (required for apply/status).")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("list", help="List supported local and ADCS scenarios.")
    subparsers.add_parser("status", help="Show scenarios recorded in the selected range configuration.")
    apply_parser = subparsers.add_parser("apply", help="Interactively choose and apply scenario(s).")
    apply_parser.add_argument("scenarios", nargs="*", help="Scenario names; omit to choose from a menu.")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "list":
        for scenario in SCENARIOS.values():
            tag = "upstream ADCS" if scenario["external"] else "local"
            print(f"{scenario['name']:<30} {scenario['label']} [{tag}]")
        return 0

    if not args.range_id:
        parser.error("--range is required for apply and status.")

    try:
        if args.command == "status":
            show_status(args.range_id)
        else:
            apply_scenarios(args.range_id, args.scenarios)
    except (RuntimeError, json.JSONDecodeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
