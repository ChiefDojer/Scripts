#!/usr/bin/env bash
# =================================================================
# PortScan.sh
# Purpose: Scan open TCP ports on localhost and the local subnet
# Platforms: Linux, macOS, Windows (Git Bash / WSL)
# Requires:  bash 3.2+. Optional: nmap, timeout/gtimeout, ping
# =================================================================

set -uo pipefail

# ------------------------------------------------------------------ colors ---
if [[ -t 1 ]]; then
    YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
    RED='\033[0;31m'; GRAY='\033[0;90m'; NC='\033[0m'
else
    YELLOW=''; CYAN=''; GREEN=''; RED=''; GRAY=''; NC=''
fi

# ---------------------------------------------------------------- platform ---
detect_platform() {
    local s
    s=$(uname -s 2>/dev/null) || s="Windows_NT"
    case "$s" in
        Linux*)        grep -qi microsoft /proc/version 2>/dev/null && echo "wsl" || echo "linux" ;;
        Darwin*)       echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)             echo "unknown" ;;
    esac
}

PLATFORM=$(detect_platform)

# ----------------------------------------------------------------- helpers ---
header()    { printf "\n${YELLOW}=== [ %s ] ===${NC}\n" "$1"; }
subheader() { printf "\n${GRAY}--- %s ---${NC}\n" "$1"; }
info()      { printf "${CYAN}[i]${NC} %s\n" "$1"; }
ok()        { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn()      { printf "${RED}[!]${NC} %s\n" "$1" >&2; }
cmd_exists(){ command -v "$1" &>/dev/null; }

# --------------------------------------------------------------- CLI args ---
PORT_MODE="common"
CUSTOM_PORTS=""
SCAN_SUBNET=true
TIMEOUT_SEC=1
EXTRA_HOST=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Scans open TCP ports on localhost then the local /24 subnet.
Uses nmap when available; falls back to bash /dev/tcp.

Options:
  --host <ip>        Scan a specific host only (skips subnet scan)
  --ports common     Scan ~140 curated common ports (default)
  --ports all        Scan full range 1-65535 (slow without nmap)
  --ports <list>     Comma-separated list, e.g. 22,80,443,8080
  --no-subnet        Skip local subnet scan
  --timeout <sec>    TCP connect timeout for bash fallback (default: 1)
  --help             Show this help and exit

Examples:
  $(basename "$0")
  $(basename "$0") --ports all --no-subnet
  $(basename "$0") --host 192.168.1.50 --ports 22,80,443,8080
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)      EXTRA_HOST="${2:-}"; shift 2 ;;
        --ports)
            case "${2:-}" in
                common) PORT_MODE="common"; shift 2 ;;
                all)    PORT_MODE="all";    shift 2 ;;
                *)      PORT_MODE="custom"; CUSTOM_PORTS="${2:-}"; shift 2 ;;
            esac ;;
        --no-subnet) SCAN_SUBNET=false; shift ;;
        --timeout)   TIMEOUT_SEC="${2:-1}"; shift 2 ;;
        --help|-h)   usage ;;
        *)           warn "Unknown option: $1"; shift ;;
    esac
done

# ----------------------------------------------------------- port presets ---
# ~140 ports covering: system services, web, databases, DevOps, messaging, security tools
COMMON_PORTS="21 22 23 25 53 67 69 80 88 110 111 119 123 135 137 139 143 \
161 194 389 443 445 465 500 514 515 587 631 636 873 993 995 \
1080 1194 1433 1521 1723 1883 1900 2049 2082 2083 2181 2375 2376 \
3000 3128 3268 3306 3389 3690 4200 4243 4443 4444 4567 4848 \
5000 5001 5432 5601 5671 5672 5900 5984 \
6379 6443 7000 7001 7070 7443 7474 7700 \
8000 8001 8008 8080 8081 8083 8086 8088 8161 8443 8444 8500 8888 \
9000 9090 9092 9093 9200 9300 9418 9999 \
10000 11211 15672 16379 27017 27018 28017 50000 50070 61616"

build_port_list() {
    case "$PORT_MODE" in
        common) echo "$COMMON_PORTS" ;;
        all)    seq 1 65535 | tr '\n' ' ' ;;
        custom) echo "$CUSTOM_PORTS" | tr ',' ' ' ;;
    esac
}

