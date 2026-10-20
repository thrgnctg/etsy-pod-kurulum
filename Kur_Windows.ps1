# Etsy POD otomasyonu — tek tıklamalı kurulum ve güncelleme (Windows 10/11; Windows Server'da WSL2 yolu). K-160 G3.
# Kur_Windows.bat'a çift tıkla (bu dosyayı yönetici izni olmadan çalıştırır; Docker kurulumu için Windows izin sorabilir).
#   1) Docker Desktop yoksa winget ile kurar (Windows yeniden başlatma isteyebilir; sonra bu dosyayı tekrar çalıştır)
#   2) Bu makineye özel GitHub erişim anahtarı (deploy key) üretir, panoya kopyalar, GitHub sayfasını açar
#   3) Projeyi (kod, ayarlar, kütüphane, görseller — Git LFS) indirir ya da günceller
#   4) Görsel servisini başlatır ve tarayıcıda kurulum sihirbazını açar
#   5) Sihirbaz bitince tüm servisleri başlatır, n8n akışlarını, Telegram'ı ve ngrok'u bağlar
param([string]$Hedef = "$env:USERPROFILE\EtsyOtomasyonCowork", [string]$Dal = "main")
$ErrorActionPreference = "Continue"
$RepoSsh = "git@github.com:thrgnctg/etsy-pod-otomasyon.git"
$RepoWeb = "https://github.com/thrgnctg/etsy-pod-otomasyon"
$GhKey = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
$Log = "$env:USERPROFILE\etsy_otomasyon_kurulum.log"
Start-Transcript -Path $Log -Append | Out-Null
function Dur($m) { Write-Host "HATA: $m" -ForegroundColor Red; Write-Host "Günlük: $Log"; Stop-Transcript | Out-Null; Read-Host "Kapatmak için Enter"; exit 1 }
function Adim($m) { Write-Host ""; Write-Host "── $m" -ForegroundColor Cyan }
Write-Host "=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Etsy POD otomasyonu kurulumu (Windows) — hedef: $Hedef ==="

# Windows Server: Docker Desktop desteklenmez → WSL2 + Ubuntu içinde Linux kurulumu
$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -ne 1) {
  Adim "Windows Server algılandı: WSL2 + Ubuntu ile kurulum"
  $wsl = (wsl -l -q 2>$null) -join " "
  if ($wsl -notmatch "Ubuntu") {
    Write-Host "WSL2 ve Ubuntu kuruluyor (yönetici izni ister; bitince Windows'u yeniden başlat ve bu dosyayı tekrar çalıştır)…"
    Start-Process -Verb RunAs -Wait wsl -ArgumentList "--install -d Ubuntu"
    Dur "WSL2 kuruldu. Windows'u yeniden başlat, Ubuntu'yu bir kez açıp kullanıcı oluştur, sonra bu dosyayı tekrar çalıştır."
  }
  $Kok = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $env:KUR_BETIK }
  $betik = Join-Path $Kok "kur_linux.sh"
  if (-not (Test-Path $betik)) { Dur "Windows Server için kur_linux.sh de bu dosyanın yanında olmalı (GitHub → kurulum/kur_linux.sh → Download raw file)" }
  $wp = (wsl -d Ubuntu wslpath -a ($betik -replace '\\', '/')).Trim()
  wsl -d Ubuntu -- bash -lc "bash '$wp'"
  Stop-Transcript | Out-Null; Read-Host "Kapatmak için Enter"; exit $LASTEXITCODE
}

