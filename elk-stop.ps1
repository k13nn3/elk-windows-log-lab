# Dừng ELK (log, dashboard, agent đã enroll, chứng chỉ vẫn nằm trong volume)
# rồi tắt Docker Desktop để VmmemWSL trả RAM về cho Windows.
#   .\elk-stop.ps1              dừng ELK + tắt Docker Desktop
#   .\elk-stop.ps1 -KeepDocker  chỉ dừng ELK, Docker chạy tiếp cho phần mềm khác
param([switch]$KeepDocker)

Set-Location $PSScriptRoot

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker Desktop không chạy, không có gì để dừng."
    exit 0
}

# stop (không phải down -v): giữ container và volume
docker compose stop
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($KeepDocker) { exit 0 }

# Không tắt Docker nếu phần mềm khác vẫn đang dùng
$others = docker ps -q
if ($others) {
    Write-Host "`nCòn container khác đang chạy, giữ Docker Desktop:"
    docker ps --format "  {{.Names}}  ({{.Status}})"
    exit 0
}

docker desktop stop

# VM của WSL vẫn giữ ~1GB sau khi distro đã dừng; chỉ tắt khi không còn distro nào chạy (vd Ubuntu)
$running = (wsl --list --running --quiet) -replace "`0", '' | Where-Object { $_.Trim() }
if (-not $running) { wsl --shutdown }
Write-Host "`nĐã dừng ELK và Docker Desktop. Dữ liệu vẫn còn, chạy .\elk-start.ps1 để bật lại."
