# STAFF_APP_ARCHITECTURE.md — Arsitektur Sistem POS Multi-Device (`stafkasirtoko` & `kasirtoko`)

**Versi Dokumen:** `v2.0` (Selaras Keputusan Final Desain POS Multi-Device)  
**Target Klien:** POS Staff Android (`stafkasirtoko`)  
**Pusat Otoritatif:** POS Admin Android (`kasirtoko`)  
**Jaringan:** Lokal Wi-Fi Router atau Hotspot Android (tanpa ketergantungan internet)

---

## 1. Prinsip & Topologi Sistem

1. **Single Source of Truth (SSOT) di POS Admin:** Seluruh data master, stok, user/PIN, shift, laci kas, transaksi sah, akuntansi kas, log audit, dan perangkat printer dikelola terpusat oleh `kasirtoko`.
2. **Thin-Terminal POS Staff:** `stafkasirtoko` hanya berfungsi sebagai terminal kasir: pairing perangkat, login PIN kasir ke Admin, scan & pencarian katalog cache, manajemen keranjang persisten lokal, pengajuan checkout idempoten ke Admin, pratinjau struk resmi, dan penerusan permintaan cetak / buka laci (sesuai izin) ke Admin.
3. **Skalabilitas Dinamis Tanpa Batas Hardcoded:** Admin dapat menerima pairing terminal sebanyak apa pun melalui alur dinamis (`paired_terminals` tanpa konstanta batas perangkat di kode), sementara kapasitas realistis per perangkat Admin dan router/hotspot diverifikasi lewat **Capacity & Stress Test**.

```
+-----------------------------------------------------------------------+
|              JARINGAN LOKAL (Wi-Fi Router / Hotspot Android)          |
|                                                                       |
|  +-----------------------+     HTTPS (TLS Pinning + HMAC + Nonce)     |
|  | POS STAFF TERMINAL 1  | ----------------------------------------+  |
|  | (terminal_id: TERM-01)| <======== WSS (Heartbeat & Events) ===+ |  |
|  +-----------------------+                                       | |  |
|                                                                  v v  |
|  +-----------------------+     HTTPS + WSS          +------------+----+---------------+
|  | POS STAFF TERMINAL N  | <======================> |  POS ADMIN (kasirtoko)          |
|  | (terminal_id: TERM-N) |                          |  - Foreground Server Service    |
|  +-----------------------+                          |  - TLS Self-Signed CA/Cert Mgr  |
|                                                     |  - Auth, RateLimit & RBAC       |
|                                                     |  - Shift & Cash Register Engine |
|                                                     |  - SQLite v5 (WAL Mode, SSOT)   |
|                                                     |  - Serial Print & Drawer Queue  |
|                                                     +----------------+----------------+
|                                                                      |
+----------------------------------------------------------------------|----------------+
                                                                       v
                                                     [Printer Thermal / Cash Drawer RJ11]
```

---

## 2. Model Shift & Laci Kas (`SHARED_DRAWER` vs `INDIVIDUAL_DRAWER`)

Sistem memisahkan 4 entitas secara eksplisit pada setiap sesi dan transaksi:
- **`cashier_id`** -> Identitas kasir (`users.id`) yang melakukan login PIN dan melayani transaksi.
- **`terminal_id`** -> Identitas perangkat terminal (`paired_terminals.terminal_id`, atau `'ADMIN'` bila transaksi dilakukan di perangkat Admin).
- **`shift_id`** -> Identitas sesi shift (`shifts.id`) yang sedang dibuka.
- **`cash_register_id`** -> Identitas laci kas fisik/logis (`cash_registers.id`, contoh: `REG-MAIN` untuk laci utama atau `REG-S1`, `REG-S2` untuk laci terpisah).

### 2.1. Dua Mode Operasional (Dikonfigurasi Admin via `store_settings.drawer_mode`)

