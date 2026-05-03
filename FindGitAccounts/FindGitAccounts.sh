#!/usr/bin/env bash
# =================================================================
# FindGitAccounts.sh
# Purpose: Detect all Git, GitHub, and GitLab accounts configured
#          or cached on this machine.
# Platforms: Linux, macOS, Windows (Git Bash / WSL)
# Requires:  bash 3.2+, git. Optional: gh, glab, sqlite3,
#            security (macOS), secret-tool (Linux), cmdkey/reg (Win)
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

# ----------------------------------------------------------- counters/state ---
system_git_count=0
global_git_count=0
local_identity_count=0
cred_entry_count=0
vscode_session_count=0
vs_account_count=0
gh_cli_count=0
glab_cli_count=0
github_remote_count=0
gitlab_remote_count=0

# Newline-separated accumulators (deduplicated at summary time; bash 3 safe)
git_identities=""
cred_names=""
gh_accounts=""
glab_accounts=""

add_identity() {
    local val="${1:-}"
    [[ -z "$val" ]] && return
    git_identities="${git_identities}${val}"$'\n'
}

printf "\n"
info "Scanning for Git / GitHub / GitLab accounts...  (platform: $PLATFORM)"

# =================================================================
# 1. GIT CONFIGURATION  (System → Global → Local)
# =================================================================
header "1. GIT CONFIGURATION (System / Global / Local)"

if ! cmd_exists git; then
    warn "git not found in PATH — skipping git config checks."
else
    # ---- 1a. System -------------------------------------------------
    subheader "System configuration"
    system_name=$(git config --system user.name  2>/dev/null || true)
    system_email=$(git config --system user.email 2>/dev/null || true)
    sys_path=$(git config --system --show-origin --list 2>/dev/null \
               | head -1 | cut -f1 | sed 's/^file://' || true)

    printf "Config path : %s\n" "${sys_path:-/etc/gitconfig (default)}"
    if [[ -n "$system_name" || -n "$system_email" ]]; then
        printf "user.name   : %s\n" "$system_name"
        printf "user.email  : %s\n" "$system_email"
        system_git_count=1
        add_identity "$system_name"
        add_identity "$system_email"
    else
        echo "No system Git identity configured."
    fi

    # ---- 1b. Global -------------------------------------------------
    subheader "Global configuration (~/.gitconfig)"
    global_name=$(git config --global user.name  2>/dev/null || true)
    global_email=$(git config --global user.email 2>/dev/null || true)
    global_path=$(git config --global --show-origin --list 2>/dev/null \
                  | head -1 | cut -f1 | sed 's/^file://' || true)

    printf "Config path : %s\n" "${global_path:-~/.gitconfig (default)}"
    if [[ -n "$global_name" || -n "$global_email" ]]; then
        printf "user.name   : %s\n" "$global_name"
        printf "user.email  : %s\n" "$global_email"
        global_git_count=1
        add_identity "$global_name"
        add_identity "$global_email"
    else
        echo "No global Git identity configured."
    fi

    # ---- 1c. Local repository overrides ----------------------------
    subheader "Local repository identity overrides"
    echo "Scanning: $HOME  (may take a moment)..."

    while IFS= read -r dot_git; do
        repo_root=$(dirname "$dot_git")
        [[ -f "$dot_git/config" ]] || continue
        local_name=$(git  -C "$repo_root" config user.name  2>/dev/null || true)
        local_email=$(git -C "$repo_root" config user.email 2>/dev/null || true)
        [[ -z "$local_name" && -z "$local_email" ]] && continue
        printf "\nRepo       : %s\n"   "$repo_root"
        printf "  user.name  : %s\n"  "$local_name"
        printf "  user.email : %s\n"  "$local_email"
        local_identity_count=$((local_identity_count + 1))
        add_identity "$local_name"
        add_identity "$local_email"
    done < <(find "$HOME" -maxdepth 6 -type d -name ".git" 2>/dev/null)

    [[ $local_identity_count -eq 0 ]] && echo "No local repo identity overrides found."
fi

# =================================================================
# 2. CREDENTIAL STORES
# =================================================================
header "2. CREDENTIAL STORES"

