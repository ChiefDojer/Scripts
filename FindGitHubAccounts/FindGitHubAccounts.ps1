<#
    ===============================================================
    FindGitHubAccounts.ps1
    Purpose: Detect all GitHub accounts configured or cached
             on this Windows machine (global, repo, VS Code, CLI, VS)
    ===============================================================
#>

# Global settings for better error handling and output
$ErrorActionPreference = 'Continue' # Keep default for most cases but handle errors locally
$PSDefaultParameterValues = @{
    'Select-String:CaseSensitive' = $false # Default Select-String to be case-insensitive
}

# --- SUMMARY COUNTERS & ACCOUNT ARRAYS ---
$systemGitCount = 0 # New counter for system config
$globalGitCount = 0
$localIdentityCount = 0
$credEntryCount = 0
$vsCodeSessionCount = 0
$vsAccountCount = 0
$ghCliAccountCount = 0
$githubRemoteCount = 0
$detectedGitIdentities = @() # Stores unique Git user.name/user.email
$detectedCredNames = @()     # Stores unique Credential Manager Targets
$detectedGhAccounts = @()    # Stores unique GitHub CLI usernames
# -----------------------------------------

Write-Host ""
Write-Host "[i] Checking all GitHub identities on this machine..." -ForegroundColor Cyan

