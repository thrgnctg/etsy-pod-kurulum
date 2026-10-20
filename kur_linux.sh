#!/bin/bash
# Etsy POD otomasyonu — tek komutla kurulum ve güncelleme (Linux sunucu; Windows Server'da WSL2 içinde de çalışır). K-160 G3.
#   bash kur_linux.sh                 → ~/EtsyOtomasyonCowork'a kurar (ya da günceller)
#   HEDEF=/opt/etsy bash kur_linux.sh → başka klasöre
# Ekransız sunucuda kurulum sihirbazı iki yoldan açılır:
#   a) (önerilen) kendi bilgisayarından SSH tüneli: ssh -L 8000:localhost:8000 kullanici@sunucu → http://localhost:8000/kurulum
#   b) güvendiğin yerel ağda geçici olarak açık adres + tek kullanımlık anahtar (KURULUM_AG=1); kurulum bitince kapanır
set -u
REPO_SSH="${REPO_SSH:-git@github.com:thrgnctg/etsy-pod-otomasyon.git}"
REPO_WEB="${REPO_WEB:-https://github.com/thrgnctg/etsy-pod-otomasyon}"
HEDEF="${HEDEF:-$HOME/EtsyOtomasyonCowork}"
DAL="${DAL:-main}"
KURULUM_AG="${KURULUM_AG:-0}"
GH_KEY='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
LOG="$HOME/etsy_otomasyon_kurulum.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') Etsy POD otomasyonu kurulumu (Linux) — hedef: $HEDEF ==="
dur() { echo "HATA: $*"; echo "Günlük: $LOG"; exit 1; }
adim() { echo; echo "── $*"; }
SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo"

adim "1/5 Docker"
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker kuruluyor (get.docker.com; yönetici şifresi istenebilir)…"
  curl -fsSL https://get.docker.com | $SUDO sh || dur "Docker kurulamadı"
  $SUDO systemctl enable --now docker 2>/dev/null || $SUDO service docker start 2>/dev/null || true
fi
D="docker"
docker info >/dev/null 2>&1 || D="$SUDO docker"
$D info >/dev/null 2>&1 || dur "Docker çalışmıyor (systemctl status docker)"
$D compose version >/dev/null 2>&1 || dur "docker compose eklentisi yok (Docker'ı get.docker.com ile güncelle)"
echo "Docker hazır: $($D version --format '{{.Server.Version}}' 2>/dev/null)"

GIT_IMG=etsy-kurulum-git:1
$D image inspect $GIT_IMG >/dev/null 2>&1 || printf 'FROM alpine:3.20\nRUN apk add --no-cache git git-lfs openssh-client bash\n' | $D build -q -t $GIT_IMG - >/dev/null || dur "git aracı kurulamadı"
mkdir -p "$HEDEF/.secrets" && chmod 700 "$HEDEF/.secrets"
G() {
  $D run --rm -v "$HEDEF:/proje" ${EK_BAGLA:+-v "$EK_BAGLA:$EK_BAGLA"} -w /proje -e DAL="$DAL" -e REPO="$REPO_SSH" -e HUID="$(id -u)" -e HGID="$(id -g)" $GIT_IMG bash -c "
    mkdir -p /root/.ssh && cp /proje/.secrets/github_deploy_key /root/.ssh/id && chmod 600 /root/.ssh/id
    echo '$GH_KEY' > /root/.ssh/known_hosts
    export GIT_SSH_COMMAND='ssh -i /root/.ssh/id -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/root/.ssh/known_hosts -o ConnectTimeout=20'
    git config --global --add safe.directory /proje; git config --global core.quotepath false
    $1
    r=\$?; chown -R \$HUID:\$HGID /proje 2>/dev/null; exit \$r"
}

adim "2/5 GitHub erişimi"
if [ ! -f "$HEDEF/.secrets/github_deploy_key" ]; then
  $D run --rm -v "$HEDEF/.secrets:/k" $GIT_IMG sh -c "ssh-keygen -q -t ed25519 -N '' -C 'etsy-pod-otomasyon-$(hostname)-$(date +%Y%m%d)' -f /k/github_deploy_key && chown $(id -u):$(id -g) /k/github_deploy_key /k/github_deploy_key.pub"
  chmod 600 "$HEDEF/.secrets/github_deploy_key"
fi
if ! G "git ls-remote \$REPO >/dev/null 2>&1"; then
  echo "Bu makinenin GitHub anahtarı (açık anahtar):"
  echo
  cat "$HEDEF/.secrets/github_deploy_key.pub"
  echo
  echo "GitHub'da ekle: $REPO_WEB/settings/keys/new → Key'e yapıştır; bu makine yedek gönderecekse 'Allow write access' → Add key."
  ok=""
  for i in $(seq 1 180); do G "git ls-remote \$REPO >/dev/null 2>&1" && { ok=1; break; }; [ $((i % 6)) -eq 1 ] && echo "  [$(date '+%H:%M:%S')] anahtarın eklenmesi bekleniyor…"; sleep 10; done
  [ -n "$ok" ] || dur "GitHub erişimi gelmedi (30 dk). Anahtarı ekleyip tekrar çalıştır."