| Aspek | Mode 1: `SHARED_DRAWER` (Laci Bersama) | Mode 2: `INDIVIDUAL_DRAWER` (Laci Per Kasir / Terminal) |
| :--- | :--- | :--- |
| **Konsep Fisik** | Beberapa kasir/terminal berbagi 1 laci kas utama (mis. `REG-MAIN`) | Setiap kasir/terminal memiliki laci kas masing-masing (`REG-01`, `REG-02`, dst.) |
| **Aturan Buka Shift** | Maksimal **1 shift `'open'`** pada `cash_register_id` bersama tersebut (`REG-MAIN`). Biasanya dibuka oleh Admin/Supervisor atau kasir yang berwenang | **Batasan 1 shift terbuka global DIHAPUS.** Diperbolehkan **multiple shift `'open'` paralel**, dengan syarat maksimal **1 shift `'open'` per `cash_register_id`** DAN **maksimal 1 shift `'open'` aktif per `cashier_id`** |
| **Pelacakan Transaksi** | Semua transaksi terminal masuk ke `shift_id` & `cash_register_id` bersama, namun **`cashier_id` dan `terminal_id` tetap terpisah per transaksi** | Setiap transaksi masuk ke `shift_id` dan `cash_register_id` milik kasir/terminal tersebut, plus `cashier_id` & `terminal_id` |
| **Tutup Shift (Blind Cash Count)** | Ditutup 1 kali untuk laci bersama tersebut; laporan tetap bisa memecah omzet per kasir & per terminal | Setiap kasir menutup shift & menghitung uang fisik laci masing-masing secara independen |
| **Kompatibilitas Data Lama** | Transaksi & shift lama otomatis dipetakan ke `terminal_id = 'ADMIN'`, `cash_register_id = 1` (`REG-MAIN`) | Tetap kompatibel penuh; shift historis tetap terbaca pada laporan |

### 2.2. Aturan Konteks Shift di POS Staff
- Saat kasir berhasil login PIN di POS Staff, Admin mengevaluasi `drawer_mode`:
  - Jika `SHARED_DRAWER`: Admin mencocokkan terminal ke `cash_register_id` laci bersama (atau laci yang ditetapkan pada terminal tersebut), lalu mengembalikan shift `'open'` pada laci tersebut. Jika belum dibuka, status Staff menjadi `ONLINE_SHIFT_CLOSED`.
  - Jika `INDIVIDUAL_DRAWER`: Admin memeriksa apakah kasir tersebut sudah punya shift `'open'` pada laci miliknya/terminalnya. Jika belum ada, POS Staff menampilkan layar **Buka Shift Laci Kasir** (bila kasir diizinkan buka shift dan memilih/terikat ke `cash_register_id` miliknya) sebelum dapat melakukan checkout.

---

## 3. Arsitektur Keamanan Komunikasi & Kredensial

Semua komunikasi produksi antar-perangkat wajib menerapkan **defense-in-depth**:

1. **HTTPS dengan Sertifikat TLS yang Dikelola Admin:**
   - Saat pertama kali mode server multi-kasir diaktifkan di POS Admin, Admin menghasilkan pasangan kunci ECDSA P-256 / RSA-2048 dan sertifikat X.509 self-signed lokal (`SAN` mencakup IP LAN/Hotspot aktif dan `server_id`).
   - **Isolasi Keystore terhadap Backup (`BackupService`):** Private key TLS, PIN pepper, dan master Key-Encryption-Key (`KEK`) AES-GCM untuk membungkus `device_secret_enc` wajib disimpan eksklusif di **Android Keystore / `flutter_secure_storage`**, **tidak pernah** di dalam file `kasirtoko.db`, sehingga fitur ekspor backup DB (`BackupService.createAndShareBackup`) ke Google Drive atau WhatsApp tidak membocorkan secret perangkat atau kunci TLS.
   - HTTP polos **ditolak** pada jalur komunikasi produksi (WSS dipakai untuk WebSocket).