# ---- 2a. Windows Credential Manager (Windows / WSL) ---------------
if [[ "$PLATFORM" == "windows" || "$PLATFORM" == "wsl" ]]; then
    subheader "Windows Credential Manager"
    cmdkey_bin="cmdkey"
    [[ "$PLATFORM" == "wsl" ]] && cmdkey_bin="cmdkey.exe"

    if cmd_exists "$cmdkey_bin"; then
        found_win=0
        while IFS= read -r line; do
            echo "$line" | grep -qiE "github|gitlab|git:https?://" || continue
            echo "* $line"
            cred_entry_count=$((cred_entry_count + 1))
            found_win=$((found_win + 1))
            if echo "$line" | grep -qiE "Target:"; then
                target=$(echo "$line" | sed -E 's/.*Target:\s*//')
                cred_names="${cred_names}${target}"$'\n'
            fi
        done < <("$cmdkey_bin" /list 2>/dev/null || true)
        [[ $found_win -eq 0 ]] && echo "No GitHub/GitLab entries in Windows Credential Manager."
    else
        warn "$cmdkey_bin not available."
    fi
fi

# ---- 2b. macOS Keychain --------------------------------------------
if [[ "$PLATFORM" == "macos" ]] && cmd_exists security; then
    subheader "macOS Keychain"
    for svc in "github.com" "gitlab.com"; do
        inet=$(security find-internet-password -s "$svc" 2>/dev/null || true)
        gen=$(security find-generic-password  -s "$svc" 2>/dev/null || true)
        if [[ -n "$inet" ]]; then
            printf "Internet-password entry for %s\n" "$svc"
            acct=$(printf '%s\n' "$inet" | grep '"acct"' | sed -E 's/.*"acct"<blob>="(.+)"/\1/')
            [[ -n "$acct" ]] && printf "  Account: %s\n" "$acct" && add_identity "$acct"
            cred_entry_count=$((cred_entry_count + 1))
        fi
        if [[ -n "$gen" ]]; then
            printf "Generic-password entry for %s\n" "$svc"
            acct=$(printf '%s\n' "$gen" | grep '"acct"' | sed -E 's/.*"acct"<blob>="(.+)"/\1/')
            [[ -n "$acct" ]] && printf "  Account: %s\n" "$acct" && add_identity "$acct"
            cred_entry_count=$((cred_entry_count + 1))
        fi
        [[ -z "$inet" && -z "$gen" ]] && printf "No keychain entry for %s.\n" "$svc"
    done
fi

# ---- 2c. Linux GNOME Keyring (secret-tool) -------------------------
if [[ "$PLATFORM" == "linux" ]] && cmd_exists secret-tool; then
    subheader "GNOME Keyring (secret-tool)"
    for svc in "github.com" "gitlab.com"; do
        out=$(secret-tool search server "$svc" 2>/dev/null || true)
        if [[ -n "$out" ]]; then
            printf "Entry found for %s:\n" "$svc"
            printf '%s\n' "$out" | grep -i account || true
            cred_entry_count=$((cred_entry_count + 1))
        else
            printf "No secret-tool entry for %s.\n" "$svc"
        fi
    done
fi

# ---- 2d. ~/.git-credentials (all platforms) ------------------------
subheader "Git credentials file (~/.git-credentials)"
cred_file="$HOME/.git-credentials"
if [[ -f "$cred_file" ]]; then
    echo "Found: $cred_file"
    while IFS= read -r line; do
        echo "$line" | grep -qiE "github|gitlab" || continue
        redacted=$(echo "$line" | sed -E 's/:[^@:]+@/:***@/')
        echo "* $redacted"
        cred_entry_count=$((cred_entry_count + 1))
    done < "$cred_file"
else
    echo "Not found."
fi

# ---- 2e. ~/.netrc (all platforms) ----------------------------------
netrc="$HOME/.netrc"
if [[ -f "$netrc" ]]; then
    subheader ".netrc file"
    echo "Found: $netrc"
    grep -iE "github|gitlab" "$netrc" \
        | sed -E 's/password[[:space:]]+[^[:space:]]*/password ***/gi' \
        || echo "No GitHub/GitLab entries."
