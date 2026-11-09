param([int]$Port = 0)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$build = Join-Path $project 'build\web'
if (!(Test-Path -LiteralPath (Join-Path $build 'index.html'))) {
  throw 'Run flutter build web --release first.'
}
$serverScript = Join-Path $PSScriptRoot 'serve_web.mjs'
$stateDirectory = Join-Path $project 'output\web-preview'
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$stateFile = Join-Path $stateDirectory 'server.json'
if (Test-Path -LiteralPath $stateFile) {
  try {
    $prior = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    $running = Get-CimInstance Win32_Process -Filter "ProcessId = $($prior.pid)"
    if ($running -and $running.CommandLine.Contains($serverScript)) {
      $prior | ConvertTo-Json
      exit 0
    }
  } catch { }
}
$stdout = Join-Path $stateDirectory 'server.stdout.log'
$stderr = Join-Path $stateDirectory 'server.stderr.log'
$priorPort = $env:HASR_PREVIEW_PORT
try {
  $env:HASR_PREVIEW_PORT = [string]$Port
  $serverProcess = Start-Process -FilePath (Get-Command node).Source -ArgumentList ('"' + $serverScript + '"') -WorkingDirectory $project -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
} finally {
  $env:HASR_PREVIEW_PORT = $priorPort
}
for ($attempt = 0; $attempt -lt 40; $attempt++) {
  Start-Sleep -Milliseconds 100
  if ((Test-Path -LiteralPath $stdout) -and (Get-Item -LiteralPath $stdout).Length -gt 0) {
    $state = Get-Content -LiteralPath $stdout -TotalCount 1 | ConvertFrom-Json
    $state | Add-Member -NotePropertyName stdout -NotePropertyValue $stdout
    $state | Add-Member -NotePropertyName stderr -NotePropertyValue $stderr
    $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
    $state | ConvertTo-Json
    exit 0
  }
  if ($serverProcess.HasExited) { throw "Preview server exited; see $stderr" }
}
throw "Preview server did not report readiness; see $stderr"
