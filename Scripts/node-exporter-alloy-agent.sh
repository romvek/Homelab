#!/usr/bin/env bash
# ==============================================================================
# ROMVEK HOMELAB SOC - AGENT DEPLOYMENT PIPELINE
# Target: Node Exporter (Metrics) & Grafana Alloy (Logs)
# ==============================================================================
set -euo pipefail

# Minimalist Green Theme Aesthetics
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[+] $1${NC}"; }
warn() { echo -e "${GREEN}[!] $1${NC}"; }

# Enforce root privileges
if [[ $EUID -ne 0 ]]; then
   warn "This script must be executed with root privileges (sudo)."
   exit 1
fi

# Fallback Configuration & Auto-Detection
DEFAULT_LOKI="http://loki.romvek.internal:3100/loki/api/v1/push"
echo -e "${GREEN}"
read -p "Enter Loki push endpoint [Default: $DEFAULT_LOKI]: " USER_INPUT
echo -e "${NC}"
LOKI_URL=${USER_INPUT:-$DEFAULT_LOKI}

log "Validating baseline system dependencies..."
for pkg in curl wget gpg tar; do
    if ! command -v "$pkg" &>/dev/null; then
        apt-get update -qq && apt-get install -y "$pkg"
    fi
done

# ==============================================================================
# PART 1: NODE EXPORTER SETUP
# ==============================================================================
log "Initializing Standalone Node Exporter Setup..."
cd /tmp

# Clean API routing stream without local file write side-effects
NODE_VERSION_URL=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest \
  | grep "browser_download_url.*linux-amd64.tar.gz" \
  | cut -d '"' -f 4)

wget -qO node_exporter.tar.gz "$NODE_VERSION_URL"
tar -xf node_exporter.tar.gz
mv /tmp/node_exporter.*linux-amd64/node_exporter /usr/local/bin/
rm -rf /tmp/node_exporter*

# Setup unprivileged system user if missing
if ! id -u node_exporter &>/dev/null; then
    useradd -rs /bin/false node_exporter
fi

log "Writing systemd unit configuration for Node Exporter..."
cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter

# ==============================================================================
# PART 2: GRAFANA ALLOY SETUP (Replacing Legacy Promtail)
# ==============================================================================
log "Evaluating legacy log engines..."
if systemctl is-active --quiet promtail 2>/dev/null; then
    warn "Legacy Promtail instance identified. Decommissioning service..."
    systemctl stop promtail || true
    systemctl disable promtail || true
    rm -f /etc/systemd/system/promtail.service
fi

log "Provisioning Grafana software signing keys..."
mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list

log "Installing Grafana Alloy daemon tracking package..."
apt-get update -qq
apt-get install -y alloy

log "Elevating Alloy system access to security logs via adm membership..."
usermod -aG adm alloy

log "Writing unified River pipeline configuration layer..."
cat <<EOF > /etc/alloy/config.alloy
logging {
  level  = "info"
  format = "logfmt"
}

// Local log tracking discovery engine
local.file_match "system_logs" {
  path_targets = [
    { "__address__" = "localhost", "__path__" = "/var/log/syslog", "job" = "syslog", "instance" = constants.hostname },
    { "__address__" = "localhost", "__path__" = "/var/log/auth.log", "job" = "auth", "instance" = constants.hostname },
    { "__address__" = "localhost", "__path__" = "/var/log/**/*.log", "job" = "varlogs", "instance" = constants.hostname }
  ]
}

// Active dynamic log parser 
loki.source.file "log_scrape" {
  targets    = local.file_match.system_logs.targets
  forward_to = [loki.write.loki_service.receiver]
}

// Ingestion endpoint target mapping
loki.write "loki_service" {
  endpoint {
    url = "${LOKI_URL}"
  }
}
EOF

log "Enforcing configuration formatting lint rules..."
alloy fmt /etc/alloy/config.alloy

systemctl daemon-reload
systemctl restart alloy
systemctl enable alloy

# ==============================================================================
# AUDIT PIPELINE
# ==============================================================================
log "Verifying active runtime daemon states:"
echo "----------------------------------------------------------------"
systemctl status node_exporter --no-pager | grep -E "Active:" || true
systemctl status alloy --no-pager | grep -E "Active:" || true
echo "----------------------------------------------------------------"
log "Pipeline compilation complete. Homelab node is shipping data."