PORT_LIST=$(build_port_list)
PORT_COUNT=$(echo "$PORT_LIST" | wc -w | tr -d ' ')

# --------------------------------------------------------- backend detect ---
USE_NMAP=false
cmd_exists nmap && USE_NMAP=true

TIMEOUT_BIN=""
if cmd_exists timeout; then
    TIMEOUT_BIN="timeout"
elif cmd_exists gtimeout; then
    TIMEOUT_BIN="gtimeout"
fi

# ------------------------------------------------------ all-mode warning ---
if [[ "$PORT_MODE" == "all" ]] && ! $USE_NMAP; then
    warn "Scanning 65535 ports without nmap can take 15-30 min per host."
    warn "Install nmap for significantly faster results."
fi

# ---------------------------------------------------------- temp dir/cleanup ---
TMPDIR_SCAN=$(mktemp -d) || { warn "Failed to create temp directory."; exit 1; }
trap 'rm -rf "$TMPDIR_SCAN"' EXIT INT TERM

BATCH_SIZE=64

# -------------------------------------------------------- service name map ---
svc_name() {
    case "$1" in
        21)    echo "ftp" ;;         22)    echo "ssh" ;;
        23)    echo "telnet" ;;      25)    echo "smtp" ;;
        53)    echo "dns" ;;         67)    echo "dhcp-server" ;;
        69)    echo "tftp" ;;        80)    echo "http" ;;
        88)    echo "kerberos" ;;    110)   echo "pop3" ;;
        111)   echo "rpcbind" ;;     119)   echo "nntp" ;;
        123)   echo "ntp" ;;         135)   echo "msrpc" ;;
        137)   echo "netbios-ns" ;;  139)   echo "netbios" ;;
        143)   echo "imap" ;;        161)   echo "snmp" ;;
        194)   echo "irc" ;;         389)   echo "ldap" ;;
        443)   echo "https" ;;       445)   echo "smb" ;;
        465)   echo "smtps" ;;       500)   echo "isakmp" ;;
        514)   echo "syslog" ;;      515)   echo "lpd" ;;
        587)   echo "smtp-sub" ;;    631)   echo "ipp" ;;
        636)   echo "ldaps" ;;       873)   echo "rsync" ;;
        993)   echo "imaps" ;;       995)   echo "pop3s" ;;
        1080)  echo "socks" ;;       1194)  echo "openvpn" ;;
        1433)  echo "mssql" ;;       1521)  echo "oracle" ;;
        1723)  echo "pptp" ;;        1883)  echo "mqtt" ;;
        1900)  echo "upnp" ;;        2049)  echo "nfs" ;;
        2181)  echo "zookeeper" ;;   2375)  echo "docker" ;;
        2376)  echo "docker-tls" ;;  3000)  echo "dev-http" ;;
        3128)  echo "squid" ;;       3268)  echo "msft-gc" ;;
        3306)  echo "mysql" ;;       3389)  echo "rdp" ;;
        3690)  echo "svn" ;;         4200)  echo "angular-dev" ;;
        4243)  echo "docker-alt" ;;  4444)  echo "metasploit" ;;
        4567)  echo "sinatra" ;;     4848)  echo "glassfish" ;;
        5000)  echo "flask/upnp" ;;  5001)  echo "dev-https" ;;
        5432)  echo "postgres" ;;    5601)  echo "kibana" ;;
        5671)  echo "amqps" ;;       5672)  echo "amqp" ;;
        5900)  echo "vnc" ;;         5984)  echo "couchdb" ;;
        6379)  echo "redis" ;;       6443)  echo "k8s-api" ;;
        7000)  echo "cassandra" ;;   7001)  echo "weblogic" ;;
        7070)  echo "realserver" ;;  7474)  echo "neo4j" ;;
        8000)  echo "dev-http" ;;    8001)  echo "dev-http" ;;
        8008)  echo "http-alt" ;;    8080)  echo "http-alt" ;;
        8081)  echo "http-alt" ;;    8083)  echo "mqtt-ws" ;;
        8086)  echo "influxdb" ;;    8088)  echo "riak" ;;
        8161)  echo "activemq-web";; 8443)  echo "https-alt" ;;
        8444)  echo "https-alt" ;;   8500)  echo "consul" ;;
        8888)  echo "jupyter" ;;     9000)  echo "sonar/php-fpm" ;;
        9090)  echo "prometheus" ;;  9092)  echo "kafka" ;;
        9093)  echo "kafka-tls" ;;   9200)  echo "elasticsearch" ;;
        9300)  echo "elastic-tcp" ;; 9418)  echo "git" ;;
        9999)  echo "abyss" ;;       10000) echo "webmin" ;;
        11211) echo "memcached" ;;   15672) echo "rabbitmq-ui" ;;
        16379) echo "redis-cluster";;27017) echo "mongodb" ;;
        27018) echo "mongo-shard" ;; 28017) echo "mongo-web" ;;
        50000) echo "db2/jenkins" ;; 50070) echo "hdfs-namenode" ;;
        61616) echo "activemq" ;;    *)     echo "unknown" ;;
    esac
}

