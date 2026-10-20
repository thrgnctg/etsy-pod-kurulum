#!/bin/bash
# Etsy POD otomasyonu — tek tıklamalı kurulum ve güncelleme (macOS; Mac mini / sunucu Mac dahil). K-160 G3.
# GitHub'dan indir (Releases → kurulum.zip ya da bu dosya), Finder'da çift tıkla. Adımlar:
#   1) Docker Desktop yoksa indirir ve kurar (ilk açılışta lisans onayı ve Mac şifresi senden istenir)
#   2) Bu makineye özel GitHub erişim anahtarı (deploy key) üretir; GitHub'da eklemen için sayfayı açar ve anahtarı panoya kopyalar
#   3) Projeyi (kod, ayarlar, kütüphane, görseller — Git LFS) klasöre indirir; varsa günceller
#   4) Görsel servisini başlatır ve tarayıcıda kurulum sihirbazını açar (gereken bilgileri orada sorar ve sınar)
#   5) Sihirbaz bitince tüm servisleri başlatır, n8n akışlarını, Telegram'ı ve ngrok'u bağlar, paneli açar
# Gizli bilgiler yalnız <klasör>/.secrets/ içinde kalır; hiçbir yere gönderilmez.
set -u
REPO_SSH="${REPO_SSH:-git@github.com:thrgnctg/etsy-pod-otomasyon.git}"
REPO_WEB="${REPO_WEB:-https://github.com/thrgnctg/etsy-pod-otomasyon}"
HEDEF="${HEDEF:-$HOME/EtsyOtomasyonCowork}"
DAL="${DAL:-main}"
GH_KEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:$HOME/.docker/bin:/Applications/Docker.app/Contents/Resources/bin"
LOG="$HOME/etsy_otomasyon_kurulum.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') Etsy POD otomasyonu kurulumu (macOS) — hedef: $HEDEF ==="
bitir() { echo "Günlük: $LOG"; read -r -p "Pencereyi kapatmak için Enter'a bas." _; exit "${1:-0}"; }
adim() { echo; echo "── $*"; }

# 1) Docker
adim "1/5 Docker"
if [ ! -d /Applications/Docker.app ] && ! command -v docker >/dev/null 2>&1; then
  ARCH=$(uname -m); [ "$ARCH" = "arm64" ] && U=arm64 || U=amd64
  DMG="$HOME/Downloads/Docker.dmg"
  echo "Docker Desktop indiriliyor ($U)…"
  curl -fL --progress-bar -o "$DMG" "https://desktop.docker.com/mac/main/$U/Docker.dmg" || { echo "HATA: Docker indirilemedi"; bitir 1; }
  hdiutil attach "$DMG" -nobrowse -quiet -mountpoint /Volumes/DockerKurulum || { echo "HATA: Docker.dmg açılamadı"; bitir 1; }
  cp -R /Volumes/DockerKurulum/Docker.app /Applications/ && echo "Docker.app Uygulamalar'a kopyalandı"
  hdiutil detach /Volumes/DockerKurulum -quiet
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker Desktop açılıyor. İlk açılışta lisans sözleşmesini kabul et ve istenirse Mac şifreni gir (senin adımın)."
  open -a Docker
  for i in $(seq 1 150); do docker info >/dev/null 2>&1 && break; sleep 2; done
fi
docker info >/dev/null 2>&1 || { echo "HATA: Docker çalışmıyor. Docker Desktop'ı açıp bu dosyayı tekrar çalıştır."; bitir 1; }
echo "Docker hazır: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

# Git aracı (konteynerde: git + git-lfs + ssh; Mac'e bir şey kurulmaz)
GIT_IMG=etsy-kurulum-git:1
if ! docker image inspect $GIT_IMG >/dev/null 2>&1; then
  printf 'FROM alpine:3.20\nRUN apk add --no-cache git git-lfs openssh-client bash\n' | docker build -q -t $GIT_IMG - >/dev/null || { echo "HATA: git aracı kurulamadı"; bitir 1; }
fi
mkdir -p "$HEDEF/.secrets"
chmod 700 "$HEDEF/.secrets"
G() {   # konteynerde git (anahtar /root/.ssh'a 600 izniyle kopyalanır)
  docker run --rm -v "$HEDEF:/proje" -w /proje -e DAL="$DAL" -e REPO="$REPO_SSH" $GIT_IMG bash -c "
    mkdir -p /root/.ssh && cp /proje/.secrets/github_deploy_key /root/.ssh/id && chmod 600 /root/.ssh/id
    echo '$GH_KEY' > /root/.ssh/known_hosts
    export GIT_SSH_COMMAND='ssh -i /root/.ssh/id -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/root/.ssh/known_hosts -o ConnectTimeout=20'
    git config --global --add safe.directory /proje; git config --global core.quotepath false
    $1"
}

# 2) GitHub erişimi
adim "2/5 GitHub erişimi"
if [ ! -f "$HEDEF/.secrets/github_deploy_key" ]; then
  docker run --rm -v "$HEDEF/.secrets:/k" $GIT_IMG ssh-keygen -q -t ed25519 -N "" -C "etsy-pod-otomasyon-$(scutil --get ComputerName 2>/dev/null | tr ' ' '-' || hostname)-$(date +%Y%m%d)" -f /k/github_deploy_key
  chmod 600 "$HEDEF/.secrets/github_deploy_key"
