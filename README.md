# Phone Proxy Logger

HTTP/HTTPS proxy dengan logging real-time untuk debugging Instagram login via mobile IP.

## Features

- ✅ Support HTTP dan HTTPS (CONNECT method)
- 📊 Real-time logging semua request dengan timestamp
- 🎨 Color-coded output untuk mudah dibaca
- 📦 Tampilkan bytes transferred untuk setiap connection
- 🔍 Debug Instagram API calls dengan detail

## Setup di HP (Termux)

### 1. Install dependencies

```bash
pkg update
pkg install python git openssh
```

### 2. Clone repo ini

```bash
cd ~
git clone https://github.com/alviarts/phone-proxy-logger.git
cd phone-proxy-logger
```

### 3. Jalankan proxy logger

```bash
python proxy_logger.py
```

Output:
```
[2026-05-08 18:30:15.123] 🚀 Proxy server started on 0.0.0.0:8080
[2026-05-08 18:30:15.124] 📊 Logging all requests in real-time...
```

### 4. Setup SSH tunnel (terminal baru)

Swipe Termux ke kanan → **New Session**, lalu:

```bash
autossh -M 0 -f -N \
  -o "ServerAliveInterval 30" \
  -o "ServerAliveCountMax 3" \
  -R 0.0.0.0:18080:127.0.0.1:8080 \
  phoneproxy@103.74.5.44
```

## Test dari VPS

```bash
# SSH ke VPS
ssh root@103.74.5.44

# Test proxy
curl -x http://127.0.0.1:18080 https://api.ipify.org

# Cek IP yang keluar
curl -x http://127.0.0.1:18080 https://api.ipify.org
```

Di HP kamu akan lihat log real-time:

```
[2026-05-08 18:31:02.456] 🔐 CONNECT api.ipify.org:443
[2026-05-08 18:31:02.678] ✅ Tunnel established to api.ipify.org:443
[2026-05-08 18:31:03.123] 🔌 Tunnel closed to api.ipify.org:443 (↑234 ↓89 bytes)
```

## Monitoring Instagram Login

Ketika worker mencoba login IG, kamu akan lihat:

```
[2026-05-08 18:35:12.345] 🔐 CONNECT i.instagram.com:443
[2026-05-08 18:35:12.567] ✅ Tunnel established to i.instagram.com:443
[2026-05-08 18:35:15.890] 🔌 Tunnel closed to i.instagram.com:443 (↑2345 ↓12678 bytes)

[2026-05-08 18:35:16.123] 🔐 CONNECT api.instagram.com:443
[2026-05-08 18:35:16.345] ✅ Tunnel established to api.instagram.com:443
[2026-05-08 18:35:18.678] 🔌 Tunnel closed to api.instagram.com:443 (↑3456 ↓23456 bytes)
```

## Troubleshooting

### Proxy timeout dari VPS

```bash
# Cek apakah proxy jalan di HP
ps aux | grep proxy_logger

# Cek apakah port 8080 listen
netstat -tlnp | grep 8080
```

### Tunnel tidak connect

```bash
# Cek autossh process
ps aux | grep autossh

# Kill dan restart
pkill autossh
autossh -M 0 -f -N -R 0.0.0.0:18080:127.0.0.1:8080 phoneproxy@103.74.5.44
```

### Lihat IP yang keluar

```bash
# Di VPS
curl -x http://127.0.0.1:18080 https://api.ipify.org
```

Harusnya return IP mobile carrier (XL/Axis), bukan IP VPS.

## Stop Proxy

```bash
# Tekan Ctrl+C di terminal yang running proxy_logger.py
# Atau kill process
pkill -f proxy_logger.py
```

## License

MIT
