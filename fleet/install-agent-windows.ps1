# Install Elastic Agent on a Windows VM and enroll it into Fleet (policy "Windows Servers").
# Run in an elevated PowerShell inside the VM, from the folder containing:
#   - this script
#   - ca.crt                     (CA of the ELK stack)
#   - enrollment-token.txt       (or pass -EnrollmentToken)
#   - elastic-agent-<ver>-windows-x86_64.zip
param(
  [string]$EnrollmentToken,
  [string]$FleetHost = "10.20.20.1",
  [int]$FleetPort = 8220,
  [int]$EsPort = 9200,
  [string]$AgentZip,
  [string]$CaCert = (Join-Path $PSScriptRoot "ca.crt")
)
$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run this script in PowerShell as Administrator."
}

if (-not $EnrollmentToken) {
  $tokenFile = Join-Path $PSScriptRoot "enrollment-token.txt"
  if (-not (Test-Path $tokenFile)) { throw "Missing -EnrollmentToken and $tokenFile" }
  $EnrollmentToken = (Get-Content $tokenFile -Raw).Trim()
}
if (-not $AgentZip) {
  $AgentZip = Get-ChildItem $PSScriptRoot -Filter "elastic-agent-*-windows-x86_64.zip" |
    Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
  if (-not $AgentZip) { throw "Agent zip not found next to the script (elastic-agent-*-windows-x86_64.zip)" }
}
if (-not (Test-Path $CaCert)) { throw "CA certificate not found: $CaCert" }

Write-Host "== Checking connectivity to $FleetHost" -ForegroundColor Cyan
foreach ($port in @($FleetPort, $EsPort)) {
  $ok = (Test-NetConnection $FleetHost -Port $port -WarningAction SilentlyContinue).TcpTestSucceeded
  Write-Host ("  {0}:{1} -> {2}" -f $FleetHost, $port, $(if ($ok) { "OK" } else { "BLOCKED" }))
  if (-not $ok) { throw "Cannot reach ${FleetHost}:$port. Check the host firewall / VMware network." }
}

Write-Host "== Installing CA to C:\ProgramData\Elastic\ca.crt" -ForegroundColor Cyan
New-Item -ItemType Directory -Force "C:\ProgramData\Elastic" | Out-Null
Copy-Item $CaCert "C:\ProgramData\Elastic\ca.crt" -Force

Write-Host "== Extracting $AgentZip" -ForegroundColor Cyan
$work = Join-Path $env:TEMP "elastic-agent-install"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
Expand-Archive $AgentZip -DestinationPath $work
$agentDir = Get-ChildItem $work -Directory | Select-Object -First 1

Write-Host "== Installing and enrolling Elastic Agent" -ForegroundColor Cyan
& (Join-Path $agentDir.FullName "elastic-agent.exe") install `
  --url="https://${FleetHost}:$FleetPort" `
  --enrollment-token="$EnrollmentToken" `
  --certificate-authorities="C:\ProgramData\Elastic\ca.crt" `
  --non-interactive
if ($LASTEXITCODE -ne 0) { throw "elastic-agent install failed (exit $LASTEXITCODE)" }

Remove-Item $work -Recurse -Force
Write-Host "== Done. Status:" -ForegroundColor Green
& "C:\Program Files\Elastic\Agent\elastic-agent.exe" status