2. **Certificate Pinning via QR Pairing & Rotasi Sertifikat:**
   - QR Code Pairing membawa **`cert_sha256`** (SHA-256 SPKI/DER fingerprint sertifikat TLS Admin).
   - POS Staff menyimpan `cert_sha256` di `flutter_secure_storage` dan menerapkannya pada `SecurityContext` / `badCertificateCallback` di `LanHttpClient` & `LanWsClient`. Jika ada sertifikat lain (MITM/ARP spoofing) di Wi-Fi yang sama, koneksi langsung diputus!
   - *(Untuk pairing IP Manual, pengguna wajib memverifikasi 6–8 karakter checksum fingerprint sertifikat yang tampil di layar Admin bersama IP & kode pairing).*
   - Mendukung rotasi `device_token`/`device_secret` (`POST /api/v1/pairing/rotate-secret`) serta pembaruan pin sertifikat TLS terkelola (`GET /api/v1/security/cert-info`).
3. **Device Token & Secret yang Dapat Dicabut:**
   - Hasil `POST /api/v1/pairing/register` menghasilkan `terminal_id`, `device_token` (disimpan SHA-256 hash-nya di `paired_terminals`), dan `device_secret` (256-bit random key untuk HMAC signing, dienkripsi via Android Keystore KEK di Admin).
   - Admin dapat me-revoke terminal kapan saja -> langsung menolak seluruh request REST & menutup koneksi WSS dengan event `terminal_revoked`.
4. **HMAC Request Signing + Timestamp & Nonce (Anti-Replay + Kalibrasi Jam Offline):**
   - Setiap request terautentikasi wajib menyertakan:
     - `X-Request-Timestamp`: epoch milliseconds terkalibrasi `clock_offset_ms = server_time_ms - local_time_ms` dari `GET /api/v1/health` (penting karena jaringan Wi-Fi/Hotspot lokal sering tanpa internet/NTP). Admin menolak selisih `> ±120 detik` (`401 REPLAY_TIMESTAMP_EXPIRED`).
     - `X-Request-Nonce`: UUID v4. Admin menyimpan nonce di in-memory sliding window cache selama `150 detik`; nonce berulang langsung ditolak (`401 REPLAY_NONCE_DETECTED`).
     - `X-Signature`: `HMAC-SHA256(device_secret, "$method\n$pathWithQuery\n$timestamp\n$nonce\n$bodySha256Hex")`.
5. **Cashier Session Token Berbatas Waktu & Revocable:**
   - Login PIN menghasilkan `session_token` acak kriptografis (256-bit, disimpan hash-nya di tabel `terminal_sessions` Admin dengan `expires_at`, mis. 12 jam).
   - Session otomatis dicabut bila: kasir logout/switch cashier, token expired, Admin me-nonaktifkan user, Admin me-revoke terminal, hak akses user diubah Admin, atau shift terkait ditutup.
6. **Upgrade Standar Hashing PIN (Migrasi Progresif) & Rate Limiting:**
   - Mengatasi hasil audit `SecurityHelper` (yang sebelumnya hanya custom HMAC 1000 iterasi + salt bersama), hashing kredensial di Admin ditingkatkan ke **KDF standar kuat** (Argon2id atau PBKDF2-HMAC-SHA256 `>= 210.000` iterasi dengan format PHC), **salt unik terpisah** (`pin_salt` vs `password_salt`), domain separation, dan server pepper di Keystore Admin.
   - **Migrasi Akun Aman:** Verifier `legacy_v1` tetap dipertahankan sementara untuk membaca akun v4 saat login pertama kali lalu otomatis melakukan *transparent re-hash* ke KDF `v2` (tanpa mengunci akun lama).
   - Endpoint PIN login mewajibkan `user_id` terpilih dari `GET /api/v1/auth/cashiers` (verifikasi `O(1)`, bebas timing leak) dan menerapkan **rate limit & progressive lockout** per `terminal_id` dan per `user_id`.

---

## 4. Kebijakan & Mekanisme Cash Drawer, Print Server, & Lifecycle Android

