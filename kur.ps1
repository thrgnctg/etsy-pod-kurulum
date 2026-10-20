# Etsy POD otomasyonu — terminalden tek komutla kurulum (Windows 10/11 ve Windows Server). K-162.
#   PowerShell:  irm https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main/kur.ps1 | iex
#   cmd:         powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main/kur.ps1 | iex"
# Kurulum betiklerini bu açık repodan geçici klasöre indirir ve ayrı bir PowerShell penceresinde çalıştırır (bu pencere kapanmaz).
# Asıl proje gizli repodadır; erişim için betik bu makineye özel bir GitHub anahtarı üretir ve sana GitHub'da eklettirir.
$ErrorActionPreference = "Stop"
$taban = if ($env:TABAN) { $env:TABAN } else { "https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main" }
$gec = Join-Path $env:TEMP ("etsy-kurulum-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $gec | Out-Null
foreach ($ad in @("Kur_Windows.ps1", "kur_linux.sh")) {
  Invoke-WebRequest -UseBasicParsing -Uri "$taban/$ad" -OutFile (Join-Path $gec $ad)
}
Write-Host "Kurulum betikleri indirildi: $gec"
$arg = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $gec "Kur_Windows.ps1"))
if ($env:HEDEF) { $arg += @("-Hedef", $env:HEDEF) }
if ($env:DAL) { $arg += @("-Dal", $env:DAL) }
Start-Process -FilePath "powershell.exe" -ArgumentList $arg -Wait