fi
echo "GitHub erişimi tamam"

adim "3/5 Proje dosyaları (görseller dahil)"
if [ -d "$HEDEF/.git" ]; then
  ( cd "$HEDEF/2.Sistem" 2>/dev/null && $D compose --env-file ../.secrets/keys.env run --rm --no-deps yedek simdi "kurulum öncesi yedek" ) || true
  G "git pull -q --ff-only origin \$DAL && git lfs pull" || dur "güncelleme birleştirilemedi (yerel ve uzak değişiklikler çakışıyor)"
else
  G "git init -q -b \$DAL && git remote add origin \$REPO && git lfs install --local >/dev/null && git fetch origin \$DAL && git checkout -q -f -B \$DAL origin/\$DAL && git lfs pull" || dur "proje indirilemedi"
fi
[ -f "$HEDEF/2.Sistem/docker-compose.yml" ] || dur "proje dosyaları eksik"
echo "Sürüm: $(cat "$HEDEF/VERSION" 2>/dev/null)"
ENVF="$HEDEF/.secrets/keys.env"
touch "$ENVF" && chmod 600 "$ENVF"
setenv() { grep -v "^$1=" "$ENVF" > "$ENVF.tmp"; echo "$1=$2" >> "$ENVF.tmp"; mv "$ENVF.tmp" "$ENVF"; chmod 600 "$ENVF"; }
grep -Eq '^N8N_ENCRYPTION_KEY=.+' "$ENVF" || setenv N8N_ENCRYPTION_KEY "$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
grep -Eq '^YEDEK_DAL=' "$ENVF" || setenv YEDEK_DAL "$DAL"
cd "$HEDEF/2.Sistem" || dur "klasör yok"
DC() { $D compose --env-file "$ENVF" ${COMPOSE_EK:+-f docker-compose.yml -f "$COMPOSE_EK"} "$@"; }
[ "${DURAK:-}" = 3 ] && { echo "DURAK 3 (test)"; exit 0; }

adim "4/5 Görsel servisi ve kurulum sihirbazı (ilk kurulumda imaj 5-15 dk)"
if [ "$KURULUM_AG" = 1 ]; then
  setenv PANEL_ADRES 0.0.0.0
  od -An -tx1 -N16 /dev/urandom | tr -d ' \n' > "$HEDEF/.secrets/kurulum_anahtari"; chmod 600 "$HEDEF/.secrets/kurulum_anahtari"
fi
DC up -d --build image-service || dur "görsel servisi kurulamadı"
for i in $(seq 1 120); do curl -fsS -m 5 http://localhost:8000/health >/dev/null 2>&1 && break; sleep 3; done
curl -fsS -m 5 http://localhost:8000/health >/dev/null || dur "görsel servisi açılmadı ($D compose logs image-service)"
tamam() { curl -fsS -m 10 http://localhost:8000/kurulum/api/durum 2>/dev/null | grep -q '"tamamlandi":true' && echo 1; }
if [ -z "$(tamam)" ]; then
  if [ "$KURULUM_AG" = 1 ]; then
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo "Kurulum sihirbazı (yalnız güvendiğin ağda): http://${IP:-SUNUCU_IP}:8000/kurulum?anahtar=$(cat "$HEDEF/.secrets/kurulum_anahtari")"
  else
    echo "Kendi bilgisayarında:  ssh -L 8000:localhost:8000 $(whoami)@$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "Sonra tarayıcıda:      http://localhost:8000/kurulum"
  fi
  echo "Sihirbazda 'Kurulumu tamamla'ya basınca bu komut devam eder…"
  until [ -n "$(tamam)" ]; do sleep 5; done
fi
echo "Sihirbaz tamamlandı"
if [ "$KURULUM_AG" = 1 ]; then setenv PANEL_ADRES 127.0.0.1; rm -f "$HEDEF/.secrets/kurulum_anahtari"; fi

adim "5/5 Servisler ve bağlantılar"
DC up -d --build n8n image-service yedek
DC exec -T image-service python /app/kurulum_son.py
if grep -Eq '^NGROK_AUTHTOKEN=.+' "$ENVF" && grep -Eq '^NGROK_DOMAIN=.+' "$ENVF" && [ -f "$HEDEF/.secrets/ngrok_panel.yml" ]; then
  DC --profile tunnel up -d ngrok && echo "ngrok tüneli başladı"
fi
DC ps
echo "=== Kurulum bitti: $(date '+%H:%M:%S') — panel: http://localhost:8000/panel (sunucuda SSH tüneliyle) ==="
