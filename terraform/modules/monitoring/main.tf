# Monitoring instance: Prometheus + Grafana + Alertmanager. No public IP —
# reachable only through the hub, matching the segmentation design.

data "aws_iam_instance_profile" "lab" {
  name = "cs1-ec2-role"
}

resource "aws_instance" "monitoring" {
  # ... ami, instance_type, subnet_id, vpc_security_group_ids, iam_instance_profile,
  #     key_name — all stay exactly as they are now ...

  # NOTE: plain aws_instance auto-base64-encodes user_data — do NOT wrap this
  # in base64encode() (same rule as the NAT instance; only aws_launch_template
  # needs that wrapper).
  user_data = <<-EOF
    #!/bin/bash
    export DEBIAN_FRONTEND=noninteractive
    until apt-get update -y; do sleep 10; done
    until apt-get install -y docker.io; do sleep 10; done
    systemctl enable --now docker

    mkdir -p /opt/monitoring

    cat > /opt/monitoring/prometheus.yml <<'PROM'
    global:
      scrape_interval: 15s

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

    cat > /opt/monitoring/alertmanager.yml <<'ALERT'
    route:
      receiver: 'null'
    receivers:
      - name: 'null'
    ALERT

    docker run -d --name prometheus --restart unless-stopped \
      --net="host" \
      -v /opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml \
      prom/prometheus --config.file=/etc/prometheus/prometheus.yml

    docker run -d --name alertmanager --restart unless-stopped \
      -p 9093:9093 \
      -v /opt/monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
      prom/alertmanager --config.file=/etc/alertmanager/alertmanager.yml

    docker run -d --name grafana --restart unless-stopped \
      -p 3000:3000 \
      grafana/grafana
  EOF
}
