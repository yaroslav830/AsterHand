param([string]$CodexDirectory = $(if ($env:CODEX_HOME) {$env:CODEX_HOME} else {Join-Path $env:USERPROFILE '.codex'}))
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$source = Join-Path $project 'skills\asterhand-skill'
if (!(Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) {throw 'AsterHand skill source missing'}
foreach ($relative in @('shared\asterhand-client.mjs','shared\control-wire.mjs','cli\asterhand.mjs')) {
    if (!(Test-Path -LiteralPath (Join-Path $project $relative))) {throw ('AsterHand shared runtime missing: ' + $relative)}
}
$destination = Join-Path $CodexDirectory 'skills\asterhand-skill'
# Preserve an installed revision before a bounded update. Never copy pairing keys.
if (Test-Path -LiteralPath $destination) {
    $backup = Join-Path $CodexDirectory ('skill-backups\asterhand-skill-' + [Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    Copy-Item -LiteralPath $destination -Destination $backup -Recurse
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
$pointer = Join-Path $CodexDirectory 'asterhand.json'
if (Test-Path -LiteralPath $pointer) {Copy-Item -LiteralPath $pointer -Destination ($pointer + '.backup-' + [Guid]::NewGuid().ToString())}
$json = @{project=$project} | ConvertTo-Json
[IO.File]::WriteAllText($pointer,$json,(New-Object Text.UTF8Encoding($false)))
# Move former names out of discovery; preserve revisions outside skills.
foreach ($legacyName in @('asterhand-control', 'agentgo-control')) {
  $legacy = Join-Path $CodexDirectory ('skills\' + $legacyName)
  if (Test-Path -LiteralPath $legacy) {
    $resolvedCodex = (Resolve-Path -LiteralPath $CodexDirectory).Path
    $resolvedLegacy = (Resolve-Path -LiteralPath $legacy).Path
    $expectedLegacy = [IO.Path]::GetFullPath((Join-Path $resolvedCodex ('skills\' + $legacyName)))
    $legacyBackup = [IO.Path]::GetFullPath((Join-Path $resolvedCodex ('skill-backups\' + $legacyName + '-' + [Guid]::NewGuid().ToString())))
    if (![String]::Equals($resolvedLegacy,$expectedLegacy,[StringComparison]::OrdinalIgnoreCase) -or !$legacyBackup.StartsWith((Join-Path $resolvedCodex 'skill-backups\'),[StringComparison]::OrdinalIgnoreCase)) {throw 'Unexpected legacy skill path'}
    New-Item -ItemType Directory -Path (Split-Path -Parent $legacyBackup) -Force | Out-Null
    Move-Item -LiteralPath $resolvedLegacy -Destination $legacyBackup
  }
  # Old command paths remain forwarding scripts, without an old SKILL.md entry.
  $compatibility = Join-Path $project ('skills\' + $legacyName)
  if (Test-Path -LiteralPath $compatibility) {Copy-Item -LiteralPath $compatibility -Destination $legacy -Recurse}
}
Write-Output ('Installed: ' + $destination)
Write-Output 'Start a new Codex chat to load the MCP-first operating workflow. CLI launchers use the same project runtime; pairing keys remain in AsterHand.'