# --- 1️⃣ Git configuration (system + global + local)
Write-Host "`n=== [ 1. GIT CONFIGURATION (System, Global, Local) ] ===" -ForegroundColor Yellow
$gitFound = $false
try {
    # Check if 'git' command is available first
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git command not found. Is Git installed and in PATH?"
    }

    # 1.a System Git configuration (Lowest Priority, applies to all users)
    Write-Host "`n--- System Configuration ---" -ForegroundColor DarkGray
    
    # --- FIX 1: Safely retrieve name/email to prevent .Trim() on $null ---
    $systemNameRaw = git config --system user.name 2>$null
    $systemName = if ($systemNameRaw) { $systemNameRaw.Trim() } else { "" }
    
    $systemEmailRaw = git config --system user.email 2>$null
    $systemEmail = if ($systemEmailRaw) { $systemEmailRaw.Trim() } else { "" }
    # ----------------------------------------------------------------------
    
    # Safely retrieve config path to avoid 'null-valued expression' error
    $systemConfigRaw = git config --system --show-origin 2>$null
    $systemConfigPath = $null
    if ($systemConfigRaw) {
        # Only process if output exists
        $systemConfigPath = $systemConfigRaw.Trim() -split "`n" | Select-Object -First 1 -replace 'file:', ''
    }

    Write-Host "Config Path: $($systemConfigPath -replace '\r?\n', ' (Default: C:\Program Files\Git\etc\gitconfig)')"

    if ($systemName -or $systemEmail) {
        Write-Host "System Git user.name : $($systemName -replace '\r?\n', '')"
        Write-Host "System Git user.email: $($systemEmail -replace '\r?\n', '')"
        $gitFound = $true
        $systemGitCount = 1

        # Capture identities
        if ($systemName) { $detectedGitIdentities += $systemName }
        if ($systemEmail) { $detectedGitIdentities += $systemEmail }
    } else {
        Write-Host "No system Git identity found."
    }

    # 1.b Global Git configuration (Applies to current user)
    Write-Host "`n--- Global Configuration ---" -ForegroundColor DarkGray
    
    # --- FIX 2: Safely retrieve name/email to prevent .Trim() on $null ---
    $globalNameRaw = git config --global user.name 2>$null
    $globalName = if ($globalNameRaw) { $globalNameRaw.Trim() } else { "" }
    
    $globalEmailRaw = git config --global user.email 2>$null
    $globalEmail = if ($globalEmailRaw) { $globalEmailRaw.Trim() } else { "" }
    # ----------------------------------------------------------------------
    
    # Safely retrieve config path to avoid 'null-valued expression' error
    $globalConfigRaw = git config --global --show-origin 2>$null
    $globalConfigPath = $null
    if ($globalConfigRaw) {
        # Only process if output exists
        $globalConfigPath = $globalConfigRaw.Trim() -split "`n" | Select-Object -First 1 -replace 'file:', ''
    }

    Write-Host "Config Path: $($globalConfigPath -replace '\r?\n', ' (Default: %UserProfile%\.gitconfig)')"

    if ($globalName -or $globalEmail) {
        # Remove potential newlines from git output
        Write-Host "Global Git user.name : $($globalName -replace '\r?\n', '')"
        Write-Host "Global Git user.email: $($globalEmail -replace '\r?\n', '')"
        $gitFound = $true
        $globalGitCount = 1 # Increment counter for summary

        # Capture identities
        if ($globalName) { $detectedGitIdentities += $globalName }
        if ($globalEmail) { $detectedGitIdentities += $globalEmail }
    } else {
        Write-Host "No global Git identity found."
    }

    # 1.c Local Repository configurations (Highest Priority)
    Write-Host "`n--- Local Repository Scan ---" -ForegroundColor DarkGray

    # Start search from user profile for efficiency
    $searchPath = $env:USERPROFILE

    Write-Host "`nScanning local repositories in: $searchPath (may take a moment)..."

    # Use -Filter ".git" with Get-ChildItem -Recurse to drastically speed up the search
    Get-ChildItem -Path $searchPath -Recurse -Directory -Filter ".git" -ErrorAction SilentlyContinue | ForEach-Object {
        $configPath = Join-Path -Path $_.FullName -ChildPath "config"
        if (Test-Path $configPath) {
            try {
                # Navigate up one level from the .git directory to the repository root
                $repoRoot = Join-Path -Path $_.FullName -ChildPath ".."
                $localName  = (git -C $repoRoot config user.name 2>$null).Trim()
                $localEmail = (git -C $repoRoot config user.email 2>$null).Trim()

                if ($localName -or $localEmail) {
                    Write-Host "`nRepo: ${repoRoot}"
                    Write-Host "  user.name : $($localName -replace '\r?\n', '')"
                    Write-Host "  user.email: $($localEmail -replace '\r?\n', '')"
                    $gitFound = $true
                    $localIdentityCount++ # Increment counter

                    # Capture identities
                    if ($localName) { $detectedGitIdentities += $localName }
                    if ($localEmail) { $detectedGitIdentities += $localEmail }
                }
            } catch {
                Write-Warning "[!] Unable to read local Git config in ${repoRoot}: $($_.Exception.Message)"
            }
        }
    }

    if ($localIdentityCount -eq 0) {
        Write-Host "No local repository identities with custom config found."
    }

} catch {
    Write-Warning "[!] Unable to check Git configuration: $($_.Exception.Message)"
}

# --- 2️⃣ Windows Credential Manager
Write-Host "`n=== [ 2. WINDOWS CREDENTIAL MANAGER ] ===" -ForegroundColor Yellow
try {
    # Filter for both 'github' and the common 'git:https://github.com' pattern
    $creds = cmdkey /list | Select-String -Pattern "github|git:https://github.com"
    if ($creds) {
        Write-Host "GitHub-related credentials found:"
        $creds | ForEach-Object {
            $line = $_.ToString().Trim()
            if ($line) {
                Write-Host "* $line"
                $credEntryCount++ # Increment counter for each entry found

                # Extract the target name/key for the summary list
                if ($line -match 'Target:\s*(.+)') {
                    $detectedCredNames += $matches[1].Trim()
                }
            }
        }
    } else {
        Write-Host "No GitHub credentials found in Windows Credential Manager."
    }
} catch {
    Write-Warning "[!] Unable to query Credential Manager."
}

# --- 3️⃣ VS Code and VS Code Insider Sessions
Write-Host "`n=== [ 3. VS CODE AUTHENTICATION SESSIONS ] ===" -ForegroundColor Yellow

