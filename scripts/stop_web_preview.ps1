$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$serverScript = Join-Path $PSScriptRoot 'serve_web.mjs'
$stateFile = Join-Path $project 'output\web-preview\server.json'
if (!(Test-Path -LiteralPath $stateFile)) { exit 0 }
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$running = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.pid)"
if ($running -and $running.CommandLine.Contains($serverScript)) {
  Stop-Process -Id $state.pid
  Write-Output 'Stopped this project preview server.'
} elseif ($running) {
  throw 'The recorded process ID is now used by another process; nothing was stopped.'
} else {
  Write-Output 'Preview server is already stopped.'
}
