# Etsy POD otomasyonu — kurulum

Bu repo yalnız **kurulum betiklerini** içerir. Kod, ayarlar ve hiçbir anahtar burada yoktur; asıl proje gizli repodadır
(`thrgnctg/etsy-pod-otomasyon`) ve erişim yalnız sahibinin GitHub'da eklediği makine anahtarıyla olur.

## Terminalden tek komutla kurulum

**Mac ve Linux** (Terminal):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main/kur.sh)"
```

**Windows 10/11 ve Windows Server** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main/kur.ps1 | iex
```

(cmd'de: `powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/thrgnctg/etsy-pod-kurulum/main/kur.ps1 | iex"`)

Ekransız Linux sunucuda kurulum sihirbazını kendi bilgisayarında aç: `ssh -L 8000:localhost:8000 kullanici@sunucu` → http://localhost:8000/kurulum.
Seçenekler (ortam değişkeni): `HEDEF=<klasör>` (varsayılan `~/EtsyOtomasyonCowork`), `DAL=<yedek dalı>` (ikinci makine için ör. `makine-sunucu`), `KURULUM_AG=1` (Linux: sihirbazı güvendiğin yerel ağdan tek kullanımlık anahtarla aç).

## Çift tıklamayla kurulum
Bu repodan makinene uygun dosyayı indir: Mac `Kur_Mac.command` · Windows `Kur_Windows.bat` (tek dosya) · Linux `kur_linux.sh`.

## Kurulum ne yapar?
1. Docker'ı denetler, yoksa kurar (Docker Desktop lisans onayı ve yönetici şifresi senden istenir).
2. Bu makineye özel bir GitHub anahtarı (deploy key) üretir, GitHub'da **Settings → Deploy keys → Add deploy key** sayfasını açar; anahtarı sen eklersin (yedek gönderecek makinede *Allow write access*).
3. Projeyi (görseller dahil, Git LFS) indirir; var olan kurulumu günceller.
4. Tarayıcıda **kurulum sihirbazını** açar: Google (Vertex/Gemini), Printify, Etsy, Telegram, ngrok, telefondan giriş, ek yapay zekâ hesapları ve yedek dalı — her bilgi kaydedilmeden sınanır, gizli değerler yalnız makinedeki `.secrets/` klasörüne yazılır.
5. Tüm servisleri başlatır; n8n akışları, Telegram ve ngrok kendiliğinden bağlanır. Panel: http://localhost:8000/panel

Bu repodaki betikler gizli repodaki `kurulum/` klasörünün yansımasıdır; her sürümde eşitlenir. Tüm hakları saklıdır.
