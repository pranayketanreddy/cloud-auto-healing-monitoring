# Cloud-Based Auto-Healing Monitoring and Recovery System

This project is a prototype-level cloud monitoring and auto-recovery system.

It monitors an Apache web server running on AWS EC2. If Apache stops, the Bash auto-healing script detects the failure and restarts the service automatically using a Cron Job.

## Features

- AWS EC2 Ubuntu server
- Apache web server
- Node Exporter for server metrics
- Prometheus for monitoring
- Grafana for dashboard visualization
- Bash script for auto-healing
- Cron Job for automatic checking
- Recovery log file

## Architecture

```text
User / Browser
     |
     v
Apache Web Server on AWS EC2
     |
     v
Node Exporter collects metrics
     |
     v
Prometheus stores metrics
     |
     v
Grafana displays dashboard

Auto-Healing Script + Cron Job
     |
     v
Checks Apache status every minute
     |
     v
If Apache is down, restart automatically
     |
     v
Write result to log file


**AWS SNS Notification**

Whenever Apache is restarted automatically, the script publishes a message to an AWS SNS Topic.

SNS sends an email notification to all confirmed subscribers.

**Flow**

Apache Stops
↓
Cron Job
↓
Auto Healing Script
↓
Restart Apache
↓
AWS CLI
↓
SNS Topic
↓
Email Notification
