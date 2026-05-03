# EnvironmentCheck — Universal Developer Environment Checker

## Definition

**EnvironmentCheck** is a cross-platform Bash script that audits the presence, version, and configuration of developer tools on any workstation. It detects the operating system on startup and runs both universal checks and OS-specific checks automatically.

**Supported platforms:** Windows (Git Bash / MSYS2), Linux, macOS  
**Requires:** Bash 4.0+

---

## How to Run

### Windows (Git Bash / MSYS2)

**Prerequisite:** Git for Windows must be installed — it provides Git Bash, the Bash runtime used to run this script.

Download: https://git-scm.com/download/win

**Option 1 — `.bat` launcher from PowerShell or cmd (easiest):**
```powershell
.\EnvironmentCheck.bat
```
The launcher finds Git Bash via the Windows registry and runs the script automatically. Works from PowerShell, cmd, and double-click in Explorer. Prints a clear error if Git for Windows is not installed.

**Option 2 — from Git Bash terminal:**
```bash
bash EnvironmentCheck.sh
```

**Option 3 — from PowerShell with explicit path:**

In PowerShell, `bash` resolves to WSL (`C:\Windows\System32\bash.exe`), not Git Bash. Use the full path:
```powershell
& "C:\Program Files\Git\bin\bash.exe" EnvironmentCheck.sh
```

### Linux

```bash
chmod +x EnvironmentCheck/EnvironmentCheck.sh
./EnvironmentCheck/EnvironmentCheck.sh
```

### macOS

macOS ships with Bash 3.x. Install Bash 4+ via Homebrew first:

```bash
brew install bash
```

Then run:

```bash
chmod +x EnvironmentCheck/EnvironmentCheck.sh
./EnvironmentCheck/EnvironmentCheck.sh
```

### Save output to a file

```bash
./EnvironmentCheck/EnvironmentCheck.sh | tee env-report.txt
```

---

## OS Detection

The script determines the platform at startup before any checks run:

```bash
case "$(uname -s)" in
    Linux*)                      OS="linux"   ;;
    Darwin*)                     OS="macos"   ;;
    MINGW*|MSYS*|CYGWIN*|*NT*)  OS="windows" ;;
esac
```

All subsequent sections branch on `$OS` so Windows-only, macOS-only, and Linux-only checks are never executed on the wrong platform.

---

## Script Architecture

### Core function: `check_command`

```bash
check_command CMD NAME [VERSION_ARG] [PARSER_REGEX]
```

| Parameter | Description |
|-----------|-------------|
| `CMD` | Executable name (e.g. `git`, `node`) |
| `NAME` | Display label shown in output |
| `VERSION_ARG` | Argument passed to the command. Default: `--version`. Pass `""` for no argument. |
| `PARSER_REGEX` | Optional Bash regex; capture group 1 is used as the version string |

**Function workflow:**
1. Checks if the command exists in PATH via `command -v`; marks Missing immediately if not found
2. Executes the command, capturing both stdout and stderr
3. Takes the first line of output and trims whitespace
4. If the first line exceeds 100 characters, searches all output for a semver pattern (`X.Y.Z`)
5. Applies the optional regex if provided, using capture group 1
6. Stores the result in the `results` associative array for the summary

### Output helpers

```bash
ok "message"    # green  [OK]
warn "message"  # yellow [!]
fail "message"  # red    [X]
section "name"  # yellow section header
```

---

## What Is Checked

### Platform Features

Runs first. Content differs per OS.

**Windows**
| Check | Method |
|-------|--------|
| PowerShell version | `powershell.exe $PSVersionTable.PSVersion` |
| WSL (Windows Subsystem for Linux) | `wsl --status` |
| Hyper-V / Virtual Machine Platform | `powershell.exe Get-WindowsOptionalFeature` |

**macOS**
| Check | Method |
|-------|--------|
| macOS version | `sw_vers -productVersion` |
| Xcode Command Line Tools | `xcode-select --version` |
| Homebrew | `brew --version` |

**Linux**
| Check | Method |
|-------|--------|
| Kernel version | `uname -r` |
| Package manager (apt / dnf / pacman / zypper / emerge) | first found wins |
| systemd | `systemctl --version` |

---

### Core Tools

