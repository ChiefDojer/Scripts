# Ultimate Windows Developer Environment Checker (v3.2)

## Definition

The **Ultimate Windows Developer Environment Checker** is a comprehensive PowerShell diagnostic script designed to audit and validate the presence, configuration, and versions of development tools, runtimes, frameworks, and system features installed on Windows systems. It provides developers with a complete overview of their development environment in a single execution.

---

## Overview

This automated auditing tool systematically checks over 50 different development tools, platforms, and system features across multiple technology stacks. It provides color-coded output with detailed version information, making it easy to identify missing dependencies, outdated tools, or configuration issues.

### Key Features

- **Comprehensive Coverage**: Checks tools across 11 major categories
- **Version Extraction**: Displays actual version numbers, not just presence/absence
- **Smart Detection**: Searches beyond PATH for tools like 7-Zip and Visual Studio
- **Error Resilience**: Continues execution even when individual checks fail
- **Clean Output**: Color-coded results with organized sectional display
- **Summary Report**: Consolidated status table at completion
- **Non-Destructive**: Read-only operations with no system modifications

---

## Technical Architecture

### Script Structure

The script is organized into the following components:

1. **Initialization Block**: Sets up variables and displays script header
2. **Core Function**: `Check-Command` - Reusable verification logic
3. **Category Sections**: Organized checks for different tool types
4. **Error Handling**: Try-Catch-Finally blocks for graceful failure recovery
5. **Summary Generation**: Results compilation and display

### The `Check-Command` Function

```powershell
function Check-Command {
    param(
        [string]$cmd,           # Command to execute
        [string]$name,          # Display name
        [string]$arg,           # Argument (default: --version)
        [string]$Parser         # Optional regex for version extraction
    )
}
```

**Function Workflow:**
1. Executes the command with specified arguments
2. Captures both stdout and stderr (using `2>&1`)
3. Validates exit code and output presence
4. Cleans multi-line output to single-line version string
5. Applies optional regex parsing for custom extraction
6. Stores results in the global `$results` hashtable
7. Displays color-coded output (Green for success, Red for failure)

### Advanced Detection Techniques

#### Registry-Based Discovery
For tools not in PATH (e.g., 7-Zip, Visual Studio):
- Searches Windows Registry for installation paths
- Checks both 32-bit and 64-bit registry hives
- Validates file existence before execution

#### File Metadata Reading
For executables that hang on execution (e.g., `devenv.exe`):
- Reads version information from file properties
- Extracts ProductVersion and ProductName
- Avoids launching GUI applications

#### Dual-Mode Checks
For tools with multiple installation methods (e.g., Docker Compose):
- Attempts modern plugin-based approach first
- Falls back to legacy standalone installation
- Reports which variant was detected

---

## Category Breakdown

### 1. Windows Platform Features

| Check | Purpose | Method |
|-------|---------|--------|
| **WSL Status** | Validates Windows Subsystem for Linux | `wsl --status` command |
| **Virtualization** | Checks Hyper-V/Virtual Machine Platform | `Get-WindowsOptionalFeature` cmdlet |

**Importance**: Essential for Docker Desktop, containerized development, and Linux-based workflows.

### 2. Core System Tools

| Tool | Typical Use Case |
|------|------------------|
| **PowerShell** | Built-in version detection via `$PSVersionTable` |
| **Git** | Version control for source code management |
| **VS Code** | Primary code editor verification |
| **7-Zip** | Archive manipulation and compression |
| **CMake** | Cross-platform build system generator |
| **Make** | Build automation tool (Unix-style) |

**Special Handling**: 7-Zip uses registry-based discovery with custom parsing of non-standard output.

### 3. Python Ecosystem

Comprehensive Python development stack validation:

- **Python Interpreter**: Base runtime check
- **pip**: Package installer with custom dual-version display (pip version + Python version)
- **pipx**: Isolated CLI application installer
- **Poetry**: Modern dependency management and packaging
- **Pipenv**: Virtual environment and dependency manager
- **venv Module**: Tests actual virtual environment creation (not just presence)

**Custom Enhancement**: The pip check extracts both pip version and associated Python version using regex pattern matching on the output format: `pip X.Y from ... (python Z.A)`

### 4. Programming Runtimes

| Runtime | Languages Supported | Check Method |
|---------|-------------------|--------------|
| **JRE** | Java runtime | `java -version` |
| **JDK** | Java development | `javac -version` |
| **Go** | Golang | `go version` |

### 5. AI & Data Science Tools

| Tool | Purpose |
|------|---------|
| **Anaconda/Miniconda** | Python distribution for data science |
| **Jupyter** | Interactive notebook environment |
| **NVIDIA GPU Driver** | GPU acceleration via `nvidia-smi` |

### 6. Application Servers & Web Hosting

Checks for production-grade web servers:

- **Apache HTTPD**: Open-source web server
- **Nginx**: High-performance web server and reverse proxy
- **IIS**: Microsoft's Internet Information Services (Windows Feature check)

