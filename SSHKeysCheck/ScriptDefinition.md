# SSHKeysCheck.sh — SSH Key Auditor

`SSHKeysCheck.sh` performs a comprehensive audit of SSH keys and SSH configuration stored on the local machine. It reports key types, fingerprints, passphrase protection status, file permissions, SSH agent state, known hosts, authorized keys, and tests live connectivity to GitHub and GitLab.

Useful for security reviews, onboarding audits, and diagnosing SSH authentication failures.

Works on **Linux**, **macOS**, and **Windows** (Git Bash / WSL).
Requires Bash 3.2+ and `ssh`. Optional: `ssh-keygen`, `ssh-add`, `git`, `security` (macOS), `sc` / `reg` (Windows).

## Execution

```bash
# Linux / macOS
chmod +x SSHKeysCheck/SSHKeysCheck.sh
./SSHKeysCheck/SSHKeysCheck.sh

# Windows — Git Bash
bash SSHKeysCheck/SSHKeysCheck.sh

# Windows — .bat launcher (PowerShell / cmd / Explorer double-click)
.\SSHKeysCheck\SSHKeysCheck.bat

# Windows — PowerShell with explicit path
& "C:\Program Files\Git\bin\bash.exe" SSHKeysCheck\SSHKeysCheck.sh

# Save output
./SSHKeysCheck/SSHKeysCheck.sh | tee ssh-audit.txt
```

## Audit Sections (9 Checks)

### 1. SSH Directory

Verifies `~/.ssh` exists and checks its permissions (should be `700`). Lists all files in the directory.

### 2. Key Pairs

Enumerates all private/public key pairs (`id_*` / `id_*.pub`) in `~/.ssh/`. For each pair reports:

- **Fingerprint** — via `ssh-keygen -l`
- **Key type** — extracted from the public key (`ssh-rsa`, `ecdsa-sha2-nistp256`, `ssh-ed25519`, etc.)
- **Comment** — the label embedded in the public key (usually `user@host`)
- **Full public key** — the raw public key string
- **Permissions** — private key should be `600`; warns if incorrect
- **Passphrase** — tests whether the private key is passphrase-protected by attempting `ssh-keygen -y -P ""`. Reports `NONE` (unprotected) or `SET` (protected)

### 3. SSH Config

Parses `~/.ssh/config` and prints every `Host` block with its directives (`HostName`, `User`, `IdentityFile`, `Port`, etc.) in a formatted table. Reports the file's permissions.

### 4. SSH Agent

Runs `ssh-add -l` to list keys currently loaded in the SSH agent. Distinguishes between: agent running with keys, agent running but empty, and agent not running.

### 5. Known Hosts

Reads `~/.ssh/known_hosts` and reports:
- Total entry count
- Unique hostnames / IPs (dehashed, de-bracketed)
- GitHub and GitLab entries specifically

### 6. Authorized Keys

Reads `~/.ssh/authorized_keys` (relevant on servers or machines that accept inbound SSH). Reports permissions and lists all keys by type and comment.

### 7. Platform-Specific Checks

| Platform | What is checked |
|---|---|
| macOS | Keychain entries storing SSH passphrases (`security find-generic-password -s SSH`) |
| Windows / WSL | OpenSSH Agent service status (`sc query ssh-agent`); keys in Windows Agent registry (`HKCU\Software\OpenSSH\Agent\Keys`) |
| Linux | `SSH_AUTH_SOCK` environment variable; instructions to start agent if missing |

### 8. Connectivity Tests

Attempts a live SSH authentication test against `git@github.com` and `git@gitlab.com` using `BatchMode=yes` and a 5-second timeout. Reports:
- `[OK]` — successfully authenticated
- `[!]` — permission denied / no matching key
- `[?]` — connection timed out or unexpected output

No actual data is transferred; the connection is closed immediately after the auth handshake.

### 9. Summary

Prints aligned counters for all checks and flags actionable issues:
- Lists all key fingerprints
- Lists all SSH config `Host` entries
- Warns if any private key has no passphrase, with the command to add one
- Warns if keys exist but no `~/.ssh/config` is present

## Security Notes

- **Passphrase check** uses an empty passphrase attempt (`ssh-keygen -y -P ""`). No passwords are guessed or brute-forced.
- **No private key content is read or printed.** Only the corresponding `.pub` file is shown.
- **Connectivity tests** use `BatchMode=yes` — no interactive prompts are issued.
- All operations are **read-only**. No files are created, modified, or deleted.
