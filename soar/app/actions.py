"""Actions the playbook can run. Every action takes (event, rule) and
returns "ok", "skipped" or "failed"."""
import ipaddress
import json
import logging
import os
import subprocess
import time
import urllib.request

log = logging.getLogger("soar.actions")

PFSENSE_HOST = os.getenv("PFSENSE_HOST", "172.16.255.1")
PFSENSE_USER = os.getenv("PFSENSE_USER", "soar")
SSH_KEY = os.getenv("SSH_KEY", "/run/secrets/pfsense_key")
KNOWN_HOSTS = os.getenv("KNOWN_HOSTS", "/data/known_hosts")
BLOCK_TABLE = "SOAR_BLOCKLIST"
EVENT_LOG = os.getenv("EVENT_LOG", "/data/events.jsonl")
NOTIFY_URL = os.getenv("NOTIFY_WEBHOOK_URL", "")

# Safeguard: never block management, the tunnel or the AWS VPC.
PROTECTED = [ipaddress.ip_network(n) for n in os.getenv(
    "PROTECTED_NETS", "172.16.10.0/24,172.16.255.0/30,10.0.0.0/16").split(",")]
# Only addresses in the on-prem segments can be blocked.
BLOCKABLE = [ipaddress.ip_network(n) for n in os.getenv(
    "BLOCKABLE_NETS", "172.16.20.0/24,172.16.30.0/24").split(",")]


def check_ip(value):
    """Return (ip, reason). ip is None when the address may not be blocked."""
    try:
        ip = ipaddress.ip_address(value)
    except (TypeError, ValueError):
        return None, "no valid src_ip in event"
    if any(ip in net for net in PROTECTED):
        return None, f"{ip} is in a protected range"
    if not any(ip in net for net in BLOCKABLE):
        return None, f"{ip} is outside the blockable ranges"
    return ip, ""


def block_ip(event, rule):
    ip, reason = check_ip(event.get("src_ip"))
    if ip is None:
        log.warning("block_ip skipped: %s", reason)
        return "skipped"
    # Arguments as a list, no shell: the address cannot inject commands.
    cmd = ["ssh", "-i", SSH_KEY,
           "-o", "BatchMode=yes",
           "-o", "ConnectTimeout=5",
           "-o", "StrictHostKeyChecking=accept-new",
           "-o", f"UserKnownHostsFile={KNOWN_HOSTS}",
           f"{PFSENSE_USER}@{PFSENSE_HOST}",
           "sudo", "/sbin/pfctl", "-t", BLOCK_TABLE, "-T", "add", str(ip)]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    if result.returncode != 0:
        log.error("block_ip failed for %s: %s", ip, result.stderr.strip())
        return "failed"
    log.info("blocked %s on pfSense (%s)", ip, result.stderr.strip())
    return "ok"


def notify(event, rule):
    if not NOTIFY_URL:
        return "skipped"
    text = (f"SOAR: rule '{rule['name']}' fired for {event.get('alertname')} "
            f"({event.get('severity')}) from {event.get('src_ip', '-')}")
    body = json.dumps({"content": text, "text": text}).encode()
    req = urllib.request.Request(NOTIFY_URL, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=5)
        return "ok"
    except OSError as exc:
        log.error("notify failed: %s", exc)
        return "failed"


def record(event, rule, results=None):
    entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "rule": rule["name"], "event": event, "results": results or {}}
    os.makedirs(os.path.dirname(EVENT_LOG), exist_ok=True)
    with open(EVENT_LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")
    return "ok"


ACTIONS = {"block_ip": block_ip, "notify": notify, "record": record}