fi
if ! G "git ls-remote \$REPO >/dev/null 2>&1" ; then
  PUB=$(cat "$HEDEF/.secrets/github_deploy_key.pub")
  printf '%s' "$PUB" | pbcopy 2>/dev/null
  echo "Bu makinenin GitHub anahtarı (açık anahtar, panoya kopyalandı):"
  echo "  $PUB"
  echo "Açılan GitHub sayfasında: Title → bu makinenin adı · Key → yapıştır (⌘V) · bu makine yedek gönderecekse 'Allow write access' işaretle · Add key."
  open "$REPO_WEB/settings/keys/new"
  ok=""
  for i in $(seq 1 180); do G "git ls-remote \$REPO >/dev/null 2>&1" && { ok=1; break; }; [ $((i % 6)) -eq 1 ] && echo "  [$(date '+%H:%M:%S')] anahtarın eklenmesi bekleniyor…"; sleep 10; done
  [ -n "$ok" ] || { echo "GitHub erişimi gelmedi (30 dk). Anahtarı ekleyip bu dosyayı tekrar çalıştır."; bitir 1; }
fi
echo "GitHub erişimi tamam"

# 3) Proje dosyaları
adim "3/5 Proje dosyaları (görseller dahil; ilk indirme uzun sürebilir)"
if [ -d "$HEDEF/.git" ]; then
  echo "Var olan kurulum güncelleniyor"
  G "git fetch -q origin \$DAL && if [ -n \"\$(git status --porcelain)\" ]; then echo 'Yerel değişiklikler var: önce yedekleniyor'; fi" || true
  ( cd "$HEDEF/2.Sistem" 2>/dev/null && docker compose --env-file ../.secrets/keys.env run --rm --no-deps yedek simdi "kurulum öncesi yedek" ) || true
  G "git pull -q --ff-only origin \$DAL && git lfs pull" || { echo "HATA: güncelleme birleştirilemedi (yerel ve uzak değişiklikler çakışıyor). Claude'a haber ver."; bitir 1; }
else
  G "git init -q -b \$DAL && git remote add origin \$REPO && git lfs install --local >/dev/null && git fetch origin \$DAL && git checkout -q -f -B \$DAL origin/\$DAL && git lfs pull" \
    || { echo "HATA: proje indirilemedi"; bitir 1; }
fi
[ -f "$HEDEF/2.Sistem/docker-compose.yml" ] || { echo "HATA: proje dosyaları eksik"; bitir 1; }
echo "Sürüm: $(cat "$HEDEF/VERSION" 2>/dev/null)"
ENVF="$HEDEF/.secrets/keys.env"
touch "$ENVF" && chmod 600 "$ENVF"
grep -Eq '^N8N_ENCRYPTION_KEY=.+' "$ENVF" || echo "N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)" >> "$ENVF"
grep -Eq '^YEDEK_DAL=' "$ENVF" || echo "YEDEK_DAL=$DAL" >> "$ENVF"
cd "$HEDEF/2.Sistem" || bitir 1
DC() { docker compose --env-file "$ENVF" "$@"; }

# 4) Kurulum sihirbazı
adim "4/5 Görsel servisi ve kurulum sihirbazı (ilk kurulumda imaj 5-15 dk)"
DC up -d --build image-service || { echo "HATA: görsel servisi kurulamadı"; bitir 1; }
for i in $(seq 1 120); do curl -fsS -m 5 http://localhost:8000/health >/dev/null 2>&1 && break; sleep 3; done
curl -fsS -m 5 http://localhost:8000/health >/dev/null || { echo "HATA: görsel servisi açılmadı (docker compose logs image-service)"; bitir 1; }
tamam() { curl -fsS -m 10 http://localhost:8000/kurulum/api/durum 2>/dev/null | grep -q '"tamamlandi":true' && echo 1; }
if [ -z "$(tamam)" ]; then
  echo "Tarayıcıda kurulum sihirbazı açılıyor: http://localhost:8000/kurulum"
  open "http://localhost:8000/kurulum"
  echo "Sihirbazda bilgileri gir ve 'Kurulumu tamamla'ya bas. Bu pencere bekliyor…"
  until [ -n "$(tamam)" ]; do sleep 5; done
fi
echo "Sihirbaz tamamlandı"

# 5) Tüm servisler ve bağlantılar
adim "5/5 Servisler ve bağlantılar"
DC up -d --build n8n image-service yedek
DC exec -T image-service python /app/kurulum_son.py
if grep -Eq '^NGROK_AUTHTOKEN=.+' "$ENVF" && grep -Eq '^NGROK_DOMAIN=.+' "$ENVF" && [ -f "$HEDEF/.secrets/ngrok_panel.yml" ]; then
  DC --profile tunnel up -d ngrok && echo "ngrok tüneli başladı"
fi
DC ps
echo
echo "=== Kurulum bitti: $(date '+%H:%M:%S') — panel http://localhost:8000/panel ==="
open "http://localhost:8000/kurulum"
bitir 0