Adim "1/5 Docker"
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Dur "winget yok. Docker Desktop'ı https://www.docker.com/products/docker-desktop/ adresinden kur, sonra tekrar çalıştır." }
  Write-Host "Docker Desktop kuruluyor (winget; Windows izin isteyebilir)…"
  winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Dur "Docker Desktop kuruldu ama komut görünmüyor. Windows'u yeniden başlatıp bu dosyayı tekrar çalıştır." }
}
docker info *> $null
if ($LASTEXITCODE -ne 0) {
  $exe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
  if (Test-Path $exe) { Write-Host "Docker Desktop açılıyor (ilk açılışta lisans sözleşmesini kabul et; WSL2 güncellemesi isteyebilir)…"; Start-Process $exe }
  for ($i = 0; $i -lt 150; $i++) { docker info *> $null; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep 2 }
}
docker info *> $null
if ($LASTEXITCODE -ne 0) { Dur "Docker çalışmıyor. Docker Desktop'ı açıp (gerekirse Windows'u yeniden başlatıp) tekrar çalıştır." }
Write-Host "Docker hazır"

$GitImg = "etsy-kurulum-git:1"
docker image inspect $GitImg *> $null
if ($LASTEXITCODE -ne 0) {
  "FROM alpine:3.20`nRUN apk add --no-cache git git-lfs openssh-client bash`n" | docker build -q -t $GitImg - | Out-Null
  if ($LASTEXITCODE -ne 0) { Dur "git aracı kurulamadı" }
}
New-Item -ItemType Directory -Force -Path "$Hedef\.secrets" | Out-Null
function G([string]$cmd) {
  $s = "mkdir -p /root/.ssh && cp /proje/.secrets/github_deploy_key /root/.ssh/id && chmod 600 /root/.ssh/id && echo '$GhKey' > /root/.ssh/known_hosts && " +
       "export GIT_SSH_COMMAND='ssh -i /root/.ssh/id -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/root/.ssh/known_hosts -o ConnectTimeout=20' && " +
       "git config --global --add safe.directory /proje && git config --global core.quotepath false && git config --global core.autocrlf false && $cmd"
  docker run --rm -v "${Hedef}:/proje" -w /proje -e "DAL=$Dal" -e "REPO=$RepoSsh" $GitImg bash -c $s
  return ($LASTEXITCODE -eq 0)
}

Adim "2/5 GitHub erişimi"
if (-not (Test-Path "$Hedef\.secrets\github_deploy_key")) {
  docker run --rm -v "$Hedef\.secrets:/k" $GitImg sh -c "ssh-keygen -q -t ed25519 -N '' -C 'etsy-pod-otomasyon-$env:COMPUTERNAME-$(Get-Date -Format yyyyMMdd)' -f /k/github_deploy_key"
  if (-not (Test-Path "$Hedef\.secrets\github_deploy_key")) { Dur "GitHub anahtarı üretilemedi" }
}
if (-not (G 'git ls-remote $REPO >/dev/null 2>&1')) {
  $pub = (Get-Content "$Hedef\.secrets\github_deploy_key.pub" -Raw).Trim()
  Set-Clipboard -Value $pub
  Write-Host "Bu makinenin GitHub anahtarı (açık anahtar, panoya kopyalandı):"
  Write-Host "  $pub"
  Write-Host "Açılan sayfada: Title → bu makinenin adı · Key → yapıştır (Ctrl+V) · yedek gönderecekse 'Allow write access' · Add key."
  Start-Process "$RepoWeb/settings/keys/new"
  $ok = $false
  for ($i = 0; $i -lt 180; $i++) { if (G 'git ls-remote $REPO >/dev/null 2>&1') { $ok = $true; break }; if ($i % 6 -eq 0) { Write-Host "  [$(Get-Date -Format HH:mm:ss)] anahtarın eklenmesi bekleniyor…" }; Start-Sleep 10 }
  if (-not $ok) { Dur "GitHub erişimi gelmedi (30 dk). Anahtarı ekleyip tekrar çalıştır." }
}
Write-Host "GitHub erişimi tamam"