# ------------------------------------------------------- bash port scanner ---
# Runs in background; touches a marker file if port is open.
scan_port_bg() {
    local host=$1 port=$2 marker=$3
    if [[ -n "$TIMEOUT_BIN" ]]; then
        $TIMEOUT_BIN "$TIMEOUT_SEC" bash -c \
            "exec 3<>/dev/tcp/$host/$port" 2>/dev/null \
            && touch "$marker" || true
    else
        # Without timeout, filtered ports may stall briefly at TCP stack timeout
        (exec 3<>/dev/tcp/"$host"/"$port") 2>/dev/null \
            && touch "$marker" || true
    fi
}

scan_host_bash() {
    local host=$1
    local host_safe="${host//./_}"
    local pids="" count=0 scanned=0

    printf "${CYAN}[i]${NC} Scanning %d ports on %s via bash/dev/tcp (batch=%d)...\n" \
        "$PORT_COUNT" "$host" "$BATCH_SIZE" >&2

    for port in $PORT_LIST; do
        local marker="$TMPDIR_SCAN/${host_safe}_${port}"
        scan_port_bg "$host" "$port" "$marker" &
        pids="$pids $!"
        count=$((count + 1))
        scanned=$((scanned + 1))
        if [[ $count -ge $BATCH_SIZE ]]; then
            for pid in $pids; do wait "$pid" 2>/dev/null || true; done
            pids=""; count=0
            printf "\r  Progress: %d/%d" "$scanned" "$PORT_COUNT" >&2
        fi
    done
    # flush remaining batch
    for pid in $pids; do wait "$pid" 2>/dev/null || true; done
    printf "\r  Progress: %d/%d\n" "$scanned" "$PORT_COUNT" >&2

    # collect open ports from marker files
    local open=""
    for f in "$TMPDIR_SCAN"/${host_safe}_*; do
        [[ -f "$f" ]] || continue
        local p="${f##*_}"
        open="$open $p"
        rm -f "$f"
    done
    echo "$open"
}

# -------------------------------------------------------- nmap port scanner ---
scan_host_nmap() {
    local host=$1
    local port_arg
    case "$PORT_MODE" in
        common) port_arg=$(echo "$COMMON_PORTS" | tr ' ' ',') ;;
        all)    port_arg="1-65535" ;;
        custom) port_arg=$(echo "$CUSTOM_PORTS" | tr ',' ' ' | tr ' ' ',') ;;
    esac
    nmap -sT --open -p "$port_arg" "$host" 2>/dev/null \
        | awk '/^[0-9]+\/tcp[[:space:]]+open/{split($1,a,"/"); printf "%s ", a[1]}' \
        || true
}

# ---------------------------------------------------------- result display ---
print_open_ports() {
    local host=$1 open_ports=$2
    if [[ -z "${open_ports// /}" ]]; then
        info "No open ports found on $host"
        return
    fi
    printf "\n${GREEN}  %-10s %-8s %s${NC}\n" "PORT" "STATE" "SERVICE"
    printf "  %-10s %-8s %s\n" "----------" "-----" "-------"
    for port in $(echo "$open_ports" | tr ' ' '\n' | sort -n | grep -v '^$'); do
        printf "  %-10s %-8s %s\n" "${port}/tcp" "open" "$(svc_name "$port")"
    done
}

