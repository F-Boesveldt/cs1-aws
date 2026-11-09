# Monitoring instance: Prometheus + Grafana + Alertmanager, and in CS2 also
# Loki + Alloy for logs. No public IP — reachable only through the hub and,
# from on-prem, through the WireGuard tunnel.

data "aws_iam_instance_profile" "lab" {
  name = "cs1-ec2-role"
}

resource "aws_instance" "monitoring" {
  ami                    = "ami-0303e2e4a29f041a3"
  instance_type          = "t3.medium"
  subnet_id              = var.monitoring_subnet_id
  vpc_security_group_ids = [var.monitoring_sg_id]
  key_name               = var.key_name

  # Fixed address: pfSense sends its syslog here, so it must not change
  # when the instance is rebuilt (CS2).
  private_ip = "10.0.33.10"

    root_block_device {
      volume_size = 20
      volume_type = "gp3"
    }

  iam_instance_profile = data.aws_iam_instance_profile.lab.name

  user_data_replace_on_change = true

  # NOTE: plain aws_instance auto-base64-encodes user_data — do NOT wrap this
  # in base64encode() (same rule as the NAT instance; only aws_launch_template
  # needs that wrapper).
  user_data = <<-EOF
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    until apt-get update -y; do sleep 10; done
    until apt-get install -y docker.io; do sleep 10; done
    systemctl enable --now docker

    mkdir -p /opt/monitoring/grafana

    cat > /opt/monitoring/prometheus.yml <<'PROM'
    global:
      scrape_interval: 15s

    rule_files:
      - /etc/prometheus/alert_rules.yml

    alerting:
      alertmanagers:
        - static_configs:
            - targets: ['localhost:9093']

    scrape_configs:
      - job_name: 'prometheus'
        static_configs:
          - targets: ['localhost:9090']

      - job_name: 'web-node-exporter'
        ec2_sd_configs:
          - region: eu-central-1
            port: 9100
            filters:
              - name: tag:Name
                values: ["cs1-web"]
              - name: instance-state-name
                values: ["running"]
        relabel_configs:
          - source_labels: [__meta_ec2_instance_id]
            target_label: instance_id
          - source_labels: [__meta_ec2_private_ip]
            target_label: instance_ip
    PROM

    cat > /opt/monitoring/alert_rules.yml <<'RULES'
    groups:
      - name: cs1-web
        rules:
          - alert: WebServerDown
            expr: up{job="web-node-exporter"} == 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "Web server {{ $labels.instance }} is down"
          - alert: HighCpu
            expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100) > 70
            for: 2m
            labels:
              severity: warning
            annotations:
              summary: "CPU above 70% on {{ $labels.instance }}"
          - alert: TooFewWebServers
            expr: (count(up{job="web-node-exporter"} == 1) or vector(0)) < 2
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Fewer than 2 web servers are up"
    RULES

    cat > /opt/monitoring/alertmanager.yml <<'ALERT'
    route:
      receiver: 'default'
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 1m
      repeat_interval: 1h
    receivers:
      - name: 'default'
    ALERT

    # ---- CS2: Loki (log store) ----
    cat > /opt/monitoring/loki.yml <<'LOKI'
    auth_enabled: false
    server:
      http_listen_port: 3100
    common:
      instance_addr: 127.0.0.1
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h
    LOKI

    # ---- CS2: Alloy (receives syslog from on-prem, forwards to Loki) ----
    cat > /opt/monitoring/config.alloy <<'ALLOY'
    loki.source.syslog "onprem" {
      listener {
        address  = "0.0.0.0:1514"
        protocol = "udp"
        labels   = { job = "syslog", source = "onprem" }
      }
      relabel_rules = loki.relabel.syslog.rules
      forward_to    = [loki.write.local.receiver]
    }

    loki.relabel "syslog" {
      forward_to = []
      rule {
        source_labels = ["__syslog_message_hostname"]
        target_label  = "host"
      }
      rule {
        source_labels = ["__syslog_message_app_name"]
        target_label  = "app"
      }
      rule {
        source_labels = ["__syslog_message_severity"]
        target_label  = "severity"
      }
    }

    loki.write "local" {
      endpoint {
        url = "http://localhost:3100/loki/api/v1/push"
      }
    }
    ALLOY

    # ---- CS2: Grafana data sources, provisioned at boot ----
    cat > /opt/monitoring/grafana/datasources.yml <<'DS'
    apiVersion: 1
    datasources:
      - name: Prometheus
        uid: prometheus
        type: prometheus
        url: http://localhost:9090
        isDefault: true
      - name: Loki
        uid: loki
        type: loki
        url: http://localhost:3100
    DS

    # ---- CS2: Grafana alert rule (log-based), provisioned at boot ----
    cat > /opt/monitoring/grafana/alert_rules.yml <<'GRULES'
    apiVersion: 1
    groups:
      - orgId: 1
        name: security
        folder: CS2
        interval: 1m
        rules:
          - uid: ssh-bruteforce
            title: SSH brute force
            condition: C
            data:
              - refId: A
                relativeTimeRange:
                  from: 600
                  to: 0
                datasourceUid: loki
                model:
                  refId: A
                  expr: 'sum(count_over_time({job="journal"} |= "Failed password" [2m])) or vector(0)'
                  queryType: range
              - refId: B
                datasourceUid: __expr__
                model:
                  refId: B
                  type: reduce
                  expression: A
                  reducer: last
              - refId: C
                datasourceUid: __expr__
                model:
                  refId: C
                  type: threshold
                  expression: B
                  conditions:
                    - evaluator:
                        type: gt
                        params: [2]
            noDataState: OK
            execErrState: Error
            for: 0s
            annotations:
              summary: 3+ failed SSH logins in 2 minutes on cs2-srv01
            labels:
              severity: critical
              type: bruteforce
    GRULES

    docker run -d --name prometheus --restart unless-stopped \
      --net="host" \
      -v /opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml \
      -v /opt/monitoring/alert_rules.yml:/etc/prometheus/alert_rules.yml \
      prom/prometheus:v3.16.0 --config.file=/etc/prometheus/prometheus.yml

    docker run -d --name alertmanager --restart unless-stopped \
      -p 9093:9093 \
      -v /opt/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
      prom/alertmanager:v0.34.2 --config.file=/etc/alertmanager/alertmanager.yml

    docker run -d --name loki --restart unless-stopped \
      -p 3100:3100 \
      -v /opt/monitoring/loki.yml:/etc/loki/local-config.yaml \
      -v loki-data:/loki \
      grafana/loki:3.7.9 -config.file=/etc/loki/local-config.yaml

    docker run -d --name alloy --restart unless-stopped \
      --net="host" \
      -v /opt/monitoring/config.alloy:/etc/alloy/config.alloy \
      grafana/alloy:v1.21.3 run --server.http.listen-addr=0.0.0.0:12345 \
      --storage.path=/var/lib/alloy/data /etc/alloy/config.alloy

    docker run -d --name grafana --restart unless-stopped \
      --net="host" \
      -v /opt/monitoring/grafana/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml \
      -v /opt/monitoring/grafana/alert_rules.yml:/etc/grafana/provisioning/alerting/alert_rules.yml \
      grafana/grafana:13.3.0
  EOF

  tags = { Name = "${var.project_name}-monitoring" }
}
