import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "splunk_telemetry.py"
SPEC = importlib.util.spec_from_file_location("splunk_telemetry", MODULE_PATH)
splunk_telemetry = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(splunk_telemetry)


def export(*rows):
    import json

    return "\n".join(json.dumps({"result": row}) for row in rows)


class SplunkTelemetryTests(unittest.TestCase):
    def test_parses_results_and_fatal_messages(self):
        rows, errors = splunk_telemetry.parse_export(
            '{"result":{"host":"lab-DC01-2022"}}\n'
            '{"messages":[{"type":"FATAL","text":"Index sysmon does not exist"}]}'
        )
        self.assertEqual(rows, [{"host": "lab-DC01-2022"}])
        self.assertEqual(errors, ["Index sysmon does not exist"])

    def test_reports_recent_events_per_host_and_index(self):
        payload = {
            "expected_hosts": ["lab-DC01-2022", "lab-WIN11-22H2-1"],
            "lookback": "2h",
            "indexes": '{"entry":[{"name":"windows"},{"name":"sysmon"}]}',
            "windows_recent": export(
                {"host": "DC01-2022", "count": "12", "last_seen": "2026-11-06T09:00:00",
                 "source": ["WinEventLog:Security"], "sourcetype": ["XmlWinEventLog:Security"]},
                {"host": "lab-WIN11-22H2-1", "count": "5", "last_seen": "2026-11-06T09:02:00",
                 "source": ["WinEventLog:Application"], "sourcetype": ["XmlWinEventLog:Application"]},
            ),
            "sysmon_recent": export({
                "host": "lab-DC01-2022", "count": "8", "last_seen": "2026-11-06T09:01:00",
                "source": ["WinEventLog:Microsoft-Windows-Sysmon/Operational"],
                "sourcetype": ["XmlWinEventLog:Microsoft-Windows-Sysmon/Operational"],
            }),
            "windows_history": "",
            "sysmon_history": "",
            "collector": "",
        }
        report = splunk_telemetry.evaluate(payload)
        self.assertEqual(report["summary"]["ok"], 3)
        checks = {item["label"]: item["message"] for item in report["checks"]}
        self.assertIn("12 event(s)", checks["lab-DC01-2022 / Security"])
        self.assertIn("8 event(s)", checks["lab-DC01-2022 / Sysmon/Operational"])
        self.assertIn("5 event(s)", checks["lab-WIN11-22H2-1 / Application"])
        self.assertIn("recent index hosts: lab-DC01-2022", checks["lab-WIN11-22H2-1 / Sysmon/Operational"])

    def test_distinguishes_missing_index_and_wrong_host_mapping(self):
        payload = {
            "expected_hosts": ["lab-WIN11-22H2-1"],
            "lookback": "1h",
            "indexes": '{"entry":[{"name":"windows"}]}',
            "windows_recent": export({"host": "lab-other-host", "count": "2"}),
            "sysmon_recent": "",
            "windows_history": "",
            "sysmon_history": "",
            "collector": "",
        }
        report = splunk_telemetry.evaluate(payload)
        checks = {item["label"]: item["message"] for item in report["checks"]}
        self.assertIn("recent index hosts: lab-other-host", checks["lab-WIN11-22H2-1 / Application"])
        self.assertIn("does not exist", checks["lab-WIN11-22H2-1 / Sysmon/Operational"])

    def test_distinguishes_empty_index_from_no_recent_events(self):
        payload = {
            "expected_hosts": ["lab-WIN11-22H2-1"],
            "lookback": "1h",
            "indexes": '{"entry":[{"name":"windows"},{"name":"sysmon"}]}',
            "windows_recent": "",
            "sysmon_recent": "",
            "windows_history": "",
            "sysmon_history": export({
                "host": "lab-WIN11-22H2-1", "count": "22",
                "source": ["WinEventLog:Microsoft-Windows-Sysmon/Operational"],
                "sourcetype": ["XmlWinEventLog:Microsoft-Windows-Sysmon/Operational"],
            }),
            "collector": "",
        }
        report = splunk_telemetry.evaluate(payload)
        checks = {item["label"]: item["message"] for item in report["checks"]}
        self.assertIn("index=windows exists but is empty", checks["lab-WIN11-22H2-1 / Application"])
        self.assertIn("historical events", checks["lab-WIN11-22H2-1 / Sysmon/Operational"])

    def test_matches_added_windows_event_and_file_sources(self):
        labels = (
            ("Defender/Operational", "WinEventLog:Microsoft-Windows-Windows Defender/Operational"),
            ("DNS Client/Operational", "WinEventLog:Microsoft-Windows-DNS-Client/Operational"),
            ("DNS Server/Analytical", "WinEventLog:Microsoft-Windows-DNS-Server/Analytical"),
            ("PowerShell transcription", "thruntops:powershell:transcript"),
            ("Windows Firewall log", "thruntops:windows:firewall"),
        )
        payload = {
            "expected_hosts": ["lab-DC01-2022", "lab-WIN11-22H2-1"],
            "lookback": "1h",
            "indexes": '{"entry":[{"name":"windows"},{"name":"sysmon"}]}',
            "windows_recent": export(*(
                {"host": "lab-DC01-2022", "count": "3", "last_seen": "2026-11-06T09:00:00",
                 "source": [source], "sourcetype": [source]}
                for _, source in labels
            )),
            "sysmon_recent": "",
            "windows_history": "",
            "sysmon_history": "",
            "collector": "",
        }
        report = splunk_telemetry.evaluate(payload)
        checks = {item["label"]: item for item in report["checks"]}
        for label, _ in labels:
            check = checks[f"lab-DC01-2022 / {label}"]
            self.assertEqual(check["status"], "ok", check["message"])
        self.assertNotIn("lab-WIN11-22H2-1 / DNS Server/Analytical", checks)

    def test_surfaces_collector_errors_for_expected_host(self):
        payload = {
            "expected_hosts": ["lab-WIN11-22H2-1"],
            "lookback": "1h",
            "indexes": '{"entry":[{"name":"windows"},{"name":"sysmon"}]}',
            "windows_recent": "",
            "sysmon_recent": "",
            "windows_history": export({"host": "lab-WIN11-22H2-1", "count": "10"}),
            "sysmon_history": "",
            "collector": export({
                "host": "lab-WIN11-22H2-1", "component": "WinEventLogChannel",
                "log_level": "ERROR", "message": "errorCode=5 access denied",
            }),
        }
        report = splunk_telemetry.evaluate(payload)
        checks = {item["label"]: item["message"] for item in report["checks"]}
        self.assertIn("has no events", checks["lab-WIN11-22H2-1 / Security"])
        self.assertIn("errorCode=5", checks["lab-WIN11-22H2-1 / collector diagnostics"])


if __name__ == "__main__":
    unittest.main()
