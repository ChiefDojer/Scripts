# ================================================================
# 🧠 ULTIMATE WINDOWS DEVELOPER ENVIRONMENT CHECKER (v3.2)
# ================================================================
# Enhancement: Custom parsing logic added for 'pip' to display a clean format 
#              showing both Pip and Python versions (e.g., pip 25.2, Python 3.13).
# ================================================================

# --- INITIALIZATION ---
# --- TITLE FIX: Save the original console title ---
$originalTitle = $Host.UI.RawUI.WindowTitle
Write-Host "`n=== ULTIMATE DEV ENVIRONMENT CHECK START (v3.2) ===`n" -ForegroundColor Cyan
$results = @{}

# Refactored function to be more robust, clean multi-line output,
# and store the actual version string instead of just "Installed".
function Check-Command {
    param(
        [string]$cmd,
        [string]$name,
        [string]$arg = "--version",
        [string]$Parser = "" # Optional Regex pattern to extract a specific part
    )
    try {
        # 1. Capture output, forcing errors to stay in the output stream (2>&1)
        # Note: Some tools like psql print version to stderr, so 2>&1 is crucial.
        $output = & $cmd $arg 2>&1

        # 2. Check for success (Exit code 0 and non-empty output)
        if ($LASTEXITCODE -eq 0 -and $output) {
            # 3. Clean up the version string: take the first line and trim whitespace
            $versionString = ($output -split '\r?\n' | Select-Object -First 1).Trim()

            # Fallback for multi-line outputs (like 'ng version'): try to find a version number
            if ($versionString.Length -gt 100) {
                 # Look for a standard version pattern (e.g., X.Y.Z)
                 $foundVersion = $output | Select-String -Pattern '\d+\.\d+\.\d+' | Select-Object -First 1 | ForEach-Object {$_.Matches.Value}
                 if ($foundVersion) {
                    $versionString = $foundVersion.Trim()
                 }
            }
            
            # 4. Optional parsing using regex (if $Parser is provided)
            if ($Parser -ne "" -and $versionString -match $Parser) {
                # Use the first captured group
                $versionString = $Matches[1]
            }
            
            # Final check for empty string
            if ($versionString -eq "") { $versionString = "Found" }

            Write-Host "[OK] $name found:" -ForegroundColor Green
            Write-Host "     Version: $versionString`n"
            $results[$name] = $versionString # Store the actual version
        }
        else { throw "Command failed or returned empty output." }
    } catch {
        # Catch errors like command not found or execution failure
        Write-Host "[X] $name not found or failed execution. Details: $($_.Exception.Message | Select-Object -First 1)`n" -ForegroundColor Red
        $results[$name] = "Missing"
    }
}

