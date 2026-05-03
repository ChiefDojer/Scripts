#!/usr/bin/env bash
# ================================================================
# UNIVERSAL DEVELOPER ENVIRONMENT CHECKER
# ================================================================
# Supports: Windows (Git Bash / MSYS2), Linux, macOS
# Requires: Bash 4.0+
#
# WINDOWS USERS: this script runs inside Git Bash, which is part
# of Git for Windows. Install it first, then run from Git Bash:
#   https://git-scm.com/download/win
# ================================================================

if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: Bash 4.0+ required. On macOS: brew install bash" >&2
    exit 1
fi

declare -A results

# ----------------------------------------------------------------
# COLORS (disabled when not writing to a terminal)
# ----------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    DGRAY='\033[0;90m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; DGRAY=''; NC=''
fi

# ----------------------------------------------------------------
# OS DETECTION — must be first
# ----------------------------------------------------------------
detect_os() {
    local s
    s="$(uname -s 2>/dev/null || echo 'Unknown')"
    case "$s" in
        Linux*)                      echo "linux"   ;;
        Darwin*)                     echo "macos"   ;;
        MINGW*|MSYS*|CYGWIN*|*NT*)  echo "windows" ;;
        *)                           echo "unknown" ;;
    esac
}

OS=$(detect_os)