# -------------------------------------------- live host discovery (nmap) ---
discover_hosts_nmap() {
    local subnet=$1
    nmap -sn "$subnet" 2>/dev/null \
        | awk '/Nmap scan report/{gsub(/[()]/,"",$NF); print $NF}' \
        || true
}

# ------------------------------------------- live host discovery (bash) ---
ping_host() {
    local ip=$1
    case "$PLATFORM" in
        macos)   ping -c 1 -t 1   "$ip" &>/dev/null ;;
        windows) ping -n 1 -w 500 "$ip" &>/dev/null ;;
        *)       ping -c 1 -W 1   "$ip" &>/dev/null ;;
    esac
}

discover_hosts_bash() {
    local subnet=$1
    local base="${subnet%.*}"
    local pids="" count=0

    printf "${CYAN}[i]${NC} Pinging %s.1-254 to find live hosts...\n" "$base" >&2

    for i in $(seq 1 254); do
        local ip="$base.$i"
        local marker="$TMPDIR_SCAN/alive_${i}"
        (ping_host "$ip" && echo "$ip" > "$marker") &
        pids="$pids $!"
        count=$((count + 1))
        if [[ $count -ge 32 ]]; then
            for pid in $pids; do wait "$pid" 2>/dev/null || true; done
            pids=""; count=0
        fi
    done
    for pid in $pids; do wait "$pid" 2>/dev/null || true; done

    local hosts=""
    for f in "$TMPDIR_SCAN"/alive_*; do
        [[ -f "$f" ]] && hosts="$hosts $(cat "$f")"
        rm -f "$f"
    done
    echo "$hosts"
}

# ------------------------------------------------------ subnet detection ---
detect_local_subnet() {
    local subnet="" ip="" iface=""
    case "$PLATFORM" in
        linux)
            subnet=$(ip route show 2>/dev/null \
                | grep -v default | grep "/" | awk '{print $1}' | head -1)
            if [[ -z "$subnet" ]]; then
                ip=$(hostname -I 2>/dev/null | awk '{print $1}')
                [[ -n "$ip" ]] && subnet="${ip%.*}.0/24"
            fi
            ;;
        wsl)
            # Skip 172.x WSL-internal bridge; prefer the Windows-facing adapter
            subnet=$(ip route show 2>/dev/null \
                | grep -v default | grep "/" | awk '{print $1}' \
                | grep -v "^172\." | head -1)
            if [[ -z "$subnet" ]]; then
                ip=$(cmd.exe /c "ipconfig" 2>/dev/null | tr -d '\r' \
                    | grep -i "ipv4" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                [[ -n "$ip" ]] && subnet="${ip%.*}.0/24"
            fi
            ;;
        macos)
            iface=$(route get default 2>/dev/null | awk '/interface:/{print $2}' | head -1)
            [[ -z "$iface" ]] && iface="en0"
            ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
            [[ -n "$ip" ]] && subnet="${ip%.*}.0/24"
            ;;
        windows)
            ip=$(ipconfig 2>/dev/null | grep -i "ipv4" | head -1 \
                | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            [[ -n "$ip" ]] && subnet="${ip%.*}.0/24"
            ;;
        *)
            ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            [[ -n "$ip" ]] && subnet="${ip%.*}.0/24"
            ;;
    esac
    echo "$subnet"
}

get_local_ip() {
    local ip="" iface=""
    case "$PLATFORM" in
        linux|wsl) ip=$(hostname -I 2>/dev/null | awk '{print $1}') ;;
        macos)
            iface=$(route get default 2>/dev/null | awk '/interface:/{print $2}' | head -1)
            ip=$(ipconfig getifaddr "${iface:-en0}" 2>/dev/null || true)
            ;;
        windows)
            ip=$(ipconfig 2>/dev/null | grep -i "ipv4" | head -1 \
                | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            ;;
        *)
            ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            ;;
    esac
    echo "$ip"
}

# ---------------------------------------------------------------- counters ---
hosts_scanned=0
total_open=0
open_ports_all=""   # accumulator: "host:port" lines