# ---------------------------------------------------------------
# 🌟 MAIN SCRIPT EXECUTION (Wrapped in Try/Catch/Finally)
# ---------------------------------------------------------------
try {

# ---------------------------------------------------------------
# 💻 WINDOWS PLATFORM FEATURES
# ---------------------------------------------------------------
Write-Host "--- Checking Windows Platform Features ---" -ForegroundColor Yellow

# Check for WSL (Windows Subsystem for Linux)
try {
    # Check status and look for a default distribution indicator
    $wslStatus = & wsl --status 2>&1 | Select-String "Default Distribution"
    if ($wslStatus) {
        Write-Host "[OK] WSL found and initialized." -ForegroundColor Green
        $results["WSL Status"] = "Active"
    } else {
        throw "WSL not running or no default distribution set"
    }
} catch {
    Write-Host "[X] WSL not found or not initialized.`n" -ForegroundColor Red
    $results["WSL Status"] = "Missing"
}

# Check for Hyper-V or Virtual Machine Platform (needed by Docker Desktop)
try {
    # Get-WindowsOptionalFeature requires admin, suppress errors if not running as admin
    $hyperV = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction SilentlyContinue
    $vmPlatform = Get-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform' -ErrorAction SilentlyContinue

    if (($hyperV -ne $null -and $hyperV.State -eq 'Enabled') -or ($vmPlatform -ne $null -and $vmPlatform.State -eq 'Enabled')) {
        Write-Host "[OK] Virtualization platform (Hyper-V/VMP) enabled.`n" -ForegroundColor Green
        $results["Virtualization"] = "Enabled"
    } else {
        Write-Host "[!] Virtualization platform (Hyper-V/VMP) NOT enabled. Docker may fail.`n" -ForegroundColor Red
        $results["Virtualization"] = "Warning: Disabled"
    }
} catch {
    Write-Host "[!] Could not check Virtualization status (requires elevated rights).`n" -ForegroundColor Yellow
    $results["Virtualization"] = "Warning: Check manually"
}

# ---------------------------------------------------------------
# 🧩 CORE SYSTEM TOOLS
# ---------------------------------------------------------------
Write-Host "--- Checking Core Tools ---" -ForegroundColor Yellow
$psVer = $PSVersionTable.PSVersion.ToString()
Write-Host "[OK] PowerShell version: $psVer`n" -ForegroundColor Green
$results["PowerShell"] = $psVer 
Check-Command "git" "Git" "--version"
Check-Command "code" "Visual Studio Code" "--version"

# DEDICATED CHECK: 7-Zip (7z.exe) - Robust search for non-PATH install and tolerant of non-zero exit codes.
try {
    $sevenZipPath = $null

    # 1. Try finding it in PATH first (quickest)
    $commandInfo = Get-Command "7z" -ErrorAction SilentlyContinue
    if ($commandInfo) {
        $sevenZipPath = $commandInfo.Definition
    }
    
    # 2. If not in PATH, search registry keys for installation path
    if (!$sevenZipPath) {
        Write-Host "[!] 7z.exe not found in PATH. Searching registry..." -ForegroundColor Yellow
        # Common 32-bit and 64-bit keys for 7-Zip
        $regPaths = @(
            'HKLM:\SOFTWARE\7-Zip',
            'HKLM:\SOFTWARE\WOW6432Node\7-Zip'
        )
        foreach ($regPath in $regPaths) {
            $installDir = Get-ItemProperty -Path $regPath -Name 'Path' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
            if ($installDir) {
                $sevenZipPath = Join-Path $installDir "7z.exe"
                break
            }
        }
    }
    
    if ($sevenZipPath -and (Test-Path $sevenZipPath)) {
        # Execute 7z using the full path, which prints output but usually returns non-zero.
        $output = & $sevenZipPath 2>&1
        if ($output) {
            # Extract the line containing "7-Zip" and expand its string content, then trim.
            $versionString = ($output | Select-String "7-Zip" | Select-Object -First 1 | Select-Object -ExpandProperty Line).Trim()
            
            if ($versionString -match '(\d+\.\d+)') {
                $displayVersion = $Matches[1]
                Write-Host "[OK] 7-Zip found:" -ForegroundColor Green
                Write-Host "     Path: $sevenZipPath"
                Write-Host "     Version: $displayVersion`n"
                $results["7-Zip"] = $displayVersion
            } else {
                Write-Host "[OK] 7-Zip found (version details unavailable).`n" -ForegroundColor Green
                $results["7-Zip"] = "Found (Version check complicated)"
            }
        } else { throw "7z executed but returned no output." }
    } else { throw "7z command not found in PATH and not found via registry search." }
} catch {
    Write-Host "[X] 7-Zip not found or failed execution. Details: $($_.Exception.Message | Select-Object -First 1)`n" -ForegroundColor Red
    $results["7-Zip"] = "Missing"
}


Check-Command "cmake" "CMake" "--version"
Check-Command "make" "Make" "--version"

# ---------------------------------------------------------------
# 🐍 PYTHON ECOSYSTEM
# ---------------------------------------------------------------
Write-Host "--- Checking Python Ecosystem ---" -ForegroundColor Yellow
Check-Command "python" "Python" "--version"

# DEDICATED CHECK: pip (with custom formatting to show Pip and Python versions)
try {
    $cmd = "pip"
    $name = "pip"
    # Execute pip --version
    $output = & $cmd "--version" 2>&1
    
    if ($LASTEXITCODE -eq 0 -and $output) {
        $versionString = ($output -split '\r?\n' | Select-Object -First 1).Trim()

        # Regex to capture pip version (1) and Python version (2)
        # Example output: pip 25.2 from C:\... (python 3.13)
        $parser = 'pip (\d+\.\d+).*\(python (\d+\.\d+)\)'

        if ($versionString -match $parser) {
            $pipVersion = $Matches[1]
            $pyVersion = $Matches[2]
            
            # Format the output as requested: "pip X.Y, Python Z.A"
            $displayVersion = "pip $pipVersion, Python $pyVersion"
            
            Write-Host "[OK] $name found:" -ForegroundColor Green
            Write-Host "     Version: $displayVersion`n"
            $results[$name] = $displayVersion 
        } else {
            # Fallback if the regex pattern doesn't match (use the raw output)
            $results[$name] = $versionString 
            Write-Host "[OK] $name found (raw output used):" -ForegroundColor Green
            Write-Host "     Version: $versionString`n"
        }
    } else { throw "Command failed or returned empty output." }
} catch {
    Write-Host "[X] pip not found or failed execution. Details: $($_.Exception.Message | Select-Object -First 1)`n" -ForegroundColor Red
    $results["pip"] = "Missing"
}


Check-Command "pipx" "pipx" "--version"
Check-Command "poetry" "Poetry" "--version"
Check-Command "pipenv" "Pipenv" "--version"
try {
    $venvTest = python -m venv testenv 2>$null
    if (Test-Path "./testenv") {
        Remove-Item -Recurse -Force "./testenv" | Out-Null
        Write-Host "[OK] Python venv module working`n" -ForegroundColor Green
        $results["Python venv"] = "Working"
    }
    else { throw "venv test failed" }
} catch { 
    Write-Host "[X] Python venv module failed to create environment.`n" -ForegroundColor Red
    $results["Python venv"] = "Missing" 
}

# ---------------------------------------------------------------
# ⚙️ PROGRAMMING RUNTIMES
# ---------------------------------------------------------------
Write-Host "--- Checking Programming Runtimes ---" -ForegroundColor Yellow
Check-Command "java" "Java Runtime Environment (JRE)" "-version"
Check-Command "javac" "Java Development Kit (JDK)" "-version"
Check-Command "go" "Go (Golang)" "version"

# ---------------------------------------------------------------
# 🧠 AI / DATA TOOLS
# ---------------------------------------------------------------
Write-Host "--- Checking AI/Data Tools ---" -ForegroundColor Yellow
Check-Command "conda" "Anaconda/Miniconda" "--version"
Check-Command "jupyter" "Jupyter" "--version"
Check-Command "nvidia-smi" "NVIDIA GPU Driver" ""

# ---------------------------------------------------------------
# 🌐 APPLICATION SERVERS & WEB HOSTING
# ---------------------------------------------------------------
Write-Host "--- Checking Application Servers & Web Hosting ---" -ForegroundColor Yellow

# Check for Apache HTTPD
Check-Command "httpd" "Apache HTTP Server" "-v" 

# Check for Nginx
Check-Command "nginx" "Nginx" "-v" 

# Check for IIS (as a Windows Feature)
try {
    # Check for IIS-WebServerRole
    $iisFeature = Get-WindowsOptionalFeature -Online -FeatureName 'IIS-WebServerRole' -ErrorAction SilentlyContinue
    if ($iisFeature -ne $null -and $iisFeature.State -eq 'Enabled') {
        Write-Host "[OK] IIS Web Server Feature is enabled." -ForegroundColor Green
        $results["IIS Web Server"] = "Enabled"
    } else {
        Write-Host "[!] IIS Web Server Feature is NOT enabled." -ForegroundColor Yellow
        $results["IIS Web Server"] = "Disabled"
    }
} catch {
    Write-Host "[!] Could not check IIS status (requires elevated rights or feature not found)." -ForegroundColor Yellow
    $results["IIS Web Server"] = "Warning: Check manually"
}
Write-Host "`n" # Add a newline to separate this section from the next

# ---------------------------------------------------------------
# ⚙️ WEB / FRONTEND DEVELOPMENT
# ---------------------------------------------------------------
Write-Host "--- Checking Web/Frontend Tools ---" -ForegroundColor Yellow
Check-Command "node" "Node.js" "-v"
Check-Command "npm" "npm" "-v"
Check-Command "pnpm" "pnpm" "-v"
Check-Command "yarn" "yarn" "-v"
Check-Command "ng" "Angular CLI" "version"
Check-Command "vue" "Vue CLI" "--version"
Check-Command "tsc" "TypeScript Compiler" "--version" # Explicit TypeScript check

# ---------------------------------------------------------------
# 🧱 DEVOPS & CLOUD
# ---------------------------------------------------------------
Write-Host "--- Checking DevOps & Cloud Tools ---" -ForegroundColor Yellow
Check-Command "docker" "Docker" "--version"
# Custom check for modern (plugin) vs. legacy (standalone) Docker Compose
try {
    # Try modern Docker Compose plugin (docker compose)
    $compose = & docker compose version 2>$null
    if ($LASTEXITCODE -eq 0 -and $compose) {
        $composeVersion = ($compose -split '\r?\n' | Select-Object -First 1).Trim()
        Write-Host "[OK] Docker Compose (plugin) found:" -ForegroundColor Green
        $results["Docker Compose"] = $composeVersion
        Write-Host "     Version: $composeVersion`n"
    } else { 
        # Fall back to legacy Docker Compose (docker-compose)
        Check-Command "docker-compose" "Docker Compose (standalone)" "--version" 
    }
} catch { 
    Write-Host "[X] Docker Compose not found (plugin or standalone).`n" -ForegroundColor Red
    $results["Docker Compose"] = "Missing" 
}

Check-Command "kubectl" "Kubernetes CLI (kubectl)" "version --client --short"
Check-Command "helm" "Helm" "version"
Check-Command "terraform" "Terraform" "version"
Check-Command "az" "Azure CLI" "--version"
Check-Command "aws" "AWS CLI" "--version"
Check-Command "gcloud" "Google Cloud CLI" "version"

# ---------------------------------------------------------------
# 💻 MICROSOFT STACK
# ---------------------------------------------------------------
Write-Host "--- Checking Microsoft Stack ---" -ForegroundColor Yellow
Check-Command "dotnet" ".NET SDK" "--version"
Check-Command "msbuild" "MSBuild" "-version"

# DEDICATED CHECK: Visual Studio (devenv.exe)
# devenv.exe is typically NOT in the system PATH, so we must search for it.
try {
    Write-Host "[!] Checking for Visual Studio (devenv.exe). Searching common installation locations..." -ForegroundColor Yellow
    $vsRoot = "C:\Program Files\Microsoft Visual Studio"
    
    if (Test-Path $vsRoot) {
        # Recursively look for devenv.exe in all VS versions (2019, 2022, etc.)
        # We search for the *latest* version first by sorting by last write time (though Get-ChildItem default sort is often adequate)
        $devenvPathItem = Get-ChildItem -Path $vsRoot -Filter 'devenv.exe' -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($devenvPathItem) {
            $fullPath = $devenvPathItem.FullName
            
            # --- FIX: Read version from file metadata instead of executing the command ---
            $versionInfo = Get-Item $fullPath | Select-Object -ExpandProperty VersionInfo
            
            # Use the ProductVersion and ProductMajorPart properties for a clean version string
            $versionString = "$($versionInfo.ProductMajorPart).$($versionInfo.ProductMinorPart) (Build $($versionInfo.ProductBuildPart))"
            $productName = $versionInfo.ProductName.Split('(')[0].Trim() # Get "Microsoft Visual Studio"

            if ($versionInfo) {
                Write-Host "[OK] $productName found via search:" -ForegroundColor Green
                Write-Host "     Path: $fullPath"
                Write-Host "     Status: $versionString`n"
                $results["Visual Studio (Full)"] = "$productName $versionString"
            } else {
                Write-Host "[!] Visual Studio (Full) found, but version details could not be extracted.`n" -ForegroundColor Yellow
                $results["Visual Studio (Full)"] = "Found (Version unknown)"
            }
        } else {
            Write-Host "[X] Visual Studio (Full) not found in common locations (`$vsRoot)." -ForegroundColor Red
            $results["Visual Studio (Full)"] = "Missing"
        }
    } else {
        Write-Host "[X] Visual Studio (Full) installation root not found ($vsRoot).`n" -ForegroundColor Red
        $results["Visual Studio (Full)"] = "Missing"
    }
} catch {
    Write-Host "[X] Visual Studio (Full) check failed due to unexpected error. Details: $($_.Exception.Message | Select-Object -First 1)`n" -ForegroundColor Red
    $results["Visual Studio (Full)"] = "Missing"
}

Check-Command "nuget" "NuGet" ""

# ---------------------------------------------------------------
# 🧰 DATABASES
# ---------------------------------------------------------------
Write-Host "--- Checking Database Tools ---" -ForegroundColor Yellow
Check-Command "psql" "PostgreSQL (psql)" "--version"
Check-Command "mysql" "MySQL Client" "--version"
Check-Command "mongosh" "MongoDB Shell" "--version"
Check-Command "sqlite3" "SQLite" "--version"

# ---------------------------------------------------------------
# 🔐 VERSION CONTROL & COLLAB
# ---------------------------------------------------------------
Write-Host "--- Checking Version Control ---" -ForegroundColor Yellow
Check-Command "git" "Git" "--version"
Check-Command "git-lfs" "Git LFS" "version"
# ENHANCEMENT: Use -V and a regex parser to cleanly extract the OpenSSH version (e.g., 9.2p1)
Check-Command "ssh" "SSH" "-V" "OpenSSH_(\d+\.\d+p\d+)" 
Check-Command "gpg" "GPG" "--version"

# ---------------------------------------------------------------
# ⚙️ BUILD & PACKAGE MANAGERS
# ---------------------------------------------------------------
Write-Host "--- Checking Build & Package Tools ---" -ForegroundColor Yellow
Check-Command "gradle" "Gradle" "--version"
Check-Command "mvn" "Maven" "-v"
Check-Command "choco" "Chocolatey" "--version"
Check-Command "winget" "Winget" "--version"

# ---------------------------------------------------------------
# 🧩 UTILITIES
# ---------------------------------------------------------------
Write-Host "--- Checking Utilities ---" -ForegroundColor Yellow
Check-Command "curl.exe" "Curl" "--version" # FIX: Use curl.exe to bypass the PowerShell alias
Check-Command "wget" "Wget" "--version"
Check-Command "openssl" "OpenSSL" "version"
Check-Command "tar" "Tar" "--version"

# ---------------------------------------------------------------
# ✅ SUMMARY TABLE
# ---------------------------------------------------------------
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
# The summary now displays the actual version number or status (Missing/Warning)
foreach ($key in $results.Keys | Sort-Object) {
    $status = $results[$key]
    if ($status -eq "Missing") {
        Write-Host ("[X] $key") -ForegroundColor Red
    } elseif ($status -like "Warning*") {
        Write-Host ("[!] $key ($status)") -ForegroundColor Yellow
    } else {
        # Display the captured version/status
        Write-Host ("[OK] $key ($status)") -ForegroundColor Green
    }
}

Write-Host "`n=== Check Completed ===" -ForegroundColor Cyan
Write-Host "Tip: Missing tools can be installed via Winget or Chocolatey.`n" -ForegroundColor Yellow

} catch {
    # This catches any fatal, unhandled errors in the main script body
    Write-Host "`n[FATAL ERROR] The script encountered an unexpected terminal error. The console title will still be restored.`n" -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.Message | Select-Object -First 1)" -ForegroundColor Red
}
finally {
    # --- TITLE FIX: Restore the original console title ---
    $Host.UI.RawUI.WindowTitle = $originalTitle
}
