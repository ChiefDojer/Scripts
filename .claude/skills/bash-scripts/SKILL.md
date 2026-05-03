# Skill: Write Bash Scripts for This Project

When the user asks to create a new Bash script, produce **three files** inside a new folder:

```
<ScriptName>/
  <ScriptName>.sh       — the Bash script
  <ScriptName>.bat      — Windows launcher (finds Git Bash via registry)
  ScriptDefinition.md   — design notes and section reference
```

Use `<ScriptName>` in PascalCase matching the folder name (e.g. `FindGitAccounts`).

---

## 1. Bash Script Template

```bash
#!/usr/bin/env bash
# =================================================================
# <ScriptName>.sh
# Purpose: <one-line description>
# Platforms: Linux, macOS, Windows (Git Bash / WSL)
# Requires:  bash 3.2+, <core deps>. Optional: <optional deps>
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
```

### Key rules

- Use `set -uo pipefail`, **not** `-e`. Many optional checks return non-zero; handle with `|| true`.
- Increment counters as `count=$((count + 1))` — never `(( count++ ))` (fails with `-e` and bash 3).
- Avoid `declare -A` (associative arrays require bash 4). Use parallel indexed arrays or string accumulators.
- Accumulate multi-value lists as newline-separated strings; deduplicate with `sort -u | grep -v '^$'` at summary time.
- Always disable colors when stdout is not a TTY (`[[ -t 1 ]]` guard).
- For Windows-only checks use `reg` (Git Bash) / `reg.exe` (WSL) and `cmdkey` / `cmdkey.exe`.
- For macOS keychain checks use `security find-internet-password` / `find-generic-password`.
- For Linux secret store checks use `secret-tool search`.
- Redact secrets in output: `sed -E 's/:[^@:]+@/:***@/'` for URLs, replace password values with `***`.

### Structure

Number sections sequentially. Always end with a SUMMARY section that:
- prints counters with `printf "%-42s %s\n"` for alignment
- prints deduplicated lists for each accumulator

---

## 2. Windows .bat Launcher Template

```bat
@echo off
setlocal

:: ----------------------------------------------------------------
:: <ScriptName>.bat — Windows launcher (cmd / PowerShell)
:: Finds Git Bash via registry and runs <ScriptName>.sh with it.
:: ----------------------------------------------------------------

set "BASH_EXE="

:: 1. Check registry (works for any install location)
for /f "tokens=2*" %%A in (
    'reg query "HKLM\SOFTWARE\GitForWindows" /v "InstallPath" 2^>nul'
) do set "BASH_EXE=%%B\bin\bash.exe"

:: 2. Fall back to common default paths
if not exist "%BASH_EXE%" set "BASH_EXE=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=C:\Program Files (x86)\Git\bin\bash.exe"

if not exist "%BASH_EXE%" (
    echo.
    echo [ERROR] Git Bash not found.
    echo         Install Git for Windows and re-run this script.
    echo         https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)

"%BASH_EXE%" "%~dp0<ScriptName>.sh"
```

`%~dp0` ensures the script is always found relative to the `.bat` file regardless of the working directory.

---

## 3. ScriptDefinition.md Template

````markdown
# <ScriptName>.sh — <Short Title>

<One paragraph: what the script does, why it exists, who should run it.>

Works on **Linux**, **macOS**, and **Windows** (Git Bash / WSL).
Requires Bash 3.2+ and `<core dep>`. Optional: `<tool1>`, `<tool2>`.

## Execution

```bash
# Linux / macOS
chmod +x <ScriptName>/<ScriptName>.sh
./<ScriptName>/<ScriptName>.sh

# Windows — Git Bash
bash <ScriptName>/<ScriptName>.sh

# Windows — .bat launcher (PowerShell / cmd / Explorer double-click)
.\<ScriptName>\<ScriptName>.bat

# Windows — PowerShell with explicit path
& "C:\Program Files\Git\bin\bash.exe" <ScriptName>\<ScriptName>.sh

# Save output
./<ScriptName>/<ScriptName>.sh | tee report.txt
```

## Audit Sections (<N> Checks)

### 1. <Section Name>

<What is checked, where data comes from, any caveats.>

### 2. <Section Name>

...

## Summary

Prints counters for all checks and deduplicated lists of detected values.
````

---

## 4. README.md Entry

After creating the three files, add an entry to the root `README.md`:

- Under **Included Scripts**: one paragraph with the script name, platform badge, file path, and a short description. Link to `ScriptDefinition.md`.
- Under **Quickstart**: code blocks for Linux/macOS, Windows Git Bash, and the `.bat` launcher.
- Under **Files**: add the folder and its three files to the file tree.

---

## 5. Platform-specific snippets

### Windows registry query (Git Bash / WSL)

```bash
reg_bin="reg"
[[ "$PLATFORM" == "wsl" ]] && reg_bin="reg.exe"
out=$("$reg_bin" query "HKCU\Some\Key" /s 2>/dev/null || true)
```

### macOS Keychain

```bash
out=$(security find-internet-password -s "example.com" 2>/dev/null || true)
acct=$(printf '%s\n' "$out" | grep '"acct"' | sed -E 's/.*"acct"<blob>="(.+)"/\1/')
```

### Windows Credential Manager

```bash
cmdkey_bin="cmdkey"
[[ "$PLATFORM" == "wsl" ]] && cmdkey_bin="cmdkey.exe"
"$cmdkey_bin" /list 2>/dev/null | grep -iE "github|gitlab" || true
```

### VS Code session DB path (platform-adaptive)

```bash
case "$PLATFORM" in
    windows) db="${APPDATA:-$HOME/AppData/Roaming}/Code/User/globalStorage/state.vscdb" ;;
    wsl)
        win=$(cmd.exe /c "echo %APPDATA%" 2>/dev/null | tr -d '\r' || true)
        db="$(wslpath "$win" 2>/dev/null)/Code/User/globalStorage/state.vscdb"
        ;;
    macos)  db="$HOME/Library/Application Support/Code/User/globalStorage/state.vscdb" ;;
    *)      db="$HOME/.config/Code/User/globalStorage/state.vscdb" ;;
esac
```

### SSH key enumeration

```bash
while IFS= read -r key; do
    [[ -f "${key}.pub" ]] || continue
    printf "Key: %s\nPub: %s\n" "$key" "$(cat "${key}.pub")"
done < <(find "$HOME/.ssh" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" 2>/dev/null)
```

### Recursive .git directory scan (max depth 6)

```bash
while IFS= read -r dot_git; do
    repo=$(dirname "$dot_git")
    [[ -f "$dot_git/config" ]] || continue
    # ... per-repo work ...
done < <(find "$HOME" -maxdepth 6 -type d -name ".git" 2>/dev/null)
```