fi

# =================================================================
# 3. SSH KEYS
# =================================================================
header "3. SSH KEYS"

ssh_dir="$HOME/.ssh"
if [[ -d "$ssh_dir" ]]; then
    echo "SSH directory: $ssh_dir"
    key_count=0

    while IFS= read -r key_file; do
        pub_file="${key_file}.pub"
        [[ -f "$pub_file" ]] || continue
        key_count=$((key_count + 1))
        printf "\nPrivate key : %s\n" "$key_file"
        printf "Public key  : %s\n"  "$(cat "$pub_file")"
    done < <(find "$ssh_dir" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" 2>/dev/null)

    [[ $key_count -eq 0 ]] && echo "No SSH private keys found in ~/.ssh/"

    if [[ -f "$ssh_dir/config" ]]; then
        echo ""
        echo "SSH config entries for GitHub / GitLab:"
        grep -A 6 -iE "^Host[[:space:]].*(github|gitlab)" "$ssh_dir/config" 2>/dev/null \
            || echo "  None found."
    fi

    if [[ -f "$ssh_dir/known_hosts" ]]; then
        echo ""
        echo "Known GitHub/GitLab hosts:"
        grep -iE "github|gitlab" "$ssh_dir/known_hosts" \
            | cut -d' ' -f1 | sort -u \
            || echo "  None found."
    fi
else
    echo "No ~/.ssh directory found."
fi

# =================================================================
# 4. VS CODE AUTHENTICATION SESSIONS
# =================================================================
header "4. VS CODE AUTHENTICATION SESSIONS"

# Build platform-specific DB path lists (bash 3 safe: parallel arrays)
declare -a vscode_labels=()
declare -a vscode_db_paths=()

case "$PLATFORM" in
    windows)
        appdata="${APPDATA:-$HOME/AppData/Roaming}"
        vscode_labels=("VS Code" "VS Code Insider")
        vscode_db_paths=(
            "$appdata/Code/User/globalStorage/state.vscdb"
            "$appdata/Code - Insiders/User/globalStorage/state.vscdb"
        )
        ;;
    wsl)
        win_appdata=$(cmd.exe /c "echo %APPDATA%" 2>/dev/null | tr -d '\r' || true)
        appdata_unix=""
        [[ -n "$win_appdata" ]] && appdata_unix=$(wslpath "$win_appdata" 2>/dev/null || true)
        vscode_labels=("VS Code" "VS Code Insider")
        vscode_db_paths=(
            "${appdata_unix}/Code/User/globalStorage/state.vscdb"
            "${appdata_unix}/Code - Insiders/User/globalStorage/state.vscdb"
        )
        ;;
    macos)
        vscode_labels=("VS Code" "VS Code Insider")
        vscode_db_paths=(
            "$HOME/Library/Application Support/Code/User/globalStorage/state.vscdb"
            "$HOME/Library/Application Support/Code - Insiders/User/globalStorage/state.vscdb"
        )
        ;;
    *)  # linux / unknown
        vscode_labels=("VS Code" "VS Code Insider")
        vscode_db_paths=(
            "$HOME/.config/Code/User/globalStorage/state.vscdb"
            "$HOME/.config/Code - Insiders/User/globalStorage/state.vscdb"
        )
        ;;
esac

for i in "${!vscode_labels[@]}"; do
    label="${vscode_labels[$i]}"
    db="${vscode_db_paths[$i]}"
    [[ -f "$db" ]] || continue
    printf "%s session DB : %s\n" "$label" "$db"
    # Optional: extract session info via SQLite if available
    if cmd_exists sqlite3; then
        sessions=$(sqlite3 "$db" \
            "SELECT value FROM ItemTable WHERE key LIKE '%github%' OR key LIKE '%gitlab%';" \
            2>/dev/null | head -3 || true)
        [[ -n "$sessions" ]] && printf "  Raw session excerpt: %.200s\n" "$sessions"
    fi
    printf "  [>] Manual: in VS Code run 'Developer: Show Authentication Sessions'\n"
    vscode_session_count=$((vscode_session_count + 1))
