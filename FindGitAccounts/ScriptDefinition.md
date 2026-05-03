# FindGitAccounts.sh — Cross-Platform Git Account Auditor

`FindGitAccounts.sh` is a Bash script that performs a comprehensive audit of a machine to detect and report all configured or cached Git, GitHub, and GitLab identities and credentials.

Works on **Linux**, **macOS**, and **Windows** (Git Bash / WSL). Requires Bash 3.2+ and `git`. All other tools (`gh`, `glab`, `sqlite3`, `secret-tool`, `security`, `cmdkey`) are optional — checks degrade gracefully when they are absent.

## Execution

```bash
# Linux / macOS
chmod +x FindGitAccounts/FindGitAccounts.sh
./FindGitAccounts/FindGitAccounts.sh

# Windows — Git Bash
bash FindGitAccounts/FindGitAccounts.sh

# Windows — PowerShell (via Git Bash)
& "C:\Program Files\Git\bin\bash.exe" FindGitAccounts\FindGitAccounts.sh

# Save output
./FindGitAccounts/FindGitAccounts.sh | tee git-accounts-report.txt
```

## Audit Sections (Nine Checks)

### 1. Git Configuration (System / Global / Local)

Reads `user.name` and `user.email` at all three Git precedence levels:

- **System** — applies to all users (`/etc/gitconfig`, `C:\Program Files\Git\etc\gitconfig`).
- **Global** — applies to the current user (`~/.gitconfig`).
- **Local** — per-repository overrides (highest priority). Scans `$HOME` up to 6 levels deep for `.git` directories and reports any repo that sets its own identity.

### 2. Credential Stores

Platform-specific:

| Platform | Store checked |
|---|---|
| Windows / WSL | Windows Credential Manager (`cmdkey /list`) |
| macOS | Keychain (`security find-internet-password`, `find-generic-password`) |
| Linux | GNOME Keyring (`secret-tool search`) |
| All | `~/.git-credentials` (plaintext store), `~/.netrc` |

Passwords and tokens are redacted in output (`***`).

### 3. SSH Keys

Enumerates private keys in `~/.ssh/` (`id_*` files), prints the corresponding public key, and shows any matching entries in `~/.ssh/config` and `known_hosts` that reference `github.com` or `gitlab.com`.

### 4. VS Code Authentication Sessions

Checks for the `state.vscdb` SQLite session database for **VS Code** and **VS Code Insider** at the correct OS-specific path. If `sqlite3` is available, attempts to extract a raw session excerpt for GitHub/GitLab keys. Otherwise provides a manual step (`Developer: Show Authentication Sessions`).

| Platform | Path |
|---|---|
| Windows | `%APPDATA%\Code\User\globalStorage\state.vscdb` |
| macOS | `~/Library/Application Support/Code/User/globalStorage/state.vscdb` |
| Linux | `~/.config/Code/User/globalStorage/state.vscdb` |

### 5. Visual Studio Connected Accounts *(Windows / WSL only)*

Queries the Windows Registry key `HKCU\Software\Microsoft\VSCommon\ConnectedUser` using `reg query` (Git Bash) or `reg.exe query` (WSL). Extracts values that look like email addresses and classifies them as GitHub accounts, Microsoft accounts (potential GitHub link), or generic accounts. Skipped silently on Linux and macOS.

### 6. GitHub CLI (`gh`)

Runs `gh auth status` and parses logged-in hosts and usernames. Also prints the `~/.config/gh/hosts.yml` config (tokens redacted).

### 7. GitLab CLI (`glab`)

Runs `glab auth status` and parses active sessions. Also prints the `~/.config/glab-cli/config.yml` config (tokens redacted).

### 8. Local Repository Remotes

Scans `$HOME` (up to 6 levels deep) for `.git` directories and checks every configured remote URL. Reports repositories whose remotes point to `github.com` or `gitlab.com`, labelling each match by provider.

### 9. Summary

Prints aggregated counters for all checks and deduplicated lists of:
- Unique Git identities (names and emails)
- GitHub CLI usernames
- GitLab CLI usernames

## Comparison with FindGitHubAccounts.ps1

| Feature | `FindGitHubAccounts.ps1` | `FindGitAccounts.sh` |
|---|---|---|
| Platform | Windows only | Linux, macOS, Windows (Git Bash / WSL) |
| Providers | GitHub | Git, GitHub, GitLab |
| Credential stores | Windows Credential Manager | Credential Manager, Keychain, secret-tool, `.git-credentials`, `.netrc` |
| GitLab CLI | — | `glab auth status` |
| SSH key audit | — | Yes |
| Visual Studio registry | Yes | Yes (`reg query` / `reg.exe`) |
| Shell | PowerShell | Bash 3.2+ |