$vsCodePaths = @(
    @{ Name = "VS Code (Standard)"; Path = Join-Path -Path $env:APPDATA -ChildPath "Code\User\globalStorage\state.vscdb" },
    @{ Name = "VS Code (Insider)"; Path = Join-Path -Path $env:APPDATA -ChildPath "Code - Insiders\User\globalStorage\state.vscdb" }
)

foreach ($item in $vsCodePaths) {
    if (Test-Path $item.Path) {
        Write-Host "$($item.Name) session database found at: $($item.Path)"
        Write-Host "[>] **Manual Step:** Open $($item.Name) -> Run command 'Developer: Show Authentication Sessions' to see active GitHub logins."
        $vsCodeSessionCount++
    }
}

if ($vsCodeSessionCount -eq 0) {
    Write-Host "VS Code session databases not found."
}

# --- 4️⃣ Visual Studio Connected Accounts (Registry Check)
Write-Host "`n=== [ 4. VISUAL STUDIO CONNECTED ACCOUNTS ] ===" -ForegroundColor Yellow
$vsRegistryPath = "HKCU:\Software\Microsoft\VSCommon\ConnectedUser"

if (Test-Path $vsRegistryPath) {
    # Get all properties from all subkeys under ConnectedUser
    $vsUserKeys = Get-ChildItem -Path $vsRegistryPath -ErrorAction SilentlyContinue

    if ($vsUserKeys.Count -gt 0) {
        Write-Host "Accounts found in Visual Studio Registry:"
        
        $vsUserKeys | ForEach-Object {
            $properties = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue

            # Attempt to find the value of any property containing 'Email' or 'Account' in its name
            $emailProperty = $properties.PSObject.Properties |
                             Where-Object { $_.Name -like "*Email*" -or $_.Name -like "*Account*" } |
                             Select-Object -First 1
            
            $email = $null
            if ($emailProperty) {
                $email = $emailProperty.Value
            }

            # --- NEW FILTER: Check if the value is an empty string, null, or a numeric-only string. ---
            if ($email -and ($email -ne "") -and ($email -is [string]) -and (-not ($email -match '^\d+$')) ) {
                $vsAccountCount++
                
                # Check if it looks like a GitHub-related account
                if ($email -like "*@github.com" -or $email -like "*@users.noreply.github.com") {
                    Write-Host "* Detected GitHub Linked Account (Email): $email"
                } elseif ($email -like "*@live.com" -or $email -like "*@outlook.com") {
                    Write-Host "* Detected Microsoft Account (Potential GitHub Link): $email"
                } else {
                    Write-Host "* Detected General Account (Email): $email"
                }
                
                $detectedGitIdentities += $email # Add to the master list of identities
            }
        }
    }
}

if ($vsAccountCount -eq 0) {
    Write-Host "No connected accounts found in the Visual Studio Common Registry path."
}

# --- 5️⃣ GitHub CLI (gh)
Write-Host "`n=== [ 5. GITHUB CLI ACCOUNTS ] ===" -ForegroundColor Yellow
try {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        # Use 'gh auth status' as it provides a clearer output of logged-in users/hosts
        $ghStatus = gh auth status 2>$null

        if ($ghStatus -match 'Logged in to github.com as ') {
             Write-Host "GitHub CLI Accounts (gh auth status):"
             # Filter the status output to show only relevant logged-in lines
             $ghStatus -split "`n" | Select-String -Pattern "Logged in to" | ForEach-Object {
                 Write-Host "* $_"
                 $ghCliAccountCount++ # Increment counter for each logged-in host/account

                 # Extract the username
                 if ($_ -match 'as\s+([^\s]+)\s+\(') {
                     $detectedGhAccounts += $matches[1].Trim()
                 }
             }
        } else {
            Write-Host "No GitHub CLI accounts found or you are logged out."
        }
    } else {
        Write-Host "GitHub CLI (gh) not installed or not in PATH."
    }
} catch {
    Write-Warning "[!] Unable to query GitHub CLI."
}