done

[[ $vscode_session_count -eq 0 ]] && echo "No VS Code session databases found."

# =================================================================
# 5. VISUAL STUDIO CONNECTED ACCOUNTS  (Windows / WSL only)
# =================================================================
header "5. VISUAL STUDIO CONNECTED ACCOUNTS"

if [[ "$PLATFORM" == "windows" || "$PLATFORM" == "wsl" ]]; then
    reg_bin="reg"
    [[ "$PLATFORM" == "wsl" ]] && reg_bin="reg.exe"
    reg_key='HKCU\Software\Microsoft\VSCommon\ConnectedUser'

    if cmd_exists "$reg_bin"; then
        reg_out=$("$reg_bin" query "$reg_key" /s 2>/dev/null || true)
        if [[ -n "$reg_out" ]]; then
            echo "Visual Studio ConnectedUser registry entries:"
            found_vs=0
            while IFS= read -r line; do
                # Look for string values that look like email addresses
                if echo "$line" | grep -qiE "REG_SZ|REG_EXPAND_SZ"; then
                    value=$(echo "$line" | awk '{print $NF}')
                    # Skip empty, numeric-only, or non-email-like values
                    if echo "$value" | grep -qE '^[^@]+@[^@]+\.[^@]+$'; then
                        if echo "$value" | grep -qiE "@github\.com|noreply\.github\.com"; then
                            printf "* GitHub account  : %s\n" "$value"
                        elif echo "$value" | grep -qiE "@live\.com|@outlook\.com|@microsoft\.com|@hotmail\.com"; then
                            printf "* Microsoft account (possible GitHub link): %s\n" "$value"
                        else
                            printf "* Account         : %s\n" "$value"
                        fi
                        add_identity "$value"
                        vs_account_count=$((vs_account_count + 1))
                    fi
                fi
            done <<< "$reg_out"
            [[ $vs_account_count -eq 0 ]] && echo "No account emails found in registry."
        else
            echo "Registry key not found — Visual Studio may not be installed."
        fi
    else
        warn "$reg_bin not available."
    fi
else
    echo "Skipped — Windows/WSL only."
fi

# =================================================================
# 6. GITHUB CLI  (gh)
# =================================================================
header "6. GITHUB CLI ACCOUNTS (gh)"

if cmd_exists gh; then
    gh_status=$(gh auth status 2>&1 || true)
    if echo "$gh_status" | grep -q "Logged in to"; then
        echo "Active sessions:"
        while IFS= read -r line; do
            echo "$line" | grep -q "Logged in to" || continue
            echo "* $line"
            gh_cli_count=$((gh_cli_count + 1))
            username=$(echo "$line" | grep -oE "as [^ ]+" | awk '{print $2}' | tr -d '()')
            [[ -n "$username" ]] && gh_accounts="${gh_accounts}${username}"$'\n'
        done <<< "$gh_status"
    else
        echo "No active GitHub CLI sessions."
        [[ -n "$gh_status" ]] && printf "  Details: %s\n" "$gh_status"
    fi

    gh_hosts="${GH_CONFIG_DIR:-$HOME/.config/gh}/hosts.yml"
    if [[ -f "$gh_hosts" ]]; then
        echo ""
        printf "gh hosts config: %s\n" "$gh_hosts"
        grep -v "oauth_token\|token:" "$gh_hosts" 2>/dev/null || true
    fi
else
    echo "GitHub CLI (gh) not installed or not in PATH."
fi

# =================================================================
# 7. GITLAB CLI  (glab)
# =================================================================
header "7. GITLAB CLI ACCOUNTS (glab)"

