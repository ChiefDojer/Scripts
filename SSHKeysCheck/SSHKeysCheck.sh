#!/usr/bin/env bash
# =================================================================
# SSHKeysCheck.sh
# Purpose: Audit all SSH keys and SSH configuration on this machine
# Platforms: Linux, macOS, Windows (Git Bash / WSL)
# Requires:  bash 3.2+, ssh. Optional: ssh-keygen, git, ssh-add
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
        Linux*)  grep -qi microsoft /proc/version 2>/dev/null && echo "wsl" || echo "linux" ;;
        Darwin*) echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)       echo "unknown" ;;
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

# ---------------------------------------------------------------- counters ---
key_count=0
key_with_passphrase=0
key_without_passphrase=0
key_unknown_passphrase=0
agent_key_count=0
host_entry_count=0
known_host_count=0
authorized_key_count=0

key_types=""       # accumulator: "type  fingerprint  comment"  per key
host_entries=""    # accumulator: Host aliases with their IdentityFile

printf "\n"
info "Auditing SSH keys and configuration...  (platform: $PLATFORM)"

# =================================================================
# 1. SSH DIRECTORY
# =================================================================
header "1. SSH DIRECTORY"

SSH_DIR="$HOME/.ssh"

if [[ ! -d "$SSH_DIR" ]]; then
    warn "~/.ssh directory not found. SSH may not be configured on this machine."
else
    perms=$(stat -c "%a" "$SSH_DIR" 2>/dev/null \
            || stat -f "%OLp" "$SSH_DIR" 2>/dev/null \
            || echo "unknown")
    printf "Path        : %s\n" "$SSH_DIR"
    printf "Permissions : %s" "$perms"
    if [[ "$perms" != "700" && "$perms" != "unknown" ]]; then
        printf "  ${RED}(should be 700)${NC}\n"
    else
        printf "  ${GREEN}(OK)${NC}\n"
    fi

    echo ""
    echo "Contents:"
    ls -la "$SSH_DIR" 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        printf "  %s\n" "$line"
    done
fi

# =================================================================
# 2. PRIVATE & PUBLIC KEY PAIRS
# =================================================================
header "2. KEY PAIRS"

if [[ ! -d "$SSH_DIR" ]]; then
    echo "Skipped — ~/.ssh not found."
