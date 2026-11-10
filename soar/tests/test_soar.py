import os, tempfile
os.environ["RULES_FILE"] = os.path.join(os.path.dirname(__file__), "..", "rules.yml")
os.environ["EVENT_LOG"] = os.path.join(tempfile.mkdtemp(), "events.jsonl")

from fastapi.testclient import TestClient
from app import actions, main
from app.rules import matching_rules

client = TestClient(main.app)


def test_bruteforce_matches_block_rule():
    rules = matching_rules(main.RULES, {"type": "bruteforce", "severity": "critical"})
    assert [r["name"] for r in rules] == ["ssh-bruteforce"]


def test_unknown_event_only_recorded():
    rules = matching_rules(main.RULES, {"type": "WebServerDown", "severity": "critical"})
    assert [r["name"] for r in rules] == ["record-everything-else"]


def test_mgmt_is_never_blocked():
    assert actions.check_ip("172.16.10.105")[0] is None


def test_aws_and_garbage_are_never_blocked():
    assert actions.check_ip("10.0.33.10")[0] is None
    assert actions.check_ip("8.8.8.8")[0] is None
    assert actions.check_ip("1.2.3.4; reboot")[0] is None
    assert actions.check_ip(None)[0] is None


def test_workstation_can_be_blocked():
    assert str(actions.check_ip("172.16.20.50")[0]) == "172.16.20.50"


def test_webhook_blocks_once_then_dedups(monkeypatch):
    calls = []
    monkeypatch.setitem(actions.ACTIONS, "block_ip", lambda e, r: calls.append(e["src_ip"]) or "ok")
    body = {"alerts": [{"status": "firing", "labels": {
        "alertname": "SSH brute force", "type": "bruteforce",
        "severity": "critical", "src_ip": "172.16.20.77"}}]}
    first = client.post("/webhook/alertmanager", json=body).json()
    second = client.post("/webhook/alertmanager", json=body).json()
    assert calls == ["172.16.20.77"]
    assert first["handled"][0]["results"]["block_ip"] == "ok"
    assert second["handled"] == []


def test_resolved_alerts_are_ignored():
    body = {"alerts": [{"status": "resolved", "labels": {"type": "bruteforce"}}]}
    assert client.post("/webhook/alertmanager", json=body).json() == {"handled": []}


def test_metrics_endpoint():
    assert "soar_events_total" in client.get("/metrics").text
