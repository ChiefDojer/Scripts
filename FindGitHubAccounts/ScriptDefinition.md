# FindGitHubAccounts.ps1 - GitHub Account Auditor for Windows

`FindGitHubAccounts.ps1` is a PowerShell script designed to perform a comprehensive audit of a Windows machine to detect and report all traces of configured or cached GitHub user identities and credentials.

This tool is useful for security auditing, consolidating development environments, or ensuring no unintended user accounts are linked to sensitive repositories.

## Execution

The script is executed directly from PowerShell:

```powershell
PS> .\FindGitHubAccounts.ps1
```

## Audit Locations (Six Key Checks)

The script systematically checks six distinct locations where GitHub identity and credential information is stored by common development tools:

### 1\. Git Configuration (System, Global, Local)

This checks the `user.name` and `user.email` settings at all three precedence levels defined by the Git application.

  * **System:** Applies to all users on the machine (e.g., `C:\Program Files\Git\etc\gitconfig`).
  * **Global:** Applies to the current user (e.g., `%UserProfile%\.gitconfig`).
  * **Local:** Applies only to specific repository roots (highest priority).

### 2\. Windows Credential Manager

Checks for encrypted access tokens and passwords stored by Git, VS Code, and other applications that use HTTPS for communication with `github.com`.

### 3\. VS Code Authentication Sessions

Checks for the presence of session database files (`state.vscdb`) for **Visual Studio Code** and **VS Code Insider**. These files contain tokens used by extensions (e.g., GitHub Pull Requests). A manual step is provided to view the accounts directly in the VS Code UI.

### 4\. Visual Studio Connected Accounts

Queries the Windows Registry (`HKCU:\Software\Microsoft\VSCommon\ConnectedUser`) where the full **Visual Studio IDE** stores connected user accounts used for licensing and integrated services.

### 5\. GitHub CLI (gh) Accounts

Checks if the `gh` command-line utility is installed and, if so, runs `gh auth status` to report all logged-in users and hosts.

### 6\. Local Repository Remotes

Scans the user's profile (`%UserProfile%`) for Git repositories and extracts the `origin` remote URL to confirm the existence of local repositories pointing to `github.com`.

## Summary of Findings

The script concludes with a consolidated summary, listing unique identities (emails and usernames) found across all checks, providing a clear overview of the detected GitHub presence on the system.