# ----------------------------------------------------------------
# OUTPUT HELPERS
# ----------------------------------------------------------------
section() { echo -e "\n${YELLOW}--- $1 ---${NC}"; }
ok()      { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
fail()    { echo -e "${RED}[X]${NC} $1"; }

# ----------------------------------------------------------------
# CORE CHECK FUNCTION
# ----------------------------------------------------------------
# Usage: check_command CMD NAME [VERSION_ARG] [PARSER_REGEX]
#   VERSION_ARG   default "--version"; pass "" to run with no args
#   PARSER_REGEX  optional bash regex; capture group 1 used as version
# ----------------------------------------------------------------
check_command() {
    local cmd="$1"
    local name="$2"
    local arg parser

    if (( $# >= 3 )); then arg="$3"; else arg="--version"; fi
    parser="${4:-}"

    if ! command -v "$cmd" &>/dev/null; then
        fail "$name not found in PATH."
        echo ""
        results["$name"]="Missing"
        return
    fi

    local output="" exit_code=0
    if [[ -z "$arg" ]]; then
        output=$("$cmd" 2>&1) || exit_code=$?
    else
        # shellcheck disable=SC2086
        output=$("$cmd" $arg 2>&1) || exit_code=$?
    fi

    if [[ -n "$output" ]]; then
        local version
        version=$(printf '%s\n' "$output" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # For unexpectedly long first lines, search for a semver pattern
        if (( ${#version} > 100 )); then
            local found
            found=$(printf '%s\n' "$output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            [[ -n "$found" ]] && version="$found"
        fi

        # Apply optional regex parser (capture group 1)
        if [[ -n "$parser" && "$version" =~ $parser ]]; then
            version="${BASH_REMATCH[1]}"
        fi

        [[ -z "$version" ]] && version="Found"

        ok "$name found:"
        echo "     Version: $version"
        echo ""
        results["$name"]="$version"
    else
        fail "$name failed to return output."
        echo ""
        results["$name"]="Unknown"
    fi
}

# ================================================================
# PLATFORM-SPECIFIC CHECKS
# ================================================================

# ---- Windows ----

check_powershell() {
    local version
    version=$(powershell.exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' \
        2>/dev/null | tr -d '\r' || true)
    if [[ -n "$version" ]]; then
        ok "PowerShell found:"
        echo "     Version: $version"
        echo ""
        results["PowerShell"]="$version"
    else
        fail "PowerShell not found or failed."
        echo ""
        results["PowerShell"]="Missing"
    fi
}

check_wsl() {
    local status
    status=$(wsl --status 2>&1 | grep -i "Default Distribution" || true)
    if [[ -n "$status" ]]; then
        ok "WSL found and initialized."
        echo ""
        results["WSL"]="Active"
    else
        fail "WSL not found or no default distribution set."
        echo ""
        results["WSL"]="Missing"
    fi
}

check_hyperv() {
    local hv vmp
    hv=$(powershell.exe -NoProfile -Command \
        "(Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction SilentlyContinue).State" \
        2>/dev/null | tr -d '\r' || true)
    vmp=$(powershell.exe -NoProfile -Command \
        "(Get-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform' -ErrorAction SilentlyContinue).State" \
        2>/dev/null | tr -d '\r' || true)

    if [[ "$hv" == *"Enabled"* || "$vmp" == *"Enabled"* ]]; then
        ok "Virtualization (Hyper-V / VMP) enabled."
        echo ""
        results["Virtualization"]="Enabled"
    else
        warn "Virtualization (Hyper-V / VMP) NOT enabled — Docker may fail."
        echo ""
        results["Virtualization"]="Warning: Disabled"
    fi
}

check_iis() {
    local state
    state=$(powershell.exe -NoProfile -Command \
        "(Get-WindowsOptionalFeature -Online -FeatureName 'IIS-WebServerRole' -ErrorAction SilentlyContinue).State" \
        2>/dev/null | tr -d '\r' || true)
    if [[ "$state" == *"Enabled"* ]]; then
        ok "IIS Web Server Feature enabled."
        results["IIS"]="Enabled"
    else
        warn "IIS Web Server Feature NOT enabled."
        results["IIS"]="Disabled"
    fi
    echo ""
}

check_7zip_windows() {
    local path=""

    if command -v 7z &>/dev/null; then
        path=$(command -v 7z)
    else
        warn "7z not in PATH. Searching registry..."
        local reg
        for key in 'HKLM:\SOFTWARE\7-Zip' 'HKLM:\SOFTWARE\WOW6432Node\7-Zip'; do
            reg=$(powershell.exe -NoProfile -Command \
                "(Get-ItemProperty '$key' -Name Path -ErrorAction SilentlyContinue).Path" \
                2>/dev/null | tr -d '\r' || true)
            [[ -n "$reg" ]] && path="${reg}7z.exe" && break
        done
    fi

    if [[ -n "$path" && -f "$path" ]]; then
        local output version
        output=$("$path" 2>&1 | head -5 || true)
        version=$(printf '%s\n' "$output" | grep "7-Zip" | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
        ok "7-Zip found:"
        echo "     Version: ${version:-Found}"
        echo ""
        results["7-Zip"]="${version:-Found}"
    else
        fail "7-Zip not found."
        echo ""
        results["7-Zip"]="Missing"
    fi
}

check_visual_studio() {
    local vs_root=""
    for root in "/c/Program Files/Microsoft Visual Studio" "C:/Program Files/Microsoft Visual Studio"; do
        [[ -d "$root" ]] && vs_root="$root" && break
    done

    if [[ -n "$vs_root" ]]; then
        local devenv
        devenv=$(find "$vs_root" -name "devenv.exe" 2>/dev/null | sort -r | head -1 || true)
        if [[ -n "$devenv" ]]; then
            local version
            version=$(powershell.exe -NoProfile -Command \
                "(Get-Item '$devenv').VersionInfo.ProductVersion" \
                2>/dev/null | tr -d '\r' || true)
            ok "Visual Studio (Full) found:"
            echo "     Path: $devenv"
            echo "     Version: ${version:-unknown}"
            echo ""
            results["Visual Studio (Full)"]="${version:-Found}"
        else
            fail "Visual Studio (devenv.exe) not found in $vs_root."
            echo ""
            results["Visual Studio (Full)"]="Missing"
        fi
    else
        fail "Visual Studio installation root not found."
        echo ""
        results["Visual Studio (Full)"]="Missing"
    fi
}

# ---- macOS ----

check_xcode_clt() {
    if command -v xcode-select &>/dev/null; then
        local version
        version=$(xcode-select --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
        ok "Xcode Command Line Tools found:"
        echo "     Version: ${version:-Found}"
        echo ""
        results["Xcode CLT"]="${version:-Found}"
    else
        fail "Xcode Command Line Tools not found."
        echo ""
        results["Xcode CLT"]="Missing"
    fi
}

# ---- Linux ----

check_linux_pkg_manager() {
    for pm in apt dnf pacman zypper emerge; do
        if command -v "$pm" &>/dev/null; then
            local version
            version=$("$pm" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
            ok "Package manager '$pm' found:"
            echo "     Version: ${version:-Found}"
            echo ""
            results["Package Manager ($pm)"]="${version:-Found}"
            return
        fi
    done
    warn "No known package manager found (apt/dnf/pacman/zypper/emerge)."
    echo ""
    results["Package Manager"]="Not detected"
}

# ---- Cross-platform special cases ----

# pip: custom formatter showing "pip X.Y, Python Z.A"
check_pip() {
    local pip_cmd=""
    if command -v pip3 &>/dev/null; then
        pip_cmd="pip3"
    elif command -v pip &>/dev/null; then
        pip_cmd="pip"
    else
        fail "pip not found in PATH."
        echo ""
        results["pip"]="Missing"
        return
    fi

    local output exit_code=0
    output=$("$pip_cmd" --version 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 && -n "$output" ]]; then
        local display
        if [[ "$output" =~ pip\ ([0-9]+\.[0-9]+).*\(python\ ([0-9]+\.[0-9]+)\) ]]; then
            display="pip ${BASH_REMATCH[1]}, Python ${BASH_REMATCH[2]}"
        else
            display=$(echo "$output" | head -1)
        fi
        ok "pip found:"
        echo "     Version: $display"
        echo ""
        results["pip"]="$display"
    else
        fail "pip not found or failed."
        echo ""
        results["pip"]="Missing"
    fi
}

# Docker Compose: plugin-first, fallback to standalone
check_docker_compose() {
    if ! command -v docker &>/dev/null; then
        fail "Docker Compose not found (Docker itself is missing)."
        echo ""
        results["Docker Compose"]="Missing"
        return
    fi

    local output exit_code=0
    output=$(docker compose version 2>&1) || exit_code=$?
    if [[ $exit_code -eq 0 && -n "$output" ]]; then
        local version
        version=$(echo "$output" | head -1)
        ok "Docker Compose (plugin) found:"
        echo "     Version: $version"
        echo ""
        results["Docker Compose"]="$version"
    else
        check_command "docker-compose" "Docker Compose (standalone)" "--version"
    fi
}

# ---- C++ runtime libraries (platform-specific) ----

# Windows: Visual C++ Redistributable packages (from registry)
check_vcredist_windows() {
    local entries
    entries=$(powershell.exe -NoProfile -Command "
        \$paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        Get-ItemProperty \$paths -ErrorAction SilentlyContinue |
        Where-Object { \$_.DisplayName -like '*Microsoft Visual C++*' } |
        Select-Object DisplayName, DisplayVersion |
        Sort-Object DisplayName |
        ForEach-Object { '  ' + \$_.DisplayName + '  v' + \$_.DisplayVersion }
    " 2>/dev/null | tr -d '\r' || true)

    if [[ -n "$entries" ]]; then
        local count
        count=$(echo "$entries" | grep -c '\S' || true)
        ok "Visual C++ Redistributable packages found ($count):"
        while IFS= read -r line; do
            [[ -n "${line// }" ]] && echo "    $line"
        done <<< "$entries"
        echo ""
        results["Visual C++ Redistributable"]="$count packages"
    else
        warn "No Visual C++ Redistributable packages found."
        echo ""
        results["Visual C++ Redistributable"]="Missing"
    fi
}

# Linux: glibc and libstdc++
check_cpplibs_linux() {
    # glibc
    local glibc_ver
    glibc_ver=$(getconf GNU_LIBC_VERSION 2>/dev/null ||
                ldd --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
    if [[ -n "$glibc_ver" ]]; then
        ok "glibc (GNU C Library) found:"
        echo "     Version: $glibc_ver"
        echo ""
        results["glibc"]="$glibc_ver"
    else
        fail "glibc not detected."
        echo ""
        results["glibc"]="Missing"
    fi

    # libstdc++: find the shared object, then try to get its version
    local stdc_path stdc_ver
    stdc_path=$(ldconfig -p 2>/dev/null | grep 'libstdc++\.so' | head -1 |
                sed 's/.*=> //' | tr -d ' \t' || true)
    [[ -z "$stdc_path" ]] && \
        stdc_path=$(find /usr/lib* -name 'libstdc++.so*' 2>/dev/null | head -1 || true)

    if [[ -n "$stdc_path" ]]; then
        # Try dpkg first, then rpm, then fall back to "installed"
        stdc_ver=$(dpkg -l 'libstdc++*' 2>/dev/null | awk '/^ii/{print $3; exit}' || true)
        [[ -z "$stdc_ver" ]] && \
            stdc_ver=$(rpm -q --qf '%{VERSION}' libstdc++ 2>/dev/null | head -1 || true)
        ok "libstdc++ found:"
        echo "     Version: ${stdc_ver:-found at $stdc_path}"
        echo ""
        results["libstdc++"]="${stdc_ver:-Installed}"
    else
        fail "libstdc++ not detected."
        echo ""
        results["libstdc++"]="Missing"
    fi
}

# macOS: libc++ (ships with Xcode CLT, lives in /usr/lib)
check_libcxx_macos() {
    local lib_path
    lib_path=$(find /usr/lib -name 'libc++.dylib' -maxdepth 2 2>/dev/null | head -1 || true)

    if [[ -n "$lib_path" ]]; then
        # Extract version from dylib info
        local ver
        ver=$(otool -L "$lib_path" 2>/dev/null |
              grep 'libc++\.' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        ok "libc++ (LLVM C++ Standard Library) found:"
        echo "     Path: $lib_path"
        [[ -n "$ver" ]] && echo "     Version: $ver"
        echo ""
        results["libc++"]="${ver:-Installed}"
    else
        warn "libc++ not found in /usr/lib. Xcode CLT may not be installed."
        echo ""
        results["libc++"]="Missing"
    fi
}

# ================================================================
# MAIN SCRIPT
# ================================================================
echo -e "\n${CYAN}=== UNIVERSAL DEV ENVIRONMENT CHECK ===${NC}"
echo -e "${DGRAY}Platform: ${OS} | Bash: ${BASH_VERSION}${NC}"

if [[ "$OS" == "windows" ]]; then
    echo -e "${YELLOW}NOTE: Running on Windows via Git Bash (Git for Windows).${NC}"
    echo -e "${DGRAY}      You are in Git Bash — prerequisite is met.${NC}"
    echo -e "${DGRAY}      From PowerShell use: & \"C:\Program Files\Git\bin\bash.exe\" EnvironmentCheck.sh${NC}"
    echo -e "${DGRAY}      (PowerShell's 'bash' points to WSL, not Git Bash)${NC}"
fi
echo ""

results["Bash"]="$BASH_VERSION"

# ================================================================
# PLATFORM FEATURES
# ================================================================
section "Platform Features"

case "$OS" in
    windows)
        check_powershell
        check_wsl
        check_hyperv
        ;;
    macos)
        echo -e "${DGRAY}macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')${NC}\n"
        check_xcode_clt
        check_command "brew" "Homebrew" "--version"
        ;;
    linux)
        echo -e "${DGRAY}Kernel: $(uname -r)${NC}\n"
        check_linux_pkg_manager
        if command -v systemctl &>/dev/null; then
            _sver=$(systemctl --version 2>&1 | head -1 || true)
            ok "systemd found: $_sver"
            echo ""
            results["systemd"]="$_sver"
        fi
        ;;
esac

# ================================================================
# CORE TOOLS
# ================================================================
section "Core Tools"
check_command "git"    "Git"                  "--version"
check_command "code"   "Visual Studio Code"   "--version"
check_command "cmake"  "CMake"                "--version"
check_command "make"   "Make"                 "--version"

if [[ "$OS" == "windows" ]]; then
    check_7zip_windows
else
    check_command "7z" "7-Zip" "i"
fi

# ================================================================
# SYSTEM C++ LIBRARIES
# ================================================================
section "System C++ Libraries"

case "$OS" in
    windows) check_vcredist_windows ;;
    linux)   check_cpplibs_linux    ;;
    macos)   check_libcxx_macos     ;;
esac

# ================================================================
# PYTHON ECOSYSTEM
# ================================================================
section "Python Ecosystem"

if command -v python3 &>/dev/null; then
    check_command "python3" "Python" "--version"
else
    check_command "python" "Python" "--version"
fi

check_pip
check_command "pipx"    "pipx"    "--version"
check_command "poetry"  "Poetry"  "--version"
check_command "pipenv"  "Pipenv"  "--version"
check_command "rye"     "Rye"     "--version"
check_command "uv"      "UV"      "--version"
check_command "uvx"     "UVX"     "--version"

# Python venv functional test
_python_cmd=""
command -v python3 &>/dev/null && _python_cmd="python3"
command -v python  &>/dev/null && [[ -z "$_python_cmd" ]] && _python_cmd="python"

if [[ -n "$_python_cmd" ]]; then
    _venv_tmp="$(mktemp -d)/testenv"
    if "$_python_cmd" -m venv "$_venv_tmp" 2>/dev/null && [[ -d "$_venv_tmp" ]]; then
        rm -rf "$_venv_tmp"
        ok "Python venv module working"
        echo ""
        results["Python venv"]="Working"
    else
        fail "Python venv module failed."
        echo ""
        results["Python venv"]="Missing"
    fi
fi

# ================================================================
# PROGRAMMING RUNTIMES
# ================================================================
section "Programming Runtimes"
check_command "java"   "Java (JRE)" "-version"
check_command "javac"  "Java (JDK)" "-version"
check_command "go"     "Go"         "version"

# ================================================================
# AI / DATA TOOLS
# ================================================================
section "AI / Data Tools"
check_command "conda"       "Anaconda/Miniconda"  "--version"
check_command "jupyter"     "Jupyter"             "--version"
check_command "nvidia-smi"  "NVIDIA GPU Driver"   ""

# ================================================================
# APPLICATION SERVERS & WEB HOSTING
# ================================================================
section "Application Servers & Web Hosting"
check_command "httpd"  "Apache HTTP Server"  "-v"
check_command "nginx"  "Nginx"               "-v"
[[ "$OS" == "windows" ]] && check_iis

# ================================================================
# WEB / FRONTEND
# ================================================================
section "Web / Frontend"
check_command "node"  "Node.js"              "-v"
check_command "npm"   "npm"                  "-v"
check_command "pnpm"  "pnpm"                 "-v"
check_command "yarn"  "yarn"                 "-v"
check_command "bun"   "Bun"                  "--version"
check_command "ng"    "Angular CLI"          "version"
check_command "vue"   "Vue CLI"              "--version"
check_command "tsc"   "TypeScript Compiler"  "--version"

# ================================================================
# DEVOPS & CLOUD
# ================================================================
section "DevOps & Cloud"
check_command "docker"     "Docker"          "--version"
check_docker_compose
check_command "kubectl"    "kubectl"         "version --client"
check_command "helm"       "Helm"            "version"
check_command "terraform"  "Terraform"       "version"
check_command "az"         "Azure CLI"       "--version"
check_command "aws"        "AWS CLI"         "--version"
check_command "gcloud"     "Google Cloud CLI" "version"

# ================================================================
# MICROSOFT STACK
# ================================================================
section "Microsoft Stack"
check_command "dotnet"   ".NET SDK"  "--version"
check_command "msbuild"  "MSBuild"   "-version"
check_command "nuget"    "NuGet"     ""
[[ "$OS" == "windows" ]] && check_visual_studio

# ================================================================
# DATABASES
# ================================================================
section "Database Tools"
check_command "psql"     "PostgreSQL (psql)"  "--version"
check_command "mysql"    "MySQL Client"       "--version"
check_command "mongosh"  "MongoDB Shell"      "--version"
check_command "sqlite3"  "SQLite"             "--version"

# ================================================================
# VERSION CONTROL & SECURITY
# ================================================================
section "Version Control & Security"
check_command "git-lfs"  "Git LFS"  "version"
check_command "ssh"      "SSH"      "-V"  'OpenSSH_([0-9]+\.[0-9]+p[0-9]+)'
check_command "gpg"      "GPG"      "--version"

# ================================================================
# BUILD & PACKAGE TOOLS
# ================================================================
section "Build & Package Tools"
check_command "gradle"  "Gradle"  "--version"
check_command "mvn"     "Maven"   "-v"

case "$OS" in
    windows)
        check_command "choco"   "Chocolatey"  "--version"
        check_command "winget"  "Winget"      "--version"
        ;;
    linux)
        check_command "snap"     "Snap"     "--version"
        check_command "flatpak"  "Flatpak"  "--version"
        ;;
esac

# ================================================================
# UTILITIES
# ================================================================
section "Utilities"
check_command "curl"     "Curl"              "--version"
check_command "wget"     "Wget"              "--version"
check_command "openssl"  "OpenSSL"           "version"
check_command "tar"      "Tar"               "--version"
check_command "jq"       "jq (JSON)"         "--version"

# ================================================================
# SUMMARY
# ================================================================
echo -e "\n${CYAN}=== SUMMARY ===${NC}"

for key in $(printf '%s\n' "${!results[@]}" | sort); do
    status="${results[$key]}"
    if [[ "$status" == "Missing" ]]; then
        echo -e "${RED}[X]${NC} $key"
    elif [[ "$status" == Warning* || "$status" == "Disabled" || "$status" == "Not detected" || "$status" == "Unknown" ]]; then
        echo -e "${YELLOW}[!]${NC} $key ($status)"
    else
        echo -e "${GREEN}[OK]${NC} $key ($status)"
    fi
done

echo -e "\n${CYAN}=== Check Completed ===${NC}"
case "$OS" in
    windows) echo -e "${YELLOW}Tip: Missing tools can be installed via Winget or Chocolatey.${NC}" ;;
    macos)   echo -e "${YELLOW}Tip: Missing tools can be installed via Homebrew (brew install).${NC}" ;;
    linux)   echo -e "${YELLOW}Tip: Missing tools can be installed via your distribution's package manager.${NC}" ;;
esac
echo ""
