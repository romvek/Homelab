#!/bin/bash
# This script sets up the log ingest pipeline for Pometheus and Grafana.
# It creates the necessary directories, configures node_exporter and Promtail, and starts the services.

# Part 1: Install node_exporter
# Purpose: Collects hardware and OS metrics (CPU, memory, disk, network) from nix machines.

# 1. Download latest node_exporter release and extract
# Move to tempory directory
cd /tmp

curl -LO https:/api.github.com/repos/prometheus/node_exporter/releases/latest \
  | grep "browser_download_url.*linux-amd64.tar.gz" \
  | cut -d : -f 2,3 \
  | tr -d \" \
  | wget -qi -

tar -xvf node_exporter-*-linux-amd64.tar.gz

# Move the node_exporter binary to standard location
sudo mv node_exporter-*-linux-amd64/node_exporter /usr/local/bin/

# 2. Create system user
# Purpose: Runs node_exporter with limited permissions for security.
sudo useradd -rs /bin/false node_exporter

# 3. Create systemd service file for node_exporter
# Purpose: Manages the node_exporter service, allowing it to start on boot and be easily controlled.
# ini, TOML
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# 4. Start and enable the node_exporter service

# Reload systemd to see the  new file
sudo systemctl daemon-reload

# Start the service
sudo systemctl start node_exporter

# Enable service to start on boot
sudo systemctl enable node_exporter

# 5. Verify
sudo systemctl status node_exporter

# Part 2: Install Promtail
# Purpose: Discovers log files, processes them, and sends them to Loki.

# 1 Download and Extract Promtail
cd /tmp

curl -LO https:/api.github.com/repos/grafana/loki/releases/latest \
  | grep "browser_download_url.*linux-amd64.tar.gz" \
  | cut -d : -f 2,3 \
  | tr -d \" \
  | wget -qi -  
  
tar -xvf loki-*-linux-amd64.tar.gz

sudo mv promtail-*-linux-amd64/promtail /usr/local/bin/promtail
sudo chomd +x /usr/local/bin/promtail

# 2. Create configuration
sudo tee /etc/promtail-config.yaml > /dev/null <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

# USed to remember how much of a file was read
positions:
  filename: /tmp/positions.yaml

# Where to send the logs
clients:
  - url: http://loki.romvek.internal:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          # Highly recommend: identify which machine the logs are coming from
          host: ${HOSTNAME}
          __path__: /var/log/*log
EOF

# 3. Create Systemd Service
sudo tee /etc/systemd/system/promtail.service > /dev/null <<EOF
[Unit]
Description=Promtail Service
After=network.target

[Service]
Type=simple
# Ensure promtail can read /var/log. Often required to run as root,
# or added to the 'adm' or 'sysemd-journal' groups.
User=root
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 4. Start and enable
sudo systemctl daemon-reload
sudo systemctl start promtail
sudo systemctl enable promtail

# 5. Verify
sudo systemctl status promtail

-- End of script - -