| Tool | Command | Notes |
|------|---------|-------|
| Git | `git --version` | |
| Visual Studio Code | `code --version` | |
| CMake | `cmake --version` | |
| Make | `make --version` | |
| 7-Zip | `7z i` (Linux/macOS) | Windows: PATH first, then registry via `powershell.exe` |

**Windows 7-Zip detection:** searches `HKLM:\SOFTWARE\7-Zip` and `HKLM:\SOFTWARE\WOW6432Node\7-Zip` for the install path when `7z` is not in PATH.

---

### System C++ Libraries

Each platform has its own C++ runtime. The script checks the platform-appropriate component automatically.

| Platform | Library | Method |
|----------|---------|--------|
| Windows | Visual C++ Redistributable (all installed versions) | Registry query via `powershell.exe` — scans both 32-bit and 64-bit uninstall keys in `HKLM:\SOFTWARE\...\Uninstall` |
| Linux | glibc (GNU C Library) | `getconf GNU_LIBC_VERSION` or `ldd --version` |
| Linux | libstdc++ | `ldconfig -p` to find the `.so`, then `dpkg` or `rpm` for version |
| macOS | libc++ (LLVM) | `find /usr/lib -name libc++.dylib`, version extracted via `otool -L` |

**Windows detail:** the check lists every installed VC++ Redistributable package with its version (e.g. `Microsoft Visual C++ 2015-2022 Redistributable (x64) v14.38.33135`). Missing VC++ runtimes are a common cause of "DLL not found" errors when running compiled applications.

**macOS note:** `libc++` is part of Xcode Command Line Tools. If the Xcode CLT check passes, libc++ is present.

---

### Python Ecosystem

| Tool | Purpose |
|------|---------|
| Python (`python3` / `python`) | Base interpreter |
| pip | Package installer; displayed as `pip X.Y, Python Z.A` |
| pipx | Isolated CLI app installer |
| Poetry | Dependency management and packaging |
| Pipenv | Virtual environment manager |
| Rye | Modern Python project manager |
| uv | Rust-based ultra-fast installer |
| uvx | Runs packages without installation |
| venv | Functional test: creates and removes a temporary environment |

**pip custom format:** the check extracts both the pip version and the associated Python version using the regex `pip ([0-9]+\.[0-9]+).*\(python ([0-9]+\.[0-9]+)\)` and displays them as `pip 25.2, Python 3.13`.

---

### Programming Runtimes

| Runtime | Command |
|---------|---------|
| Java (JRE) | `java -version` |
| Java (JDK) | `javac -version` |
| Go | `go version` |

---

### AI / Data Tools

| Tool | Command |
|------|---------|
| Anaconda / Miniconda | `conda --version` |
| Jupyter | `jupyter --version` |
| NVIDIA GPU Driver | `nvidia-smi` (no arguments) |

---

### Application Servers & Web Hosting

| Server | Command | Platform |
|--------|---------|----------|
| Apache HTTP Server | `httpd -v` | All |
| Nginx | `nginx -v` | All |
| IIS | `Get-WindowsOptionalFeature IIS-WebServerRole` | Windows only |

---

### Web / Frontend

| Tool | Command |
|------|---------|
| Node.js | `node -v` |
| npm | `npm -v` |
| pnpm | `pnpm -v` |
| Yarn | `yarn -v` |
| Bun | `bun --version` |
| Angular CLI | `ng version` |
| Vue CLI | `vue --version` |
| TypeScript Compiler | `tsc --version` |

---

### DevOps & Cloud

| Tool | Command | Notes |
|------|---------|-------|
| Docker | `docker --version` | |
| Docker Compose | `docker compose version` | Falls back to `docker-compose --version` |
| kubectl | `kubectl version --client` | |
| Helm | `helm version` | |
| Terraform | `terraform version` | |
| Azure CLI | `az --version` | |
| AWS CLI | `aws --version` | |
| Google Cloud CLI | `gcloud version` | |

**Docker Compose logic:** attempts the modern plugin (`docker compose`) first; if that fails, falls back to the legacy standalone binary (`docker-compose`).

---

### Microsoft Stack

| Tool | Command | Platform |
|------|---------|----------|
| .NET SDK | `dotnet --version` | All |
| MSBuild | `msbuild -version` | All (.NET SDK includes it on Linux/macOS) |
| NuGet | `nuget` (no arguments) | All |
| Visual Studio (Full IDE) | filesystem search + file metadata | Windows only |