**IIS Detection**: Uses `Get-WindowsOptionalFeature` to verify the IIS-WebServerRole feature state.

### 7. Web & Frontend Development

Modern JavaScript/TypeScript ecosystem:

- **Node.js**: JavaScript runtime
- **npm**: Node package manager
- **pnpm**: Performant npm alternative
- **yarn**: Facebook's package manager
- **Angular CLI**: Angular framework CLI
- **Vue CLI**: Vue.js framework CLI
- **TypeScript**: Explicit TypeScript compiler check

### 8. DevOps & Cloud Tools

Complete cloud-native development stack:

| Category | Tools |
|----------|-------|
| **Containerization** | Docker, Docker Compose |
| **Orchestration** | Kubernetes (kubectl), Helm |
| **Infrastructure as Code** | Terraform |
| **Cloud Platforms** | Azure CLI, AWS CLI, Google Cloud CLI |

**Docker Compose Logic**: Attempts modern `docker compose` plugin first, then falls back to legacy `docker-compose` standalone binary.

### 9. Microsoft Stack

.NET and Visual Studio ecosystem:

- **.NET SDK**: Core .NET development kit
- **MSBuild**: Microsoft build engine
- **Visual Studio**: Full IDE (searches filesystem, reads metadata)
- **NuGet**: .NET package manager

**Visual Studio Challenge**: The script overcomes the issue of `devenv.exe` not being in PATH and hanging when executed by:
1. Searching `C:\Program Files\Microsoft Visual Studio` recursively
2. Finding the most recent installation
3. Reading version info from file metadata instead of executing

### 10. Database Tools

| Database | Client Tool |
|----------|-------------|
| PostgreSQL | psql |
| MySQL | mysql |
| MongoDB | mongosh |
| SQLite | sqlite3 |

**Note**: PostgreSQL's `psql` outputs version info to stderr, requiring the `2>&1` redirection in the check function.

### 11. Version Control & Collaboration

- **Git**: Source control
- **Git LFS**: Large File Storage extension
- **SSH**: Secure Shell (uses `-V` flag with custom regex to extract clean version)
- **GPG**: GNU Privacy Guard for signing

**SSH Enhancement**: Uses regex pattern `OpenSSH_(\d+\.\d+p\d+)` to extract just the version number from verbose output.

### 12. Build & Package Managers

- **Gradle**: Java/Android build automation
- **Maven**: Java project management and build tool
- **Chocolatey**: Windows package manager
- **Winget**: Microsoft's official package manager

### 13. Utilities

Essential command-line tools:

- **curl.exe**: Data transfer tool (`.exe` suffix bypasses PowerShell alias)
- **wget**: Network downloader
- **OpenSSL**: Cryptography toolkit
- **tar**: Archive utility

---

## Output Format

### Real-Time Display

Each check produces immediate feedback:

```
[OK] Git found:
     Version: git version 2.42.0
```

```
[X] Docker not found or failed execution. Details: ...
```

```
[!] Virtualization platform (Hyper-V/VMP) NOT enabled. Docker may fail.
```

### Summary Table

At completion, a consolidated status report displays all results:

```
=== SUMMARY ===
[OK] PowerShell (7.4.0)
[OK] Git (git version 2.42.0)
[X] Docker
[!] Virtualization (Warning: Disabled)
...
```

**Color Coding:**
- 🟢 **Green** `[OK]`: Tool found and working
- 🔴 **Red** `[X]`: Tool missing or failed
- 🟡 **Yellow** `[!]`: Warning or manual check required

---

## Error Handling Strategy

### Multi-Level Protection

1. **Function-Level**: Each `Check-Command` wrapped in try-catch
2. **Script-Level**: Main execution block wrapped in try-catch-finally
3. **Graceful Degradation**: Failed checks don't stop execution
4. **Descriptive Messages**: Error details displayed without technical jargon

### Exit Code Handling

The script properly handles tools that:
- Return non-zero exit codes on version checks (e.g., 7-Zip)
- Output to stderr instead of stdout (e.g., psql)
- Require elevation for certain checks (Windows Features)

### Console Title Preservation

**Critical Feature**: The script saves and restores the original console window title in the `finally` block, ensuring no persistent changes to the user's terminal session.

---

## Version History & Enhancements

### Version 3.2 (Current)

**Major Enhancement**: Custom pip parser displaying both pip and Python versions in format: `pip 25.2, Python 3.13`

**Implementation**:
```powershell
$parser = 'pip (\d+\.\d+).*\(python (\d+\.\d+)\)'
if ($versionString -match $parser) {
    $displayVersion = "pip $($Matches[1]), Python $($Matches[2])"
}
```

### Key Historical Improvements

- **v3.x**: Added registry-based tool discovery
- **v3.x**: Implemented file metadata reading for GUI apps
- **v3.x**: Enhanced multi-line output cleaning
- **v3.x**: Added support for Windows optional features