### 4.1. Enam Aturan Keras Cash Drawer
1. **Hanya Pembayaran Tunai Sukses:** Pembukaan laci otomatis **hanya** dipicu apabila `transaction.payment_method == 'tunai'` dan status transaksi di DB `'completed'`.
2. **Non-Tunai Dilarang Membuka Laci:** `qris`, `transfer`, `kasbon`, atau `saldo_kredit` **tidak pernah** mengirim pulse pembukaan laci.
3. **Permission Kasir Wajib:** Role/user kasir wajib memiliki izin **`AppPermissions.openCashDrawer`** untuk aksi buka laci manual.
4. **Kontrol Per Terminal oleh Admin:** `paired_terminals` menyimpan flag terpisah `allow_auto_open_drawer` (`0`/`1`) dan `allow_manual_open_drawer` (`0`/`1`).
5. **Audit Log Wajib untuk Buka Manual:** `POST /api/v1/printers/open-drawer` wajib menyertakan `reason` dan menulis `audit_logs` (`action_type = 'buka_laci'`, `user_id`, `terminal_id`, `cash_register_id`, `shift_id`).
6. **Strict Post-Commit & Single-Shot Guard (`drawer_pulse_sent`):**
   - Pulse `[0x1B, 0x70, 0x00, 0x19, 0xFA]` **hanya** dieksekusi setelah `db.transaction` transaksi commit.
   - Pulse laci **dipisahkan dari buffer salinan cetak / retry** lewat kolom `print_jobs.drawer_pulse_sent` (`0 -> 1`). Pada `copyCount > 1`, retry job cetak gagal, atau `is_reprint == true`, perintah laci **tidak pernah dikirim ulang** (anti double-open).
   - Kegagalan print (`failed`, `usb_permission_required`) **tidak pernah membatalkan transaksi** yang sudah sah tersimpan di DB.