if cmd_exists glab; then
    glab_status=$(glab auth status 2>&1 || true)
    if echo "$glab_status" | grep -qiE "Logged in|Token:"; then
        echo "Active sessions:"
        echo "$glab_status"
        glab_cli_count=$((glab_cli_count + 1))
        username=$(echo "$glab_status" | grep -oiE "as [^ ]+" | awk '{print $2}' | head -1)
        [[ -n "$username" ]] && glab_accounts="${glab_accounts}${username}"$'\n'
    else
        echo "No active GitLab CLI sessions."
        [[ -n "$glab_status" ]] && printf "  Details: %s\n" "$glab_status"
    fi

    glab_cfg="${GLAB_CONFIG_DIR:-$HOME/.config/glab-cli}/config.yml"
    if [[ -f "$glab_cfg" ]]; then
        echo ""
        printf "glab config: %s\n" "$glab_cfg"
        grep -v "token:" "$glab_cfg" 2>/dev/null || true
    fi
else
    echo "GitLab CLI (glab) not installed or not in PATH."
fi

# =================================================================
# 8. LOCAL REPOSITORY REMOTES
# =================================================================
header "8. LOCAL REPOSITORY REMOTES"

echo "Scanning: $HOME  (github.com / gitlab.com remotes)..."

while IFS= read -r dot_git; do
    repo_root=$(dirname "$dot_git")
    [[ -f "$dot_git/config" ]] || continue

    while IFS= read -r remote; do
        url=$(git -C "$repo_root" remote get-url "$remote" 2>/dev/null || true)
        [[ -z "$url" ]] && continue

        if echo "$url" | grep -q "github.com"; then
            printf "\nRepo: %s\n  Remote (%s): %s  [GitHub]\n" "$repo_root" "$remote" "$url"
            github_remote_count=$((github_remote_count + 1))
        elif echo "$url" | grep -qiE "gitlab\.com|/gitlab"; then
            printf "\nRepo: %s\n  Remote (%s): %s  [GitLab]\n" "$repo_root" "$remote" "$url"
            gitlab_remote_count=$((gitlab_remote_count + 1))
        fi
    done < <(git -C "$repo_root" remote 2>/dev/null || true)
done < <(find "$HOME" -maxdepth 6 -type d -name ".git" 2>/dev/null)

[[ $github_remote_count -eq 0 ]] && echo "No GitHub remotes found."
[[ $gitlab_remote_count -eq 0 ]] && echo "No GitLab remotes found."

# =================================================================
# 9. SUMMARY
# =================================================================
header "9. SUMMARY OF FINDINGS"
echo "--------------------------------------------------------"
printf "%-42s %s\n" "Git system identity:"           "$system_git_count"
printf "%-42s %s\n" "Git global identity:"           "$global_git_count"
printf "%-42s %s\n" "Local repo identity overrides:" "$local_identity_count"
printf "%-42s %s\n" "Credential store entries:"      "$cred_entry_count"
printf "%-42s %s\n" "VS Code session databases:"     "$vscode_session_count"
printf "%-42s %s\n" "Visual Studio accounts:"        "$vs_account_count"
printf "%-42s %s\n" "GitHub CLI sessions:"           "$gh_cli_count"
printf "%-42s %s\n" "GitLab CLI sessions:"           "$glab_cli_count"
printf "%-42s %s\n" "Repos with GitHub remote:"      "$github_remote_count"
printf "%-42s %s\n" "Repos with GitLab remote:"      "$gitlab_remote_count"

echo ""
echo "--- Unique Git identities (names / emails) ---"
if [[ -n "$git_identities" ]]; then
    printf '%s' "$git_identities" | sort -u | grep -v '^$' | while IFS= read -r id; do
        printf "* %s\n" "$id"
    done
else
    echo " (None detected)"
fi

echo ""
echo "--- GitHub CLI usernames ---"
if [[ -n "$gh_accounts" ]]; then
    printf '%s' "$gh_accounts" | sort -u | grep -v '^$' | while IFS= read -r a; do
        printf "* %s\n" "$a"
    done
else
    echo " (None detected)"
fi

echo ""
echo "--- GitLab CLI usernames ---"
if [[ -n "$glab_accounts" ]]; then
    printf '%s' "$glab_accounts" | sort -u | grep -v '^$' | while IFS= read -r a; do
        printf "* %s\n" "$a"
    done
else
    echo " (None detected)"
fi

echo "--------------------------------------------------------"
printf "\n"
ok "Scan complete. Review results above."
