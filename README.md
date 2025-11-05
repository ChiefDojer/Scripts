# Scripts
Collection of maintenance and audit PowerShell scripts for Windows developer workstations.

## Included Scripts

- CheckWindowsEnv
	- `CheckWindowsEnv/WindowsEnvironmentCheck.ps1`  
		Full environment auditor that inspects platform features, core tools, runtimes, cloud/DevOps utilities, and more. Key helper function: `Check-Command`. See definition and rationale in `CheckWindowsEnv/ScriptDefinition.md`.
- FindGitHubAccounts
	- `FindGitHubAccounts/FindGitHubAccounts.ps1`  
		GitHub account auditor that inspects Git configs, Windows Credential Manager, VS Code sessions, Visual Studio registry, GitHub CLI state, and local repo remotes. Details in `FindGitHubAccounts/ScriptDefinition.md`.

## Quickstart

Run the scripts from a PowerShell prompt. Some checks require elevation for full results.

- Run environment checker:
```powershell
cd CheckWindowsEnv
powershell -ExecutionPolicy Bypass -File .\WindowsEnvironmentCheck.ps1
```

- Run GitHub account auditor:
```powershell
cd FindGitHubAccounts
powershell -ExecutionPolicy Bypass -File .\FindGitHubAccounts.ps1
```

Notes:
- Some checks (Windows optional features, registry reads) may require elevation for full results.
- Outputs are color-coded and a summary table is produced at the end of each script run.

## Contribution & Extensibility

- To add a tool check to the environment script, use the reusable function `Check-Command` in `CheckWindowsEnv/WindowsEnvironmentCheck.ps1`.
- The GitHub auditor can be extended by adding checks for other credential stores or IDEs in `FindGitHubAccounts/FindGitHubAccounts.ps1`.

## License

Repository contains community scripts. Verify licensing before production use.

## Files

- `CheckWindowsEnv/WindowsEnvironmentCheck.ps1` — environment auditor
- `CheckWindowsEnv/ScriptDefinition.md` — script design notes
- `FindGitHubAccounts/FindGitHubAccounts.ps1` — GitHub account auditor
- `FindGitHubAccounts/ScriptDefinition.md` — script design notes
