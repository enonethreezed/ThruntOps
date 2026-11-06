#!/usr/bin/env python3
"""Classify Splunk telemetry search results for ``siem.sh check``."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from typing import Any


def parse_export(payload: str) -> tuple[list[dict[str, Any]], list[str]]:
    """Parse Splunk's JSON-lines export format, retaining API/search errors."""
    rows: list[dict[str, Any]] = []
    errors: list[str] = []
    for number, line in enumerate(payload.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            errors.append(f"invalid JSON on response line {number}")
            continue
        for message in item.get("messages", []):
            if str(message.get("type", "")).upper() in {"ERROR", "FATAL"}:
                errors.append(str(message.get("text", "Splunk search error")))
        result = item.get("result")
        if isinstance(result, dict):
            rows.append(result)
    return rows, errors


def parse_index_inventory(payload: str) -> tuple[set[str], list[str]]:
    """Read index names from the Splunk REST data/indexes response."""
    try:
        response = json.loads(payload)
    except json.JSONDecodeError as exc:
        return set(), [f"invalid index-list response: {exc.msg}"]
    if not isinstance(response.get("entry"), list):
        return set(), ["index-list response has no entry list"]
    return {
        str(entry.get("name", "")).casefold()
        for entry in response["entry"]
        if entry.get("name")
    }, []


def _values(value: Any) -> list[str]:
    if value is None or value == "":
        return []
    if isinstance(value, list):
        return [str(item) for item in value if item not in (None, "")]
    return [str(value)]


def _format_timestamp(value: Any) -> str:
    try:
        return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat(timespec="seconds")
    except (TypeError, ValueError, OverflowError):
        return str(value or "unknown")


def _timestamp_key(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
        except (TypeError, ValueError, OverflowError):
            return 0.0


def host_matches(actual: str, expected: str) -> bool:
    """Accept the configured range hostname or its unprefixed Windows name."""
    actual = actual.casefold().rstrip(".")
    expected = expected.casefold().rstrip(".")
    short_name = next(
        (suffix.casefold() for suffix in ("DC01-2022", "WIN11-22H2-1") if expected.endswith(suffix.casefold())),
        expected,
    )
    return actual == expected or actual == short_name or actual.endswith(f"-{short_name}")


def _collector_findings(rows: list[dict[str, Any]], host: str) -> list[dict[str, Any]]:
    return [row for row in rows if host_matches(str(row.get("host", "")), host)]


def evaluate(payload: dict[str, Any]) -> dict[str, Any]:
    """Return per-host/index checks with diagnostics and summary counts."""
    parsed: dict[str, list[dict[str, Any]]] = {}
    errors: dict[str, list[str]] = {}
    for key in ("windows_recent", "sysmon_recent", "windows_history", "sysmon_history", "collector"):
        parsed[key], errors[key] = parse_export(str(payload.get(key, "")))

    indexes, inventory_errors = parse_index_inventory(str(payload.get("indexes", "")))
    checks: list[dict[str, str]] = []
    expected_hosts = payload.get("expected_hosts", [])
    lookback = str(payload.get("lookback", "1h"))

    sources = (
        ("windows", "Application", "application"),
        ("windows", "Security", "security"),
        ("windows", "System", "system"),
        ("windows", "PowerShell/Operational", "powershell/operational"),
        ("sysmon", "Sysmon/Operational", "sysmon/operational"),
    )

    for index, label, source_token in sources:
        recent_key = f"{index}_recent"
        history_key = f"{index}_history"
        recent_rows = parsed[recent_key]
        history_rows = parsed[history_key]
        query_errors = errors[recent_key] + errors[history_key]
        if index in indexes and query_errors:
            index_exists: bool | None = True
        elif inventory_errors:
            index_exists = None
        else:
            index_exists = index in indexes

        for expected in expected_hosts:
            matching = [
                row for row in recent_rows
                if host_matches(str(row.get("host", "")), str(expected))
                and any(
                    source_token in value.casefold()
                    for field in ("source", "sourcetype")
                    for value in _values(row.get(field))
                )
            ]
            observed_hosts = sorted({str(row.get("host", "")) for row in recent_rows if row.get("host")})
            if index_exists is False:
                status = "fail"
                message = f"index={index} does not exist; check Splunk index provisioning"
            elif query_errors:
                status = "fail"
                message = f"{label} query failed: {'; '.join(query_errors)}"
            elif matching:
                count = sum(int(row.get("count", 0) or 0) for row in matching)
                latest_row = max(matching, key=lambda row: _timestamp_key(row.get("last_seen", 0)))
                last_seen = _format_timestamp(latest_row.get("last_seen"))
                sources = sorted({
                    value
                    for row in matching
                    for field in ("source", "sourcetype")
                    for value in _values(row.get(field))
                })
                source_note = ", ".join(sources) if sources else "source metadata unavailable"
                status = "ok"
                message = (
                    f"{label} — {count} event(s), "
                    f"last_seen={last_seen}; source(s): {source_note}"
                )
            else:
                host_rows = [
                    row for row in recent_rows
                    if host_matches(str(row.get("host", "")), str(expected))
                ]
                historic_for_host = any(
                    host_matches(str(row.get("host", "")), str(expected))
                    and any(
                        source_token in value.casefold()
                        for field in ("source", "sourcetype")
                        for value in _values(row.get(field))
                    )
                    for row in history_rows
                )
                if historic_for_host:
                    status = "fail"
                    message = f"{label} has historical events for {expected}, but none in the last {lookback}"
                elif host_rows:
                    observed_sources = sorted({
                        value
                        for row in host_rows
                        for field in ("source", "sourcetype")
                        for value in _values(row.get(field))
                    })
                    status = "fail"
                    message = (
                        f"events reach index={index} for {expected}, but no source matched {label}; "
                        f"observed source(s): {', '.join(observed_sources) if observed_sources else 'unavailable'}"
                    )
                elif observed_hosts:
                    status = "fail"
                    message = f"{label} has no events mapped to {expected}; recent index hosts: {', '.join(observed_hosts[:8])}"
                elif index_exists is True and not history_rows:
                    status = "fail"
                    message = f"index={index} exists but is empty (no retained documents)"
                else:
                    status = "fail"
                    message = f"{label} has no events in the last {lookback}; index/source mapping or collector may be wrong"
            checks.append({"status": status, "label": f"{expected} / {label}", "message": message})

    for expected in expected_hosts:
        findings = _collector_findings(parsed["collector"], str(expected))
        if findings:
            details = [
                f"{row.get('component', 'collector')} ({row.get('log_level', 'unknown')}): "
                f"{' '.join(str(row.get('message', 'no message')).split())[:240]}"
                for row in findings[:3]
            ]
            status = "fail" if any(
                "error" in " ".join(_values(row.get("log_level"))).casefold()
                for row in findings
            ) else "warn"
            checks.append({
                "status": status,
                "label": f"{expected} / collector diagnostics",
                "message": "; ".join(details),
            })

    collector_parse_errors = errors["collector"]
    if collector_parse_errors:
        checks.append({
            "status": "warn",
            "label": "Splunk collector diagnostics",
            "message": "could not query _internal collector logs: " + "; ".join(collector_parse_errors),
        })

    return {
        "checks": checks,
        "indexes": sorted(indexes),
        "inventory_errors": inventory_errors,
        "summary": {
            "ok": sum(check["status"] == "ok" for check in checks),
            "fail": sum(check["status"] == "fail" for check in checks),
            "warn": sum(check["status"] == "warn" for check in checks),
        },
    }


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        report = evaluate(payload)
    except (json.JSONDecodeError, TypeError) as exc:
        print(json.dumps({"error": str(exc)}))
        return 2
    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
