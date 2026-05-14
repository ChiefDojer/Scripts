# Scripts

Collection of developer utility scripts for auditing and inspecting development environments. Scripts target **Windows**, **Linux**, and **macOS** unless noted otherwise.

---

## Included Scripts

### EnvironmentCheck *(cross-platform)*

`EnvironmentCheck/EnvironmentCheck.sh`

Universal developer environment auditor written in Bash. Detects the OS on first run and executes common checks plus platform-specific checks automatically. Covers 13 categories: platform features, core tools, Python ecosystem, runtimes, AI/data tools, web servers, frontend, DevOps/cloud, Microsoft stack, databases, version control, build tools, and utilities.

See full details in [EnvironmentCheck/ScriptDefinition.md](EnvironmentCheck/ScriptDefinition.md).

---

### FindGitAccounts *(cross-platform)*

`FindGitAccounts/FindGitAccounts.sh`

Cross-platform Git account auditor written in Bash. Detects Git, GitHub, and GitLab identities across 8 check categories: git config (system/global/local), credential stores (Credential Manager / Keychain / secret-tool / `.git-credentials` / `.netrc`), SSH keys, VS Code sessions, GitHub CLI, GitLab CLI, and local repo remotes. Works on Linux, macOS, and Windows (Git Bash / WSL). Requires Bash 3.2+ and `git`; all other tools are optional.

See [FindGitAccounts/ScriptDefinition.md](FindGitAccounts/ScriptDefinition.md).

---

### SSHKeysCheck *(cross-platform)*

`SSHKeysCheck/SSHKeysCheck.sh`

SSH key auditor written in Bash. Inspects key pairs, fingerprints, passphrase protection, file permissions, SSH config host entries, SSH agent state, known hosts, authorized keys, platform-specific stores (macOS Keychain, Windows OpenSSH service), and tests live authentication against GitHub and GitLab.

See [SSHKeysCheck/ScriptDefinition.md](SSHKeysCheck/ScriptDefinition.md).

---

### FindGitHubAccounts *(Windows only)*

`FindGitHubAccounts/FindGitHubAccounts.ps1`

GitHub account auditor that inspects Git configs, Windows Credential Manager, VS Code sessions, Visual Studio registry, GitHub CLI state, and local repo remotes.

See [FindGitHubAccounts/ScriptDefinition.md](FindGitHubAccounts/ScriptDefinition.md).

---

### PortScan *(cross-platform)*

`PortScan/PortScan.sh`

TCP port scanner written in Bash. Scans open ports on localhost then auto-detects the local /24 subnet and scans all live hosts. Uses **nmap** when available for speed; falls back to pure Bash `/dev/tcp` with batched parallel probes when nmap is absent. Supports ~140 curated common ports (default), full range 1–65535, or a custom comma-separated list via `--ports`. Includes a service-name map for ~90 well-known ports.

See [PortScan/ScriptDefinition.md](PortScan/ScriptDefinition.md).

---

## Quickstart

### EnvironmentCheck — cross-platform

**Prerequisites:** Bash 4.0+. On macOS the system Bash is 3.x — install a newer version first:
```bash
brew install bash
```

**Windows — из PowerShell или cmd (проще всего):**
```powershell
.\EnvironmentCheck\EnvironmentCheck.bat
```
Лаунчер сам найдёт Git Bash через реестр и запустит скрипт. Работает из PowerShell, cmd и по двойному клику в проводнике.

**Windows — из терминала Git Bash:**
```bash
bash EnvironmentCheck/EnvironmentCheck.sh
```

**Windows — из PowerShell напрямую (без .bat):**

`bash` в PowerShell указывает на WSL, а не на Git Bash:
```powershell
& "C:\Program Files\Git\bin\bash.exe" EnvironmentCheck\EnvironmentCheck.sh
```

**Linux / macOS:**
```bash
chmod +x EnvironmentCheck/EnvironmentCheck.sh
./EnvironmentCheck/EnvironmentCheck.sh
```

**Save output to a file:**
```bash
./EnvironmentCheck/EnvironmentCheck.sh | tee env-report.txt
```

---

### FindGitAccounts — cross-platform Bash

```bash
# Linux / macOS
chmod +x FindGitAccounts/FindGitAccounts.sh
./FindGitAccounts/FindGitAccounts.sh

# Windows — Git Bash
bash FindGitAccounts/FindGitAccounts.sh

# Windows — PowerShell (via Git Bash)
& "C:\Program Files\Git\bin\bash.exe" FindGitAccounts\FindGitAccounts.sh
```

---

### SSHKeysCheck — cross-platform Bash

```bash
# Linux / macOS
chmod +x SSHKeysCheck/SSHKeysCheck.sh
./SSHKeysCheck/SSHKeysCheck.sh

# Windows — .bat launcher
.\SSHKeysCheck\SSHKeysCheck.bat

# Windows — Git Bash
bash SSHKeysCheck/SSHKeysCheck.sh
```

---

### FindGitHubAccounts — Windows PowerShell

```powershell
cd FindGitHubAccounts
powershell -ExecutionPolicy Bypass -File .\FindGitHubAccounts.ps1
```

---

### PortScan — cross-platform Bash

```bash
# Linux / macOS
chmod +x PortScan/PortScan.sh
./PortScan/PortScan.sh

# Windows — .bat launcher
.\PortScan\PortScan.bat

# Windows — Git Bash
bash PortScan/PortScan.sh

# Scan all ports on localhost only
./PortScan/PortScan.sh --ports all --no-subnet

# Scan a specific host with a custom port list
./PortScan/PortScan.sh --host 192.168.1.50 --ports 22,80,443,3306
```

---

## Notes

- Some checks (Hyper-V, IIS, Windows Optional Features) require an elevated PowerShell or admin shell for full results; the scripts degrade gracefully when permissions are missing.
- All operations are read-only — no installations or modifications are performed.
- Output is color-coded; a summary table is printed at the end of each run.

---

## Contribution & Extensibility

- To add a tool check to `EnvironmentCheck.sh`, call `check_command "cmd" "Display Name" "--version"` in the appropriate section.
- For tools with non-standard version output, pass an optional Bash regex as the fourth argument: `check_command "cmd" "Name" "arg" 'pattern_([0-9]+\.[0-9]+)'`
- Platform-specific checks go inside the relevant `case "$OS" in ... esac` block.

---

## Files

```
EnvironmentCheck/
  EnvironmentCheck.sh          — universal cross-platform environment auditor
  EnvironmentCheck.bat         — Windows launcher (finds Git Bash via registry, runs the .sh)
  ScriptDefinition.md          — design notes and category reference

FindGitAccounts/
  FindGitAccounts.sh           — cross-platform Git/GitHub/GitLab account auditor
  ScriptDefinition.md          — design notes and section reference

SSHKeysCheck/
  SSHKeysCheck.sh              — cross-platform SSH key auditor
  SSHKeysCheck.bat             — Windows launcher (finds Git Bash via registry, runs the .sh)
  ScriptDefinition.md          — design notes and section reference

FindGitHubAccounts/
  FindGitHubAccounts.ps1       — Windows-only GitHub account auditor (PowerShell)
  ScriptDefinition.md          — design notes

PortScan/
  PortScan.sh                  — cross-platform TCP port scanner (nmap + bash/dev/tcp fallback)
  PortScan.bat                 — Windows launcher (finds Git Bash via registry, runs the .sh)
  ScriptDefinition.md          — design notes, options, and port preset reference
```