scan_and_report() {
    local host=$1
    local open_ports

    hosts_scanned=$((hosts_scanned + 1))

    if $USE_NMAP; then
        open_ports=$(scan_host_nmap "$host")
    else
        open_ports=$(scan_host_bash "$host")
    fi

    print_open_ports "$host" "$open_ports"

    for port in $open_ports; do
        [[ -n "$port" ]] || continue
        total_open=$((total_open + 1))
        open_ports_all="${open_ports_all}
${host}:${port}"
    done
}

# =================================================================
printf "\n"
info "Port scanner  (platform: $PLATFORM)"
if $USE_NMAP; then
    nmap_ver=$(nmap --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9.]+' | head -1)
    info "Backend       : nmap ${nmap_ver:-unknown}"
else
    info "Backend       : bash /dev/tcp  (install nmap for speed)"
    if [[ -n "$TIMEOUT_BIN" ]]; then
        info "Timeout cmd   : $TIMEOUT_BIN ${TIMEOUT_SEC}s per port"
    else
        warn "No timeout binary found — filtered ports may cause brief hangs"
    fi
fi
info "Port mode     : $PORT_MODE  ($PORT_COUNT ports per host)"
if $SCAN_SUBNET && [[ -z "$EXTRA_HOST" ]]; then
    info "Subnet scan   : enabled"
else
    info "Subnet scan   : disabled"
fi

# =================================================================
# 1. LOCALHOST
# =================================================================
header "1. LOCALHOST"

TARGET_HOST="${EXTRA_HOST:-127.0.0.1}"
info "Target: $TARGET_HOST"

scan_and_report "$TARGET_HOST"

# =================================================================
# 2. LOCAL SUBNET
# =================================================================
if $SCAN_SUBNET && [[ -z "$EXTRA_HOST" ]]; then
    header "2. LOCAL SUBNET"

    SUBNET=$(detect_local_subnet)

    if [[ -z "$SUBNET" ]]; then
        warn "Could not detect local subnet. Use --host <ip> to scan a specific target."
    else
        info "Detected subnet: $SUBNET"

        if $USE_NMAP; then
            info "Discovering live hosts (nmap -sn) ..."
            LIVE_HOSTS=$(discover_hosts_nmap "$SUBNET")
        else
            LIVE_HOSTS=$(discover_hosts_bash "$SUBNET")
        fi

        if [[ -z "${LIVE_HOSTS// /}" ]]; then
            warn "No live hosts found on $SUBNET"
            info "Possible causes: ICMP blocked by firewall, no other hosts present, or run as root"
        else
            LOCAL_IP=$(get_local_ip)
            for host in $LIVE_HOSTS; do
                [[ "$host" == "127.0.0.1" ]] && continue
                [[ -n "$LOCAL_IP" && "$host" == "$LOCAL_IP" ]] && continue
                subheader "Host: $host"
                scan_and_report "$host"
            done
        fi
    fi
fi

# =================================================================
# 3. SUMMARY
# =================================================================
header "3. SUMMARY"

printf "%-42s %s\n" "Hosts scanned:"    "$hosts_scanned"
printf "%-42s %s\n" "Total open ports:" "$total_open"
printf "%-42s %s\n" "Port mode:"        "$PORT_MODE  ($PORT_COUNT ports/host)"
if $USE_NMAP; then
    printf "%-42s %s\n" "Backend:" "nmap"
else
    printf "%-42s %s\n" "Backend:" "bash /dev/tcp"
fi

if [[ -n "${open_ports_all// /}" ]]; then
    printf "\nOpen ports found:\n"
    printf "${GREEN}  %-20s %-12s %s${NC}\n" "HOST" "PORT" "SERVICE"
    printf "  %-20s %-12s %s\n"              "----" "----" "-------"
    echo "$open_ports_all" | grep -v '^$' | sort -t: -k1,1 -k2,2n \
        | while IFS=: read -r h p; do
            [[ -z "${h:-}" || -z "${p:-}" ]] && continue
            printf "  %-20s %-12s %s\n" "$h" "${p}/tcp" "$(svc_name "$p")"
          done
fi
