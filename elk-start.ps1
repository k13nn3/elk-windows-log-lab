# Bật Docker Desktop (nếu đang tắt) rồi chạy ELK với dữ liệu cũ trong volume.
Set-Location $PSScriptRoot

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Đang bật Docker Desktop..."
    docker desktop start
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

docker compose up -d --wait
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$kibanaUrl = (Get-Content .env | Where-Object { $_ -match '^KIBANA_PUBLIC_URL=' }) -replace '^KIBANA_PUBLIC_URL=', ''
Write-Host "`nELK đã chạy. Kibana: $kibanaUrl"
