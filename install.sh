#!/bin/bash

set -e

GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
YELLOW="\e[33m"
RESET="\e[0m"

echo -e "${BLUE}"
echo "=========================================================="
echo " Cloud Auto-Healing Monitoring System Installation"
echo "=========================================================="
echo -e "${RESET}"

#############################################
# Root Check
#############################################

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run using sudo.${RESET}"
    exit 1
fi

#############################################
# Update Packages
#############################################

echo -e "${YELLOW}[1/10] Updating Ubuntu...${RESET}"

apt update -y
apt upgrade -y

#############################################
# Install Required Packages
#############################################

echo -e "${YELLOW}[2/10] Installing Dependencies...${RESET}"

sudo apt install unzip curl -y

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

unzip awscliv2.zip

sudo ./aws/install

#############################################
# Install Apache
#############################################

echo -e "${YELLOW}[3/10] Installing Apache...${RESET}"
apt install -y apache2 wget tar curl apt-transport-https software-properties-common gpg cron

systemctl enable apache2
systemctl start apache2

echo -e "${GREEN}Apache Installed Successfully${RESET}"

#############################################
# Install Node Exporter
#############################################

echo -e "${YELLOW}[4/10] Installing Node Exporter...${RESET}"

cd /tmp

NODE_EXPORTER_VERSION="1.8.2"

wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/

chmod +x /usr/local/bin/node_exporter

#############################################
# Create Node Exporter Service
#############################################

cat >/etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=ubuntu
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable node_exporter

systemctl start node_exporter

echo -e "${GREEN}Node Exporter Installed${RESET}"

#############################################
# Install Prometheus
#############################################

echo -e "${YELLOW}[5/10] Installing Prometheus...${RESET}"

cd /tmp

PROMETHEUS_VERSION="2.54.1"

wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

rm -rf /opt/prometheus

mv prometheus-${PROMETHEUS_VERSION}.linux-amd64 /opt/prometheus

mkdir -p /opt/prometheus/data

#############################################
# Prometheus Configuration
#############################################

cat >/opt/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:

  - job_name: "prometheus"

    static_configs:
      - targets:
        - localhost:9090

  - job_name: "node_exporter"

    static_configs:
      - targets:
        - localhost:9100
EOF

#############################################
# Prometheus Service
#############################################

cat >/etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=ubuntu

ExecStart=/opt/prometheus/prometheus \
--config.file=/opt/prometheus/prometheus.yml \
--storage.tsdb.path=/opt/prometheus/data

Restart=always

[Install]
WantedBy=multi-user.target
EOF

chown -R ubuntu:ubuntu /opt/prometheus

systemctl daemon-reload

systemctl enable prometheus

systemctl start prometheus

echo -e "${GREEN}Prometheus Installed Successfully${RESET}"

#############################################
# Install Grafana
#############################################

echo -e "${YELLOW}[6/10] Installing Grafana...${RESET}"

mkdir -p /etc/apt/keyrings

wget -q -O - https://apt.grafana.com/gpg.key | \
gpg --dearmor -o /etc/apt/keyrings/grafana.gpg

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
> /etc/apt/sources.list.d/grafana.list

apt update -y

apt install grafana -y

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

echo -e "${GREEN}Grafana Installed Successfully${RESET}"

#############################################
# Verify AWS CLI
#############################################

echo -e "${YELLOW}[7/10] Checking AWS CLI...${RESET}"

aws --version

echo ""
echo -e "${BLUE}"
echo "========================================================"
echo " Configure AWS CLI"
echo "========================================================"
echo -e "${RESET}"

echo "Run the following command AFTER installation:"
echo ""
echo "aws configure"
echo ""
echo "Enter:"
echo "AWS Access Key"
echo "AWS Secret Key"
echo "Region : ap-south-2"
echo "Output : json"
echo ""

#############################################
# Install Auto-Healing Script
#############################################

echo -e "${YELLOW}[8/10] Installing Auto-Healing Script...${RESET}"

cat >/usr/local/bin/auto_heal_apache.sh <<'EOF'
#!/bin/bash

SERVICE_NAME="apache2"
LOG_FILE="/var/log/auto_healing.log"

# Replace with your SNS Topic ARN
TOPIC_ARN="arn:aws:iam::926465100998:user/auto-healing-user"

DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

if systemctl is-active --quiet "$SERVICE_NAME"
then
    echo "$DATE_TIME - Apache is running." >> "$LOG_FILE"

else

    echo "$DATE_TIME - Apache stopped. Restarting..." >> "$LOG_FILE"

    systemctl restart "$SERVICE_NAME"

    sleep 5

    if systemctl is-active --quiet "$SERVICE_NAME"
    then

        echo "$DATE_TIME - Apache restarted successfully." >> "$LOG_FILE"

        if aws sts get-caller-identity >/dev/null 2>&1
        then

            aws sns publish \
            --topic-arn "$TOPIC_ARN" \
            --subject "Cloud Auto-Healing Alert" \
            --message "Apache service restarted automatically.

Hostname : $(hostname)

Time : $(date)

Status : SUCCESS"

        fi

    else

        echo "$DATE_TIME - Apache restart failed." >> "$LOG_FILE"

        if aws sts get-caller-identity >/dev/null 2>&1
        then

            aws sns publish \
            --topic-arn "$TOPIC_ARN" \
            --subject "Cloud Auto-Healing FAILED" \
            --message "Apache could not be restarted.

Hostname : $(hostname)

Time : $(date)

Status : FAILED"

        fi

    fi

fi
EOF

chmod +x /usr/local/bin/auto_heal_apache.sh

touch /var/log/auto_healing.log

chmod 644 /var/log/auto_healing.log

echo -e "${GREEN}Auto-Healing Script Installed${RESET}"

#############################################
# Configure Cron Job
#############################################

echo -e "${YELLOW}[9/10] Configuring Cron Job...${RESET}"

(crontab -l 2>/dev/null | grep -v auto_heal_apache.sh || true
echo "* * * * * /usr/local/bin/auto_heal_apache.sh") | crontab -

systemctl enable cron
systemctl restart cron

echo -e "${GREEN}Cron Job Added Successfully${RESET}"

#############################################
# Verify Services
#############################################

echo -e "${YELLOW}[10/10] Verifying Installation...${RESET}"

echo ""

echo "Apache Status"
systemctl is-active apache2

echo ""

echo "Node Exporter Status"
systemctl is-active node_exporter

echo ""

echo "Prometheus Status"
systemctl is-active prometheus

echo ""

echo "Grafana Status"
systemctl is-active grafana-server

echo ""

echo "Cron Status"
systemctl is-active cron

#############################################
# Installation Complete
#############################################

echo ""
echo -e "${GREEN}"
echo "========================================================"
echo " INSTALLATION COMPLETED SUCCESSFULLY"
echo "========================================================"
echo -e "${RESET}"

PUBLIC_IP=$(curl -s ifconfig.me)

echo ""
echo "Access your services:"
echo ""
echo "Apache      : http://$PUBLIC_IP"
echo "Prometheus  : http://$PUBLIC_IP:9090"
echo "Grafana     : http://$PUBLIC_IP:3000"
echo "NodeExporter: http://$PUBLIC_IP:9100/metrics"
