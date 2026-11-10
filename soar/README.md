# Innovatech SOAR

Small self-built SOAR (Flavor B). Alertmanager and the traffic-analysis
script post events here; `rules.yml` decides which actions run.

| Endpoint | Purpose |
|---|---|
| `POST /webhook/alertmanager` | Alertmanager webhook receiver |
| `POST /webhook/event` | Generic events (traffic analysis) |
| `GET /metrics` | Prometheus metrics (REQ-09) |
| `GET /health` | Liveness check |

Actions: `block_ip` (SSH to pfSense, add to alias `SOAR_BLOCKLIST`),
`notify` (chat webhook, optional), `record` (JSON lines in `/data/events.jsonl`).

Safeguards: MGMT, the tunnel and the AWS VPC are never blocked; only the
WORKSTATIONS and SERVERS ranges are blockable. Repeats of the same rule and
address within 5 minutes are skipped.

Run the tests: `pip install -r requirements-dev.txt && pytest -q`