else
    while IFS= read -r key_file; do
        pub_file="${key_file}.pub"
        [[ -f "$pub_file" ]] || continue

        key_count=$((key_count + 1))
        printf "\n"
        subheader "Key #${key_count}: $(basename "$key_file")"

        # ---- Type & fingerprint ----
        if cmd_exists ssh-keygen; then
            fingerprint=$(ssh-keygen -l -f "$key_file" 2>/dev/null || true)
            if [[ -n "$fingerprint" ]]; then
                printf "Fingerprint : %s\n" "$fingerprint"
                key_types="${key_types}${fingerprint}"$'\n'
            else
                printf "Fingerprint : (could not read — key may be encrypted without agent)\n"
            fi
        fi

        # ---- Public key ----
        pub_content=$(cat "$pub_file")
        key_type=$(echo "$pub_content" | awk '{print $1}')
        key_comment=$(echo "$pub_content" | awk '{$1=$2=""; print $0}' | sed 's/^ *//')
        printf "Type        : %s\n" "$key_type"
        printf "Comment     : %s\n" "${key_comment:-(none)}"
        printf "Public key  : %s\n" "$pub_content"

        # ---- File permissions ----
        priv_perms=$(stat -c "%a" "$key_file" 2>/dev/null \
                     || stat -f "%OLp" "$key_file" 2>/dev/null \
                     || echo "unknown")
        pub_perms=$(stat -c "%a" "$pub_file" 2>/dev/null \
                    || stat -f "%OLp" "$pub_file" 2>/dev/null \
                    || echo "unknown")
        printf "Permissions : private=%s" "$priv_perms"
        if [[ "$priv_perms" != "600" && "$priv_perms" != "unknown" ]]; then
            printf "  ${RED}(should be 600)${NC}"
        else
            printf "  ${GREEN}(OK)${NC}"
        fi
        printf "  public=%s\n" "$pub_perms"

        # ---- Passphrase check ----
        if cmd_exists ssh-keygen; then
            # ssh-keygen -y tries to export the public key from private.
            # Without -P it will prompt — pass empty passphrase.
            # Exit 0 means no passphrase; exit non-0 means passphrase protected or error.
            ssh-keygen -y -P "" -f "$key_file" &>/dev/null
            check_rc=$?
            if [[ $check_rc -eq 0 ]]; then
                printf "Passphrase  : ${RED}NONE${NC} (private key is unprotected)\n"
                key_without_passphrase=$((key_without_passphrase + 1))
            else
                printf "Passphrase  : ${GREEN}SET${NC} (key is passphrase-protected)\n"
                key_with_passphrase=$((key_with_passphrase + 1))
            fi
        else
            printf "Passphrase  : (ssh-keygen not available — cannot check)\n"
            key_unknown_passphrase=$((key_unknown_passphrase + 1))
        fi

    done < <(find "$SSH_DIR" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" 2>/dev/null | sort)

    [[ $key_count -eq 0 ]] && echo "No standard key pairs found (id_*) in ~/.ssh/"
fi

# =================================================================
# 3. SSH CONFIG FILE
# =================================================================
header "3. SSH CONFIG (~/.ssh/config)"

config_file="$SSH_DIR/config"

if [[ ! -f "$config_file" ]]; then
    echo "No ~/.ssh/config file found."
else
    config_perms=$(stat -c "%a" "$config_file" 2>/dev/null \
                   || stat -f "%OLp" "$config_file" 2>/dev/null \
                   || echo "unknown")
    printf "Path        : %s\n" "$config_file"
    printf "Permissions : %s\n" "$config_perms"
    echo ""

    current_host=""
    while IFS= read -r line; do
        # Skip blank lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

        if echo "$trimmed" | grep -qiE "^Host[[:space:]]"; then
            current_host=$(echo "$trimmed" | sed -E 's/^Host[[:space:]]+//')
            host_entry_count=$((host_entry_count + 1))
            printf "\nHost: ${CYAN}%s${NC}\n" "$current_host"
            host_entries="${host_entries}${current_host}"$'\n'
        elif [[ -n "$current_host" ]]; then
            key=$(echo "$trimmed" | awk '{print $1}')
            val=$(echo "$trimmed" | cut -d' ' -f2-)
            printf "  %-20s %s\n" "$key" "$val"
        fi
    done < "$config_file"

    [[ $host_entry_count -eq 0 ]] && echo "Config file is empty or has no Host entries."
fi

# =================================================================
# 4. SSH AGENT (loaded keys)
# =================================================================
header "4. SSH AGENT"

if cmd_exists ssh-add; then
    agent_out=$(ssh-add -l 2>&1 || true)
    if echo "$agent_out" | grep -q "no identities"; then
        echo "SSH agent is running but has no loaded keys."
    elif echo "$agent_out" | grep -qiE "could not open|connect.*agent|no such file"; then
        echo "SSH agent is not running or socket not found."
    else
        echo "Keys loaded in SSH agent:"
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            printf "  * %s\n" "$line"
            agent_key_count=$((agent_key_count + 1))
        done <<< "$agent_out"
    fi
else
    echo "ssh-add not available — cannot query SSH agent."
fi

# =================================================================
# 5. KNOWN HOSTS
# =================================================================
header "5. KNOWN HOSTS (~/.ssh/known_hosts)"

known_hosts_file="$SSH_DIR/known_hosts"

if [[ ! -f "$known_hosts_file" ]]; then
    echo "No known_hosts file found."
else
    total=$(grep -vc '^[[:space:]]*#\|^[[:space:]]*$' "$known_hosts_file" 2>/dev/null || echo "0")
    printf "Total entries : %s\n" "$total"
    known_host_count=$total

    echo ""
    echo "Unique hostnames / IPs:"
    grep -v '^[[:space:]]*#\|^[[:space:]]*$' "$known_hosts_file" 2>/dev/null \
        | awk '{print $1}' \
        | tr ',' '\n' \
        | sed 's/^\[//;s/\]:.*//' \
        | sort -u \
        | while IFS= read -r h; do
            printf "  * %s\n" "$h"
          done

    subheader "GitHub / GitLab entries"
    grep -iE "github|gitlab" "$known_hosts_file" 2>/dev/null \
        | awk '{print $1}' | sort -u \
        | while IFS= read -r h; do printf "  * %s\n" "$h"; done \
        || echo "  None found."
fi

# =================================================================
# 6. AUTHORIZED KEYS
# =================================================================
header "6. AUTHORIZED KEYS (~/.ssh/authorized_keys)"

auth_file="$SSH_DIR/authorized_keys"

if [[ ! -f "$auth_file" ]]; then
    echo "No authorized_keys file found."
else
    auth_perms=$(stat -c "%a" "$auth_file" 2>/dev/null \
                 || stat -f "%OLp" "$auth_file" 2>/dev/null \
                 || echo "unknown")
    printf "Permissions : %s" "$auth_perms"
    if [[ "$auth_perms" != "600" && "$auth_perms" != "644" && "$auth_perms" != "unknown" ]]; then
        printf "  ${RED}(should be 600 or 644)${NC}\n"
    else
        printf "  ${GREEN}(OK)${NC}\n"
    fi

    authorized_key_count=$(grep -vc '^[[:space:]]*#\|^[[:space:]]*$' "$auth_file" 2>/dev/null || echo "0")
    printf "Total keys  : %s\n" "$authorized_key_count"

    echo ""
    echo "Keys (type + comment):"
    grep -v '^[[:space:]]*#\|^[[:space:]]*$' "$auth_file" 2>/dev/null \
        | awk '{type=$1; comment=$NF; if (NF>=3) print "  * " type "  " comment; else print "  * " type}' \
        || true
fi

# =================================================================
# 7. PLATFORM-SPECIFIC CHECKS
# =================================================================
header "7. PLATFORM-SPECIFIC CHECKS"

case "$PLATFORM" in
    # ---- macOS: Keychain-stored passphrases ----
    macos)
        subheader "macOS Keychain (SSH passphrases)"
        if cmd_exists security; then
            kc_out=$(security find-generic-password -s "SSH" 2>/dev/null || true)
            if [[ -n "$kc_out" ]]; then
                echo "SSH passphrase(s) found in Keychain:"
                printf '%s\n' "$kc_out" | grep '"acct"\|"svce"' | while IFS= read -r l; do
                    printf "  %s\n" "$l"
                done
            else
                echo "No SSH passphrases stored in Keychain."
            fi
        else
            warn "security command not found."
        fi
        ;;

    # ---- Windows / WSL: OpenSSH service + Pageant ----
    windows|wsl)
        subheader "Windows OpenSSH Service"
        sc_bin="sc"
        [[ "$PLATFORM" == "wsl" ]] && sc_bin="sc.exe"
        if cmd_exists "$sc_bin"; then
            svc_out=$("$sc_bin" query ssh-agent 2>/dev/null || true)
            if echo "$svc_out" | grep -q "RUNNING"; then
                printf "${GREEN}[OK]${NC} Windows OpenSSH Agent service is RUNNING\n"
            elif echo "$svc_out" | grep -q "STOPPED"; then
                printf "${RED}[!]${NC} Windows OpenSSH Agent service is STOPPED\n"
                printf "    To enable: Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent\n"
            else
                echo "OpenSSH Agent service status unknown or not installed."
            fi
        fi

        subheader "Windows OpenSSH Key Store"
        # Keys registered with Windows ssh-agent (separate from OPENSSH_AUTH_SOCK)
        reg_bin="reg"
        [[ "$PLATFORM" == "wsl" ]] && reg_bin="reg.exe"
        if cmd_exists "$reg_bin"; then
            reg_out=$("$reg_bin" query "HKCU\Software\OpenSSH\Agent\Keys" /s 2>/dev/null || true)
            if [[ -n "$reg_out" ]]; then
                key_names=$(echo "$reg_out" | grep -v "^HKEY\|^$" | awk '{print $1}' | grep -v "^$" | sort -u)
                if [[ -n "$key_names" ]]; then
                    echo "Keys in Windows OpenSSH Agent registry:"
                    echo "$key_names" | while IFS= read -r k; do printf "  * %s\n" "$k"; done
                fi
            else
                echo "No keys found in Windows OpenSSH Agent registry."
            fi
        fi
        ;;

    linux)
        subheader "Linux SSH Agent Socket"
        if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
            printf "${GREEN}[OK]${NC} SSH_AUTH_SOCK = %s\n" "$SSH_AUTH_SOCK"
        else
            printf "${RED}[!]${NC} SSH_AUTH_SOCK not set — SSH agent may not be running.\n"
            printf "    To start: eval \"\$(ssh-agent -s)\"\n"
        fi
        ;;
