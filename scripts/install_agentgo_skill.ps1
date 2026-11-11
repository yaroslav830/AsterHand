# Compatibility entry for previously copied installation commands.
param([string]$CodexDirectory = $(if ($env:CODEX_HOME) {$env:CODEX_HOME} else {Join-Path $env:USERPROFILE '.codex'}))
& (Join-Path $PSScriptRoot 'install_asterhand_skill.ps1') -CodexDirectory $CodexDirectory