# --- 6️⃣ Local repository remotes
Write-Host "`n=== [ 6. LOCAL REPOSITORY REMOTES ] ===" -ForegroundColor Yellow
$searchPath = $env:USERPROFILE
Write-Host "Scanning local repositories for 'origin' remote URLs in: $searchPath..."

Get-ChildItem -Path $searchPath -Recurse -Directory -Filter ".git" -ErrorAction SilentlyContinue | ForEach-Object {
    $configPath = Join-Path -Path $_.FullName -ChildPath "config"
    if (Test-Path $configPath) {
        try {
            $repoRoot = Join-Path -Path $_.FullName -ChildPath ".."
            $remoteUrl = (git -C $repoRoot remote get-url origin 2>$null).Trim()

            # Check for standard GitHub remote patterns (https, ssh)
            if ($remoteUrl -and ($remoteUrl -like "*github.com*")) {
                Write-Host "`nRepo: ${repoRoot}"
                Write-Host "  Remote (origin): $remoteUrl"
                $githubRemoteCount++ # Increment counter for GitHub remotes
            }
        } catch {
            Write-Warning "[!] Unable to check remote URL for ${repoRoot}: $($_.Exception.Message)"
        }
    }
}

# --- 7️⃣ SUMMARY ---
Write-Host "`n=== [ 7. SUMMARY OF FINDINGS ] ===" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------"

# Process lists to get unique, sorted results
$uniqueGit = $detectedGitIdentities | Sort-Object -Unique | Where-Object { $_ -ne $null -and $_ -ne "" }
$uniqueCred = $detectedCredNames | Sort-Object -Unique | Where-Object { $_ -ne $null -and $_ -ne "" }
$uniqueGh = $detectedGhAccounts | Sort-Object -Unique | Where-Object { $_ -ne $null -and $_ -ne "" }

# Display Git Identities
Write-Host "Git System Identity Found: $($systemGitCount)"
Write-Host "Git Global Identity Found: $($globalGitCount)"
Write-Host "Local Repository Identities Found: $($localIdentityCount)"
Write-Host "Visual Studio Accounts Found: $($vsAccountCount)"
Write-Host "--- Git/VS Identities (Usernames/Emails) ---"
if ($uniqueGit.Count -gt 0) {
    $uniqueGit | ForEach-Object { Write-Host "* $_" }
} else {
    Write-Host " (None detected)"
}
Write-Host ""

# Display VS Code Sessions
Write-Host "VS Code / Insider Session Files Found: $($vsCodeSessionCount)"
if ($vsCodeSessionCount -gt 0) {
    Write-Host " (See manual steps in section 3 above)"
}
Write-Host ""

# Display Credential Manager Targets
Write-Host "Credential Manager Entries (GitHub): $($credEntryCount)"
Write-Host "--- Credential Manager Targets ---"
if ($uniqueCred.Count -gt 0) {
    $uniqueCred | ForEach-Object { Write-Host "* $_" }
} else {
    Write-Host " (None detected)"
}
Write-Host ""

# Display GitHub CLI Accounts
Write-Host "GitHub CLI Accounts Logged In: $($ghCliAccountCount)"
Write-Host "--- GitHub CLI Usernames ---"
if ($uniqueGh.Count -gt 0) {
    $uniqueGh | ForEach-Object { Write-Host "* $_" }
} else {
    Write-Host " (None detected)"
}
Write-Host ""

Write-Host "Local Repositories with GitHub Remote: $($githubRemoteCount)"
Write-Host "--------------------------------------------------------"

Write-Host ""
Write-Host "[OK] Scan complete. Review results above." -ForegroundColor Green
Write-Host "Run this script to see all GitHub identities present on this system." -ForegroundColor Cyan