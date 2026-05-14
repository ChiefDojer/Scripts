# PortScan.sh — TCP Port Scanner

Cross-platform TCP port scanner written in Bash. Audits open ports on localhost first, then auto-detects the local /24 subnet and scans all live hosts. Uses **nmap** when available for speed and accuracy; gracefully falls back to pure Bash `/dev/tcp` connections when nmap is absent. Useful for developers mapping what services are exposed on their machine and local network.

Works on **Linux**, **macOS**, and **Windows** (Git Bash / WSL).
Requires Bash 3.2+. Optional: `nmap` (strongly recommended), `timeout` or `gtimeout`, `ping`.

## Execution

```bash
# Linux / macOS
chmod +x PortScan/PortScan.sh
./PortScan/PortScan.sh

# Windows — Git Bash
bash PortScan/PortScan.sh

# Windows — .bat launcher (PowerShell / cmd / Explorer double-click)
.\PortScan\PortScan.bat

# Windows — PowerShell with explicit path
& "C:\Program Files\Git\bin\bash.exe" PortScan\PortScan.sh

# Save output
./PortScan/PortScan.sh | tee scan-report.txt
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--host <ip>` | — | Scan a specific host; skips subnet scan |
| `--ports common` | ✓ | ~140 curated ports (web, DB, DevOps, security) |
| `--ports all` | — | Full range 1–65535 (slow without nmap) |
| `--ports <list>` | — | Comma-separated custom list, e.g. `22,80,443` |
| `--no-subnet` | — | Skip local subnet scan |
| `--timeout <sec>` | `1` | TCP connect timeout for bash fallback |

## Examples

```bash
# Default: localhost + subnet, common ports
./PortScan/PortScan.sh

# Scan all ports on localhost only
./PortScan/PortScan.sh --ports all --no-subnet

# Scan a specific host with a custom port list
./PortScan/PortScan.sh --host 192.168.1.50 --ports 22,80,443,3306,5432

# Increase timeout for slow/remote hosts (bash fallback only)
./PortScan/PortScan.sh --timeout 2
```

## Audit Sections (3 Sections)

### 1. Localhost

Scans `127.0.0.1` (or `--host` target) for open TCP ports. With nmap, runs `nmap -sT --open`; with bash fallback, spawns background `/dev/tcp` probes in batches of 64 with progress reporting.

### 2. Local Subnet

Auto-detects the local /24 subnet from routing tables or interface addresses (platform-adaptive). Discovers live hosts via `nmap -sn` or parallel ping, then port-scans each remote host. Skips the machine's own IP to avoid double-counting. Disabled when `--host` is specified.

Platform detection for subnet:
- **Linux**: `ip route show` → `hostname -I` fallback
- **WSL**: `ip route` (skips `172.x` WSL bridge) → `cmd.exe /c ipconfig` fallback
- **macOS**: `route get default` + `ipconfig getifaddr`
- **Windows (Git Bash)**: `ipconfig` IPv4 address

### 3. Summary

Prints counters (hosts scanned, total open ports, port mode, backend) and a deduplicated table of all open ports across all scanned hosts with service names.

## Common Ports Preset (~140 ports)

Covers:
- **System / network**: FTP, SSH, Telnet, SMTP, DNS, DHCP, TFTP, NTP, RPC, SNMP, LDAP, Syslog, IPP, rsync, OpenVPN, ISAKMP
- **Web / proxy**: HTTP, HTTPS, HTTP-alt (8000, 8080, 8081, 8443, 8888), Squid (3128), Consul (8500)
- **Databases**: MySQL (3306), PostgreSQL (5432), MSSQL (1433), Oracle (1521), MongoDB (27017/27018), Redis (6379), CouchDB (5984), Elasticsearch (9200/9300), InfluxDB (8086), Memcached (11211), Neo4j (7474), Cassandra (7000)
- **DevOps / cloud**: Docker (2375/2376), Kubernetes API (6443), Prometheus (9090), Kibana (5601), Grafana-compatible, Webmin (10000), SonarQube (9000), Jenkins/DB2 (50000), HDFS NameNode (50070)
- **Messaging**: AMQP (5672/5671), Kafka (9092/9093), MQTT (1883), RabbitMQ UI (15672), ActiveMQ (61616/8161), Zookeeper (2181)
- **Remote access**: RDP (3389), VNC (5900), SOCKS (1080), PPTP (1723), NFS (2049)
- **Dev frameworks**: Angular dev (4200), Flask/dev (5000), Sinatra (4567), GlassFish (4848), WebLogic (7001)

## Backend Comparison

| | nmap | bash /dev/tcp |
|---|---|---|
| Speed (common ports) | ~2–5 sec | ~15–60 sec |
| Speed (all ports) | ~2–10 min | ~15–30 min |
| UDP support | No (`-sT` flag) | No |
| Host discovery | `nmap -sn` (reliable) | ICMP ping (may fail as non-root) |
| Dependency | Requires nmap | None beyond Bash |
