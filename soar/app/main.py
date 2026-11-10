"""SOAR webhook listener: receives events, runs the matching playbook rules,
and exposes Prometheus metrics."""
import logging
import os
import time

from fastapi import FastAPI, Request
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from . import actions
from .rules import load_rules, matching_rules

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("soar")

RULES = load_rules(os.getenv("RULES_FILE", "/app/rules.yml"))
DEDUP_SECONDS = int(os.getenv("DEDUP_SECONDS", "300"))
_last_seen = {}

EVENTS = Counter("soar_events_total", "Events received", ["source"])
ACTIONS_RUN = Counter("soar_actions_total", "Actions run", ["action", "result"])
DUPLICATES = Counter("soar_duplicates_total", "Events skipped as duplicates")
PROCESSING = Histogram("soar_processing_seconds", "Time to handle one event")

app = FastAPI(title="Innovatech SOAR")


def is_duplicate(rule_name, event):
    """Same rule and same source address within DEDUP_SECONDS: skip."""
    key = (rule_name, event.get("src_ip"), event.get("alertname"))
    now = time.monotonic()
    if now - _last_seen.get(key, -DEDUP_SECONDS - 1) < DEDUP_SECONDS:
        return True
    _last_seen[key] = now
    return False


def handle(event):
    with PROCESSING.time():
        handled = []
        for rule in matching_rules(RULES, event):
            if is_duplicate(rule["name"], event):
                DUPLICATES.inc()
                continue
            results = {}
            for name in rule["actions"]:
                if name == "record":
                    continue  # record last, with the results of the others
                result = actions.ACTIONS[name](event, rule)
                ACTIONS_RUN.labels(name, result).inc()
                results[name] = result
            if "record" in rule["actions"]:
                result = actions.record(event, rule, results)
                ACTIONS_RUN.labels("record", result).inc()
                results["record"] = result
            log.info("rule=%s src_ip=%s results=%s",
                     rule["name"], event.get("src_ip"), results)
            handled.append({"rule": rule["name"], "results": results})
        return handled


def from_alertmanager(alert):
    labels = alert.get("labels", {})
    return {"source": "alertmanager",
            "alertname": labels.get("alertname"),
            "type": labels.get("type"),
            "severity": labels.get("severity"),
            "src_ip": labels.get("src_ip"),
            "status": alert.get("status")}


@app.post("/webhook/alertmanager")
async def alertmanager_webhook(request: Request):
    payload = await request.json()
    out = []
    for alert in payload.get("alerts", []):
        if alert.get("status") != "firing":
            continue  # resolved notifications need no action
        EVENTS.labels("alertmanager").inc()
        out.extend(handle(from_alertmanager(alert)))
    return {"handled": out}


@app.post("/webhook/event")
async def generic_webhook(request: Request):
    """For the traffic-analysis script: {type, severity, src_ip, ...}."""
    event = await request.json()
    event.setdefault("source", "traffic-analysis")
    EVENTS.labels(event["source"]).inc()
    return {"handled": handle(event)}


@app.get("/health")
def health():
    return {"status": "ok", "rules": len(RULES)}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