Adim "3/5 Proje dosyaları (görseller dahil; ilk indirme uzun sürebilir)"
$Envf = "$Hedef\.secrets\keys.env"
if (Test-Path "$Hedef\.git") {
  Push-Location "$Hedef\2.Sistem"; docker compose --env-file $Envf run --rm --no-deps yedek simdi "kurulum öncesi yedek"; Pop-Location
  if (-not (G 'git pull -q --ff-only origin $DAL && git lfs pull')) { Dur "güncelleme birleştirilemedi (yerel ve uzak değişiklikler çakışıyor)" }
} else {
  if (-not (G 'git init -q -b $DAL && git remote add origin $REPO && git lfs install --local >/dev/null && git fetch origin $DAL && git config core.fileMode false && git checkout -q -f -B $DAL origin/$DAL && git lfs pull')) { Dur "proje indirilemedi" }
}
if (-not (Test-Path "$Hedef\2.Sistem\docker-compose.yml")) { Dur "proje dosyaları eksik" }
Write-Host "Sürüm: $((Get-Content "$Hedef\VERSION" -ErrorAction SilentlyContinue))"
if (-not (Test-Path $Envf)) { New-Item -ItemType File -Path $Envf | Out-Null }
$envtxt = Get-Content $Envf -Raw -ErrorAction SilentlyContinue
if ($envtxt -notmatch "(?m)^N8N_ENCRYPTION_KEY=.+") {
  $b = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  Add-Content -Path $Envf -Value ("N8N_ENCRYPTION_KEY=" + (($b | ForEach-Object { $_.ToString("x2") }) -join "")) -Encoding ascii
}
if ($envtxt -notmatch "(?m)^YEDEK_DAL=") { Add-Content -Path $Envf -Value "YEDEK_DAL=$Dal" -Encoding ascii }
if ($envtxt -notmatch "(?m)^YEDEK_FILEMODE=") { Add-Content -Path $Envf -Value "YEDEK_FILEMODE=false" -Encoding ascii }   # NTFS'te çalıştırma izni yok
# .secrets yalnız bu kullanıcıya açık
icacls "$Hedef\.secrets" /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" *> $null
Set-Location "$Hedef\2.Sistem"

Adim "4/5 Görsel servisi ve kurulum sihirbazı (ilk kurulumda imaj 5-15 dk)"
docker compose --env-file $Envf up -d --build image-service
if ($LASTEXITCODE -ne 0) { Dur "görsel servisi kurulamadı" }
$saglik = $false
for ($i = 0; $i -lt 120; $i++) { try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://localhost:8000/health | Out-Null; $saglik = $true; break } catch { Start-Sleep 3 } }
if (-not $saglik) { Dur "görsel servisi açılmadı (docker compose logs image-service)" }
function Tamam { try { $d = Invoke-RestMethod -TimeoutSec 10 http://localhost:8000/kurulum/api/durum; return [bool]$d.tamamlandi } catch { return $false } }
if (-not (Tamam)) {
  Write-Host "Tarayıcıda kurulum sihirbazı açılıyor: http://localhost:8000/kurulum"
  Start-Process "http://localhost:8000/kurulum"
  Write-Host "Sihirbazda bilgileri gir ve 'Kurulumu tamamla'ya bas. Bu pencere bekliyor…"
  while (-not (Tamam)) { Start-Sleep 5 }
}
Write-Host "Sihirbaz tamamlandı"

Adim "5/5 Servisler ve bağlantılar"
docker compose --env-file $Envf up -d --build n8n image-service yedek
docker compose --env-file $Envf exec -T image-service python /app/kurulum_son.py
$envtxt = Get-Content $Envf -Raw
if (($envtxt -match "(?m)^NGROK_AUTHTOKEN=.+") -and ($envtxt -match "(?m)^NGROK_DOMAIN=.+") -and (Test-Path "$Hedef\.secrets\ngrok_panel.yml")) {
  docker compose --env-file $Envf --profile tunnel up -d ngrok; Write-Host "ngrok tüneli başladı"
}
docker compose --env-file $Envf ps
Write-Host ""
Write-Host "=== Kurulum bitti: $(Get-Date -Format HH:mm:ss) — panel http://localhost:8000/panel ===" -ForegroundColor Green
Start-Process "http://localhost:8000/kurulum"
Stop-Transcript | Out-Null
Read-Host "Kapatmak için Enter"