### 4.2. Lifecycle Android Server pada POS Admin (`targetSdk = 36` / Android 5–16)
Flutter `3.47.5` mengompilasi dengan `compileSdk = 36` dan `targetSdk = 36` (Android 16), sehingga Foreground Service Server Admin wajib memenuhi aturan OS terbaru:
1. **Deklarasi Manifest & FGS Type:**
   - Tambahkan `FOREGROUND_SERVICE`, `POST_NOTIFICATIONS` (runtime permission Android 13+), `WAKE_LOCK`, dan hindari `foregroundServiceType="dataSync"` sebagai satu-satunya tipe karena **Android 15+ membatasi `dataSync` maks 6 jam/24 jam**! Gunakan **`connectedDevice`** (`FOREGROUND_SERVICE_CONNECTED_DEVICE`, sesuai pengendalian printer BT/USB/LAN lokal) dan/atau **`specialUse`** (`FOREGROUND_SERVICE_SPECIAL_USE` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`) agar server dapat beroperasi sepanjang jam operasional toko tanpa diputus OS setelah 6 jam.
2. **Isolasi Lifecycle Engine & Jaringan:**
   - Jalankan server terikat pada Android `Service` (menjaga `FlutterEngine` server tetap hidup meski Activity di-minimize atau di-swipe dari Recents `onTaskRemoved`, hingga Admin menekan **Stop Server**).
   - Daftarkan `ConnectivityManager.NetworkCallback` untuk mendeteksi pergantian Wi-Fi <-> Hotspot Android atau perubahan IP LAN secara otomatis, lalu melakukan re-bind / memperbarui QR IP Admin tanpa crash.
   - Pasca perangkat restart (`BOOT_COMPLETED`), karena Android 12–16 membatasi start FGS langsung dari background boot, Admin menampilkan notifikasi persisten untuk satu ketukan mengaktifkan ulang server (atau auto-start saat aplikasi Admin dibuka kasir/owner).

---

## 5. Koneksi Terputus, Admin Mati, & Idempotensi Transaksi

State machine di `ConnectionProvider` (`stafkasirtoko`):
- `UNPAIRED` -> belum pairing.
- `CONNECTING` -> inisialisasi / reconnect HTTPS & WSS.
- `ONLINE_READY` -> heartbeat WSS sehat, server Admin aktif, dan shift untuk `cash_register_id` kasir berstatus `'open'`.
- `ONLINE_SHIFT_CLOSED` -> server Admin aktif, tetapi belum ada shift `'open'` untuk mode/laci kasir (atau kasir belum buka shift di mode `INDIVIDUAL_DRAWER`). Tombol Bayar dinonaktifkan; keranjang & hold order lokal tetap dapat digunakan.
- `OFFLINE_ADMIN_UNREACHABLE` -> Wi-Fi/Hotspot terputus atau POS Admin mati (`2x` heartbeat gagal `~9s` atau event WS `server_stopping`). Seluruh transaksi baru **dihentikan sementara (hard-lock tombol Bayar)**; keranjang aktif di `active_cart` & `local_held_orders` (SQLite lokal) tetap utuh 100%.
- `RECOVERING_INFLIGHT` -> koneksi baru pulih dan ditemukan baris di `pending_checkout_intents`.

### Alur Idempotensi Checkout (Mencegah Transaksi & Pengurangan Stok Ganda)
1. Sebelum mengirim `POST /api/v1/transactions`, Staff membuat `idempotency_key` (UUID v4) dan menyimpannya ke `pending_checkout_intents` lokal (`state = 'submitting'`).
2. Staff **tidak pernah** menganggap transaksi berhasil sampai menerima respons `201 Created` / `200 OK` yang sah dari Admin.
3. Jika koneksi putus/timeout sebelum respons diterima:
   - Intent berubah menjadi `state = 'awaiting_reconciliation'`, state koneksi menjadi `OFFLINE_ADMIN_UNREACHABLE`.
   - Saat koneksi pulih, `CheckoutRepository` wajib memanggil **`GET /api/v1/transactions/by-idempotency/{key}`** **sebelum** mengizinkan retry maupun transaksi baru:
     - **Ditemukan (`200 OK`):** Admin ternyata sudah meng-commit transaksi! Staff mengosongkan keranjang, menyimpan salinan struk ke `recent_receipt_cache`, menghapus intent, dan menampilkan `ReceiptDialog`.
     - **Tidak ditemukan (`404 NOT_FOUND`):** Admin belum pernah menyimpan transaksi tersebut. Intent dibersihkan / diubah ke `aborted`, keranjang **dipertahankan utuh**, dan kasir dapat menekan Bayar ulang dengan `idempotency_key` baru setelah sinkronisasi ulang stok & harga.

---

## 6. Struktur Proyek POS Staff (`stafkasirtoko`) yang Direkomendasikan

```text
stafkasirtoko/
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml
│       └── res/xml/network_security_config.xml
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── constants/        # api_endpoints.dart, app_constants.dart
│   │   ├── network/          # lan_http_client.dart (TLS pinning + HMAC), lan_ws_client.dart
│   │   ├── security/         # secure_credential_store.dart, request_signer.dart
│   │   ├── theme/            # app_theme.dart (serasi kasirtoko)
│   │   └── utils/            # barcode_scan_guard.dart, currency_format.dart, date_format.dart, quick_cash_helper.dart
│   ├── data/
│   │   ├── local/            # staff_local_db.dart + DAOs (cache produk, active_cart, held_orders, intents, recent_receipts)
│   │   ├── remote/           # pairing_api.dart, auth_api.dart, catalog_api.dart, shift_api.dart, transaction_api.dart, printer_api.dart
│   │   └── repositories/     # session_repository.dart, catalog_repository.dart, shift_repository.dart, checkout_repository.dart
│   ├── domain/
│   │   ├── enums/            # connection_status.dart, drawer_mode.dart, checkout_intent_state.dart
│   │   └── models/           # pairing_profile.dart, cashier_session.dart, cash_register.dart, shift_context.dart, staff_product.dart, ...
│   └── presentation/
│       ├── providers/        # connection_provider.dart, pairing_provider.dart, auth_session_provider.dart, shift_provider.dart, catalog_provider.dart, cart_provider.dart, checkout_provider.dart, print_job_provider.dart
│       ├── screens/          # pairing_screen, qr_pairing_scanner, pin_login_screen, staff_shift_screen, staff_pos_screen, payment_dialog, receipt_dialog, terminal_receipts_screen, connection_status_screen
│       └── widgets/          # connection_status_banner.dart, offline_lock_overlay.dart, quantity_stepper.dart
├── test/
└── .github/workflows/build.yml
```