---

## Use Cases

### 1. Onboarding New Developers
Run script on new machines to verify complete environment setup and identify missing tools.

### 2. Pre-Project Audits
Before starting a new project, confirm all required dependencies are installed.

### 3. Troubleshooting Build Failures
When builds fail mysteriously, verify that all build tools are present and accessible.

### 4. Documentation Generation
Export the summary to create accurate "Development Environment" documentation sections.

### 5. CI/CD Agent Validation
Run on build agents to verify consistent tooling across the pipeline.

### 6. Migration Verification
After OS upgrades or machine migrations, confirm all tools were properly restored.

---

## Limitations & Considerations

### Administrative Privileges

Some checks require elevation:
- Windows Optional Feature queries (Hyper-V, IIS)
- Deep system configuration inspection

**Script Behavior**: Gracefully handles permission errors with warning messages rather than failing.

### PATH Dependency

Most checks rely on tools being in the system PATH. The script includes workarounds for:
- 7-Zip (registry search)
- Visual Studio (filesystem search)

**Future Enhancement**: Could be extended to search common installation directories for more tools.

### Version Format Variations

Different tools use wildly different version output formats:
- Single-line vs. multi-line
- Stdout vs. stderr
- JSON vs. plain text
- Marketing versions vs. semantic versions

The script includes custom parsing logic for problematic tools but may display verbose output for tools with unusual formats.

### Performance

Full execution typically takes 15-30 seconds depending on:
- Number of tools installed
- Disk I/O speed (for filesystem searches)
- Network connectivity (some tools query online versions)

---

## Extension Guide

### Adding New Tool Checks

To add a new tool, simply add a call in the appropriate category:

```powershell
Check-Command "toolname" "Display Name" "--version" "optional-regex-pattern"
```

### Creating Custom Parsers

For tools with complex output:

```powershell
Check-Command "tool" "Tool Name" "version" '(\d+\.\d+\.\d+)'
```

The regex pattern should capture the desired version string in group 1 (`$Matches[1]`).

### Adding New Categories

1. Add a section header:
```powershell
Write-Host "--- Checking New Category ---" -ForegroundColor Yellow
```

2. Add checks within the section
3. Results automatically appear in the summary table

---

## Best Practices

### Running the Script

1. **Open PowerShell** (no elevation needed for most checks)
2. **Navigate to script location**: `cd C:\path\to\script`
3. **Execute**: `.\environment-checker.ps1`
4. **Review output**: Scroll through or redirect to file

### Interpreting Results

- **Focus on Red [X] items first**: These are completely missing
- **Investigate Yellow [!] warnings**: May indicate configuration issues
- **Verify versions match project requirements**: Green doesn't mean compatible

### Integration with Development Workflow

- **Run weekly** to catch accidental tool removals
- **Run after major updates** (Windows updates, tool upgrades)
- **Share results** when reporting environment-related bugs
- **Version control the script** alongside project documentation

---

## Troubleshooting

### Common Issues

**Issue**: Script won't run - "Execution Policy" error  
**Solution**: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

**Issue**: Many tools show as missing despite being installed  
**Solution**: Tools may not be in PATH. Add installation directories to system PATH.

**Issue**: Virtualization shows disabled but Docker works  
**Solution**: Script may not have admin rights. Run `Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform` in elevated PowerShell.

**Issue**: Visual Studio not detected  
**Solution**: Check installation path matches expected location (`C:\Program Files\Microsoft Visual Studio\`)

---

## Technical Requirements

- **Operating System**: Windows 10/11 or Windows Server 2016+
- **PowerShell**: Version 5.1 or higher (built into Windows)
- **Permissions**: Standard user for most checks, admin for platform features
- **Dependencies**: None - script is self-contained

---

## Security Considerations

- **Read-Only Operations**: Script performs no installations or modifications
- **No Network Calls**: Except for tools that inherently check online (e.g., `aws --version`)
- **No Credential Handling**: No passwords, tokens, or sensitive data accessed
- **Safe Execution**: All commands are version checks with no side effects

---

## Performance Optimization Tips

The script is already optimized, but for faster execution:

1. **Comment out unused categories**: If you don't do Python development, comment out that section
2. **Run in elevated PowerShell**: Eliminates permission-related retries
3. **Add tools to PATH**: Reduces time spent on registry/filesystem searches

---

## Conclusion

The Ultimate Windows Developer Environment Checker (v3.2) is an essential tool for maintaining development environment health. Its comprehensive coverage, intelligent detection logic, and user-friendly output make it invaluable for individual developers, teams, and organizations managing multiple development workstations.

By providing instant visibility into the development toolchain, it reduces onboarding time, accelerates troubleshooting, and ensures consistent environments across teams.

---

**Last Updated**: October 2025  
**Script Version**: 3.2  
**Maintainer**: Community-driven development  
**License**: Free for personal and commercial use
