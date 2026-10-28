import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "thruntops-scenarios.py"
SPEC = importlib.util.spec_from_file_location("thruntops_scenarios", SCRIPT)
scenarios = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scenarios)


def make_range_config(include_workstation=True):
    machines = [
        {
            "vm_name": "{{ range_id }}-ad-dc-win2022-server-x64",
            "template": "win2022-server-x64-template",
            "domain": {"role": "primary-dc", "fqdn": "thruntops.domain"},
            "roles": [],
            "role_vars": {},
        }
    ]
    if include_workstation:
        machines.append(
            {
                "vm_name": "{{ range_id }}-ad-win11-22h2-enterprise-x64-1",
                "template": "win11-22h2-x64-enterprise-template",
                "domain": {"role": "member", "fqdn": "thruntops.domain"},
                "roles": [],
                "role_vars": {},
            }
        )
    return {"defaults": {}, "ludus": machines}


class ScenarioConfigTests(unittest.TestCase):
    def test_timeroasting_targets_dc_and_enables_local_role(self):
        original = make_range_config()
        updated, roles, limits = scenarios.prepare_config(
            original, "tst", [scenarios.SCENARIOS["timeroasting"]]
        )

        machine = updated["ludus"][0]
        self.assertEqual(roles, ["thruntops_ad_timeroasting"])
        self.assertEqual(limits, ["tst-ad-dc-win2022-server-x64"])
        self.assertIn("thruntops_ad_timeroasting", machine["roles"])
        self.assertTrue(machine["role_vars"]["thruntops_ad_timeroasting_enabled"])
        self.assertEqual(original["ludus"][0]["roles"], [])

    def test_local_scenario_targets_dc_and_workstation(self):
        original = make_range_config()
        updated, roles, limits = scenarios.prepare_config(
            original, "tst", [scenarios.SCENARIOS["kerberoasting"]]
        )

        self.assertEqual(roles, ["thruntops_ad_kerberoasting"])
        self.assertEqual(
            limits,
            [
                "tst-ad-dc-win2022-server-x64",
                "tst-ad-win11-22h2-enterprise-x64-1",
            ],
        )
        for machine in updated["ludus"]:
            self.assertIn("thruntops_ad_kerberoasting", machine["roles"])
            self.assertTrue(machine["role_vars"]["thruntops_ad_kerberoasting_enabled"])
        self.assertEqual(original["ludus"][0]["roles"], [])

    def test_adcs_new_role_defaults_every_scenario_off(self):
        selected = [
            scenarios.SCENARIOS["adcs-esc1"],
            scenarios.SCENARIOS["adcs-esc10-case2"],
        ]
        updated, roles, _ = scenarios.prepare_config(make_range_config(), "tst", selected)
        machine = updated["ludus"][0]
        role_vars = machine["role_vars"]

        self.assertEqual(roles, [scenarios.UPSTREAM_ADCS_ROLE])
        self.assertIn(scenarios.UPSTREAM_ADCS_ROLE, machine["roles"])
        for name in scenarios.ADCS_DEFAULT_FLAGS:
            self.assertEqual(
                role_vars[name],
                name
                in {
                    "ludus_adcs_esc1",
                    "ludus_adcs_esc10",
                    "ludus_adcs_esc10_case2",
                },
            )
        self.assertTrue(role_vars["ludus_adcs_esc10"])

    def test_adcs_preserves_previous_selection(self):
        config = make_range_config()
        config["ludus"][0]["roles"] = [scenarios.UPSTREAM_ADCS_ROLE]
        config["ludus"][0]["role_vars"] = {
            **scenarios.adcs_vars_for_new_install(),
            "ludus_adcs_esc1": True,
        }
        updated, _, _ = scenarios.prepare_config(
            config, "tst", [scenarios.SCENARIOS["adcs-esc6"]]
        )
        role_vars = updated["ludus"][0]["role_vars"]
        self.assertTrue(role_vars["ludus_adcs_esc1"])
        self.assertTrue(role_vars["ludus_adcs_esc6"])
        self.assertFalse(role_vars["ludus_adcs_esc2"])

    def test_missing_workstation_fails_before_config_change(self):
        config = make_range_config(include_workstation=False)
        with self.assertRaisesRegex(RuntimeError, "requires a workstation"):
            scenarios.prepare_config(
                config, "tst", [scenarios.SCENARIOS["ntlm-relay"]]
            )
        self.assertEqual(config["ludus"][0]["roles"], [])


if __name__ == "__main__":
    unittest.main()
