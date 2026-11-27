# Panduan Failover Jaringan Router <-> Hotspot Cadangan KasirToko

Dokumen ini menjelaskan desain komunikasi LAN, profil endpoint `primary_router` <-> `backup_hotspot`, mekanisme failover otomatis pada aplikasi Staff, serta keterbatasan Android yang harus dipahami staf toko.

## 1. Status Jaringan Eksplisit Aplikasi

### Pada KasirToko Admin (`AdminNetworkState`)
- **`Router Online` (`routerOnline`)**: Server aktif dan IP lokal Admin sesuai profil `primary_router` (atau antarmuka non-hotspot aktif).
- **`Hotspot Cadangan` (`hotspotBackup`)**: Server aktif pada subnet/IP tethering Hotspot Android (`backup_hotspot`, seperti `192.168.43.x`, `192.168.137.x`, `172.20.10.x`).
- **`Offline` (`offline`)**: Perangkat Admin tidak memiliki antarmuka IP LAN/Wi-Fi/Hotspot aktif.
- **`Server Tidak Tersedia` (`serverUnavailable`)**: IP jaringan tersedia tetapi `LanPosServer` belum dijalankan.

### Pada KasirToko Staff (`StaffNetworkStatus`)
- **`Router Online` (`routerOnline`)**: Terhubung dan terverifikasi (`TLS SHA-256` + `server_id`) ke jalur utama Admin.
- **`Hotspot Cadangan` (`hotspotBackup`)**: Terhubung dan terverifikasi (`TLS SHA-256` + `server_id`) melalui Hotspot HP Admin cadangan tanpa perlu pairing ulang.
- **`Connecting` (`connecting`)**: Sedang mencoba jabat tangan awal / memulihkan sesi ke Admin.
- **`Reconnecting` (`reconnecting`)**: Koneksi WebSocket/HTTP terputus; background probe sedang memindai endpoint cadangan & UDP discovery.
- **`Offline` (`offline`)**: Tidak ada jalur jaringan lokal / server tidak merespons di LAN.
- **`Server Tidak Tersedia` (`serverUnavailable`)**: Jaringan aktif, namun server menolak/tidak aktif, atau terjadi ketidaksesuaian `server_id` / sertifikat TLS (`CHECKOUT TERKUNCI`).

## 2. Konfigurasi di POS Admin (`MultiDeviceServerScreen`)

1. Buka **Server LAN & Terminal Staff**.
2. Pada kartu **Failover Jaringan: Router Utama <-> Hotspot Cadangan**:
   - **1. Router Utama (`primary_router`)**: Masukkan IP LAN tetap (DHCP reservation/static IP) HP Admin pada Wi-Fi router toko (misal `192.168.1.50`), port `8443`, dan SSID router opsional.
   - **2. Hotspot Cadangan (`backup_hotspot`)**: Masukkan IP hotspot HP Admin (umumnya `192.168.43.1`), port `8443`, dan SSID Hotspot HP Admin.
3. Profil ini otomatis dikirim ke setiap HP Staff pada saat QR/Manual Pairing, `/api/v1/health`, `/api/v1/auth/pin-login`, `/api/v1/auth/me`, `/api/v1/store/bootstrap`, serta frame WS `hello`.

## 3. Alur Probing & Failover Otomatis di POS Staff

Ketika aplikasi Staff dibuka atau koneksi WebSocket terputus (`LanWsClient.onReconnectProbeNeeded`), `StaffSessionController._discoverAndSelectReachableEndpoint()` mengeksekusi urutan ketat berikut:

1. **Uji Endpoint Tersimpan Secara Deterministik:**
   - `serverUrl` terakhir yang sukses -> `primaryServerUrl` -> `backupServerUrl` -> daftar `candidateServerUrls`.
2. **UDP LAN Discovery & Probe Gateway Subnet (Hanya Jika Profil Terkonfigurasi Gagal):**
   - `LanDiscoveryClient.discover(expectedServerId: creds.serverId)` mengirim siaran UDP ke port `45843` (`KASIRTOKO_DISCOVER`).
   - `LanDiscoveryResponder` di HP Admin membalas `KASIRTOKO_HERE|{server_id, port, ips, network_mode}`.
   - Staff memfilter respons ketat hanya untuk `server_id` yang cocok dan turut menguji gateway `.1` subnet aktif (`192.168.43.1`, `192.168.137.1`, dst.).
3. **Verifikasi Keamanan Mutlak pada Setiap Kandidat (`LanHttpClient.checkHealthVerified`):**
   - Pin sertifikat **SHA-256 TLS DER** tetap divalidasi secara ketat (tidak pernah melemahkan atau menonaktifkan `badCertificateCallback`).
   - Field `server_id` pada `/api/v1/health` harus persis sama dengan `server_id` Admin yang dipasangkan. Jika berbeda, kandidat ditolak keras.
4. **Pemulihan Tanpa Kehilangan Keranjang:**
   - Jika kandidat baru lolos verifikasi, `credentials.serverUrl` diperbarui otomatis tanpa menghapus `device_token`, `device_secret`, `session_token`, maupun keranjang kasir (`cartItems`), lalu `reconcilePendingCheckoutIntents()` segera mengecek transaksi menggantung.

## 4. Keterbatasan Android & SOP Darurat Router Mati

- **Keterbatasan Hardware/OS:** Banyak HP Android menonaktifkan Hotspot ketika Wi-Fi client dinyalakan atau tidak mampu mengaktifkan Wi-Fi client + Hotspot bersamaan secara andal.
- **SOP Saat Router Toko Mati / Internet/Wi-Fi Bermasalah:**
  1. Di HP **POS Admin**, nyalakan **Hotspot Pribadi** sesuai profil `backup_hotspot` dan pastikan status server di Admin berubah menjadi **Hotspot Cadangan**.
  2. Di seluruh HP **POS Staff**, hubungkan Wi-Fi perangkat ke Hotspot HP Admin.
  3. Aplikasi Staff otomatis mendeteksi endpoint Hotspot cadangan dan melanjutkan transaksi tanpa pairing ulang. Jika IP hotspot di perangkat tertentu berbeda (mis. DHCP acak vendor), kasir cukup membuka menu **Koneksi, Struk & Diagnostik -> Ganti IP Manual (Router/Hotspot)** — perubahan tetap diverifikasi dengan TLS SHA-256 dan `server_id`.
  4. Selama terputus di tengah proses perpindahan jaringan, tombol **Bayar** tetap terkunci untuk mencegah transaksi ganda atau kehilangan sinkronisasi stok.