esac

# =================================================================
# 8. SSH CONNECTIVITY TESTS
# =================================================================
header "8. CONNECTIVITY TESTS (GitHub / GitLab)"

if cmd_exists ssh; then
    for target in "git@github.com" "git@gitlab.com"; do
        host=$(echo "$target" | cut -d'@' -f2)
        printf "\nTesting: %s\n" "$target"
        result=$(ssh -T -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
                 "$target" 2>&1 || true)
        if echo "$result" | grep -qiE "successfully authenticated|welcome to gitlab"; then
            printf "  ${GREEN}[OK]${NC} Authenticated: %s\n" "$result"
        elif echo "$result" | grep -qiE "permission denied|publickey"; then
            printf "  ${RED}[!]${NC} Authentication failed (no matching key loaded or accepted)\n"
            printf "       %s\n" "$result"
        elif echo "$result" | grep -qiE "connection timed out|network"; then
            printf "  ${YELLOW}[?]${NC} Connection timed out — check network.\n"
        else
            printf "  ${GRAY}[?]${NC} %s\n" "$result"
        fi
    done
else
    echo "ssh not found — skipping connectivity tests."
fi

# =================================================================
# 9. SUMMARY
# =================================================================
header "9. SUMMARY OF FINDINGS"
echo "--------------------------------------------------------"
printf "%-42s %s\n" "Key pairs found (~/.ssh/id_*):"    "$key_count"
printf "%-42s %s\n" "  with passphrase:"                "$key_with_passphrase"
printf "%-42s %s\n" "  without passphrase:"             "$key_without_passphrase"
printf "%-42s %s\n" "  passphrase unknown:"             "$key_unknown_passphrase"
printf "%-42s %s\n" "SSH config Host entries:"          "$host_entry_count"
printf "%-42s %s\n" "Keys loaded in SSH agent:"         "$agent_key_count"
printf "%-42s %s\n" "Known hosts entries:"              "$known_host_count"
printf "%-42s %s\n" "Authorized keys:"                  "$authorized_key_count"

if [[ $key_without_passphrase -gt 0 ]]; then
    echo ""
    warn "$key_without_passphrase private key(s) have NO passphrase — consider adding one with:"
    echo "  ssh-keygen -p -f ~/.ssh/<keyfile>"
fi

if [[ $key_count -gt 0 && $host_entry_count -eq 0 ]]; then
    echo ""
    warn "Keys found but no ~/.ssh/config — hosts must be specified manually on every connection."
fi

echo ""
echo "--- Key fingerprints ---"
if [[ -n "$key_types" ]]; then
    printf '%s' "$key_types" | sort -u | grep -v '^$' | while IFS= read -r fp; do
        printf "  %s\n" "$fp"
    done
else
    echo "  (None)"
fi

echo ""
echo "--- SSH config hosts ---"
if [[ -n "$host_entries" ]]; then
    printf '%s' "$host_entries" | sort -u | grep -v '^$' | while IFS= read -r h; do
        printf "  * %s\n" "$h"
    done
else
    echo "  (None)"
fi

echo "--------------------------------------------------------"
printf "\n"
ok "Scan complete. Review results above."
