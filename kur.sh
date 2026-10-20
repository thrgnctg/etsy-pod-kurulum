#!/bin/bash
# Etsy POD otomasyonu — terminalden tek komutla kurulum (Mac ve Linux). K-162.
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main/kur.sh)"
# İşletim sistemine uygun kurulum betiğini bu açık repodan indirir ve çalıştırır. Asıl proje gizli repodadır;
# erişim için betik bu makineye özel bir GitHub anahtarı üretir ve sana GitHub'da eklettirir. Hiçbir gizli bilgi indirilmez ya da gönderilmez.
# Seçenekler (ortam değişkeni): HEDEF=<klasör> DAL=<yedek dalı> KURULUM_AG=1 (Linux: sihirbazı yerel ağdan aç)
set -euo pipefail
TABAN="${TABAN:-https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main}"
case "$(uname -s)" in
  Darwin) AD=Kur_Mac.command ;;
  Linux)  AD=kur_linux.sh ;;
  *) echo "Bu işletim sistemi desteklenmiyor: $(uname -s). Windows'ta PowerShell komutunu kullan (README)."; exit 1 ;;
esac
GEC=$(mktemp -d "${TMPDIR:-/tmp}/etsy-kurulum.XXXXXX")
curl -fsSL "$TABAN/$AD" -o "$GEC/$AD" || { echo "Kurulum betiği indirilemedi: $TABAN/$AD"; exit 1; }
chmod +x "$GEC/$AD"
echo "Kurulum betiği indirildi: $AD ($(wc -c < "$GEC/$AD" | tr -d ' ') bayt). Başlıyor…"
exec bash "$GEC/$AD" "$@"