**Visual Studio detection (Windows):** searches `C:/Program Files/Microsoft Visual Studio` recursively for `devenv.exe`, then reads the version from file metadata via `powershell.exe Get-Item` — avoids launching the GUI.

---

### Database Tools

| Database | Command |
|----------|---------|
| PostgreSQL | `psql --version` |
| MySQL | `mysql --version` |
| MongoDB Shell | `mongosh --version` |
| SQLite | `sqlite3 --version` |

---

### Version Control & Security

| Tool | Command | Notes |
|------|---------|-------|
| Git LFS | `git-lfs version` | |
| SSH | `ssh -V` | Regex `OpenSSH_([0-9]+\.[0-9]+p[0-9]+)` extracts clean version |
| GPG | `gpg --version` | |

---

### Build & Package Tools

| Tool | Command | Platform |
|------|---------|----------|
| Gradle | `gradle --version` | All |
| Maven | `mvn -v` | All |
| Chocolatey | `choco --version` | Windows |
| Winget | `winget --version` | Windows |
| Snap | `snap --version` | Linux |
| Flatpak | `flatpak --version` | Linux |

---

### Utilities

| Tool | Command |
|------|---------|
| Curl | `curl --version` |
| Wget | `wget --version` |
| OpenSSL | `openssl version` |
| Tar | `tar --version` |
| jq | `jq --version` |

---

## Output Format

### Real-time output

```
[OK] Git found:
     Version: git version 2.47.0

[X] Docker not found in PATH.

[!] Virtualization (Hyper-V / VMP) NOT enabled — Docker may fail.
```

### Summary table

Printed at the end, sorted alphabetically:

```
=== SUMMARY ===
[OK] Bash (5.2.21)
[OK] Git (git version 2.47.0)
[OK] Node.js (v22.3.0)
[X]  Docker
[!]  Virtualization (Warning: Disabled)
```

**Color coding:**
- Green `[OK]` — tool found and version extracted
- Red `[X]` — tool missing or not in PATH
- Yellow `[!]` — warning or feature disabled

---

## Extending the Script

### Add a new tool check

Place a `check_command` call in the relevant section:

```bash
check_command "toolname" "Display Name" "--version"
```

### Add a tool with a custom version argument

```bash
check_command "go" "Go" "version"
```

### Add a tool with no arguments

```bash
check_command "nvidia-smi" "NVIDIA GPU Driver" ""
```

### Add a custom regex parser

Use when the first output line is not the version, or you need to extract a substring. The regex must have one capture group:

```bash
check_command "ssh" "SSH" "-V" 'OpenSSH_([0-9]+\.[0-9]+p[0-9]+)'
```

### Add a Windows-only check

Wrap in the `windows` branch of the platform `case`:

```bash
case "$OS" in
    windows)
        check_command "winget" "Winget" "--version"
        ;;
esac
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `BASH_VERSINFO: bad array subscript` | Bash version is < 4. Install Bash 4+ (`brew install bash` on macOS) |
| Many tools show Missing despite being installed | Tools are not in `$PATH`. Add their directories to PATH. |
| `nvidia-smi` not found on a GPU machine | Driver may be installed but `nvidia-smi` not in PATH. Add `/usr/bin` or the driver bin directory to PATH. |
| Hyper-V / IIS show as `Warning` | Script is running without admin rights. Re-run in an elevated shell for accurate results. |
| Visual Studio not detected (Windows) | Verify installation path is under `C:/Program Files/Microsoft Visual Studio`. |
| Colors not showing | Terminal does not support ANSI codes. Colors are automatically disabled when output is not a TTY (e.g. redirected to a file). |

---

## Technical Requirements

| Requirement | Details |
|-------------|---------|
| Shell | Bash 4.0+ |
| Windows runtime | Git Bash, MSYS2, or WSL |
| Permissions | Standard user for most checks; admin for Windows Optional Feature checks |
| External dependencies | None — all checks use tools already present on the system |
| Network | No outbound connections made by the script itself |

---

## Security Considerations

- **Read-only:** no files are created, modified, or deleted (except a temporary venv directory that is immediately removed)
- **No network calls:** version checks are all local
- **No credential access:** no passwords, tokens, or secrets are read
- **No eval:** version arguments are passed as literal strings, not interpreted by the shell

---

**Last Updated:** May 2026  
**Script Version:** 1.0  
**Platforms:** Windows (Git Bash / MSYS2), Linux, macOS
