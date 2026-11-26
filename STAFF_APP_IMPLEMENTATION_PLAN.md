# STAFF_APP_IMPLEMENTATION_PLAN.md — Rencana Implementasi & Urutan Kerja Antar-Repository

**Status:** Rencana Final — Menunggu Persetujuan Pemilik Proyek sebelum Coding, Migrasi DB, atau Build APK.

---

## 1. Daftar Perubahan yang Diperlukan di POS Admin (`kasirtoko`)

Seluruh perubahan di `kasirtoko` bersifat **non-destruktif** dan mempertahankan 100% fitur offline single-device yang sudah ada:

1. **Perbaikan Keamanan (`lib/utils/security_helper.dart`, `auth_provider.dart`, `db_helper.dart`):**
   - Upgrade algoritma hashing password & PIN dari custom HMAC 1000 iterasi ke KDF standar kuat (**PBKDF2-HMAC-SHA256 >= 210.000 iterasi** atau **Argon2id**) dengan format PHC (`hash_version`), **salt terpisah** (`pin_salt` vs `password_salt`), domain separation, dan keystore pepper.
   - Tambahkan *transparent re-hash on login* untuk akun lama v4 (verifier `legacy_v1` tetap dijaga selama fase migrasi akun aktif sebelum dihapus) dan bersihkan fallback plaintext `pin`.
   - Simpan TLS private key, PIN pepper, dan master KEK AES-GCM (`device_secret_enc`) eksklusif di **Android Keystore** agar ekspor `BackupService` tidak membocorkan secret.
   - Tambahkan **rate limiting & progressive lockout** (`failed_pin_count`, `pin_locked_until`) + wajibkan `user_id` di endpoint PIN agar verifikasi berjalan `O(1)`.
   - Tambahkan permission baru `AppPermissions.openCashDrawer` di `lib/models/user.dart`.
2. **Refactor Shift & Cash Register (`db_helper.dart`, `shift.dart`, `cash_flow_provider.dart`, `shift_screen.dart`, `settings_screen.dart`):**
   - Tambah model & tabel `cash_registers`, `cash_register_assignments`, dan setting `drawer_mode` (`SHARED_DRAWER` vs `INDIVIDUAL_DRAWER`).
   - Refactor `openShift()` dan `getCurrentOpenShift()` agar mendukung paralelisme `INDIVIDUAL_DRAWER` (dengan partial unique index per `cash_register_id` & per `cashier_id`) sambil menjaga kompatibilitas mode `SHARED_DRAWER` dan data lama; perbaiki `getShiftStats` agar fallback `shift_id IS NULL` tidak bocor lintas shift di `INDIVIDUAL_DRAWER`.
   - Perbarui `insertTransaction()` agar wajib mencatat `cashier_id`, `terminal_id`, `shift_id`, `cash_register_id`, serta `idempotency_key` (menghindari duplikasi & stok ganda).
   - Perbaiki `PosProvider.checkout()` agar field `creditUsed` ikut terbawa pada objek kembalian `savedTrx`.
3. **Migrasi DB v4 -> v5 Non-Destruktif (`db_helper.dart`):**
   - Checkpoint WAL lalu buat backup otomatis `kasirtoko_pre_v5_backup.db` + **verifikasi integritas backup** (`PRAGMA integrity_check`) sebelum upgrade.
   - Aktifkan `PRAGMA journal_mode = WAL;`, `PRAGMA busy_timeout = 5000;`, dan `PRAGMA foreign_keys = ON;` (di `onConfigure`, tanpa menambah FK retroaktif yang mematahkan data legacy dengan `customer_id`/`user_id = 0` orphan).
   - Tambah tabel `cash_registers`, `cash_register_assignments`, `paired_terminals`, `terminal_sessions`, `print_jobs` (`drawer_pulse_sent`), dan kolom baru pada `users`, `shifts`, `transactions`, `cash_flows`, `products` + backfill data lama.
   - Tambah unit test migrasi dari snapshot DB v4 (dan v1–v3) ke v5.
4. **Embedded HTTPS + WSS Server, Print Queue, & Lifecycle Android (`services/server/`, `MainActivity.kt`):**
   - Generator/manager sertifikat X.509 self-signed lokal + exporter SHA-256 fingerprint + dukungan rotasi secret/cert.
   - Embedded HTTPS + WSS server (`dart:io` `HttpServer.bindSecure` + `WebSocketTransformer`) dengan anti-replay & HMAC verifier, delta sync produk termasuk `is_active = 0` tombstones.
   - Serial FIFO worker `print_jobs` yang memisahkan pulse `cashDrawerPulse` dari loop `copyCount` & retry (`drawer_pulse_sent`), serta menangani status USB OTG (`USB_PERMISSION_REQUIRED`).
   - Android Foreground Service (`connectedDevice`/`specialUse` kompatibel `targetSdk = 36`, `POST_NOTIFICATIONS`, `NetworkCallback` untuk Wi-Fi↔Hotspot/perubahan IP, engine bertahan saat Recents/Doze).
5. **UI Manajemen Multi-Kasir di Admin:**
   - Layar kontrol Server Multi-Kasir (start/stop server, IP Wi-Fi/Hotspot terdeteksi otomatis, generator QR Pairing & kode 6 digit).
   - Manajemen Laci Kas (`cash_registers`), pemilihan `drawer_mode` (`SHARED_DRAWER` / `INDIVIDUAL_DRAWER`), daftar terminal ter-pairing tanpa batas jumlah (assign laci, toggle `allow_auto_open_drawer`, `allow_manual_open_drawer`, tombol **Revoke**).

---

## 2. Daftar Pekerjaan yang Diperlukan di POS Staff (`stafkasirtoko`)

1. **Bootstrap Proyek & Fondasi:**
   - Inisialisasi proyek Flutter (`Dart ^3.13.4`, `minSdk 21`), git remote `stafkasirtoko`, dependensi (`provider`, `sqflite`, `flutter_secure_storage`, `mobile_scanner`, `qr_flutter`, `intl`, `uuid`, `crypto`), `AppTheme` serasi `kasirtoko`, `network_security_config.xml`.
2. **Lapisan Jaringan & Keamanan (`core/network/`, `core/security/`):**
   - `LanHttpClient` dengan **TLS Certificate Pinning** (`cert_sha256` dari QR Pairing), **HMAC Request Signing**, `X-Request-Timestamp`, `X-Request-Nonce`, dan `X-Idempotency-Key`.
   - `LanWsClient` (WSS dengan certificate pinning, auto-reconnect backoff, heartbeat `ping`/`pong` 4s).
   - `SecureCredentialStore` (`flutter_secure_storage` Android Keystore).
3. **Database Lokal Cache & Persistensi Keranjang (`data/local/`):**
   - Implementasi `staff_terminal.db` v1 (`pairing_profile`, `cached_products` tanpa `cost_price`, `cached_product_units`, `cached_tiered_prices`, `cached_promos`, `cached_customers`, `active_cart*`, `local_held_orders*`, `pending_checkout_intents`, `recent_receipt_cache`).
4. **Alur Pairing, Auth PIN, & Shift (`presentation/`):**
   - `PairingScreen` + `QrPairingScannerScreen` + input IP Manual dengan verifikasi checksum sertifikat.
   - `PinLoginScreen`: pilih kasir aktif -> masukkan PIN -> simpan `session_token` & `permissions`.
   - `StaffShiftScreen`: tampilkan status shift saat `SHARED_DRAWER`, dan fitur **Buka/Tutup Shift Laci Individu** saat `INDIVIDUAL_DRAWER`.
5. **Terminal POS Kasir, Idempotensi, & Offline Guard:**
   - `StaffPosScreen` responsif (HP & Tablet), `BarcodeScanGuard` + kamera/scanner eksternal, multi-satuan, harga bertingkat, promo preview.
   - `ConnectionProvider` state machine + `OfflineLockOverlay` / banner status (keranjang tetap aman di SQLite saat offline/Admin mati, tombol Bayar ditahan total).
   - `CheckoutProvider`: simpan `pending_checkout_intents` sebelum `POST /transactions`, otomatis rekonsiliasi `GET /by-idempotency/{key}` saat koneksi pulih pasca-timeout.
6. **Cetak Struk, Cash Drawer Terkontrol, & CI/CD APK:**
   - `ReceiptDialog` & `PrintJobProvider`: pratinjau struk resmi + QR nota, kirim `POST /print/receipt`, pantau status cetak via WSS, tombol **Buka Laci Manual** (hanya muncul jika `allow_manual_open_drawer` & permission `open_cash_drawer` aktif, dengan input alasan untuk audit log).
   - `TerminalReceiptsScreen` (maks 30 struk terakhir terkonfirmasi server untuk reprint).
   - Setup release keystore `.jks` dan `.github/workflows/build.yml` untuk build APK setelah seluruh pengujian lulus.

---

## 3. Urutan Implementasi & Dependensi Antar-Repository

```text
[Tahap 1: kasirtoko] SecurityHelper Upgrade + DB v5 Migration + Shift/CashRegister Refactor + Migration Tests
         |
         v
[Tahap 2: kasirtoko] TLS Cert Mgr + Embedded HTTPS/WSS Server + Pairing/Auth/Catalog/Shift/Tx/Print Endpoints + Foreground Service
         |  \
         |   +--------------------------------------------+
         v                                                | (Kontrak API & Server Uji siap)
[Tahap 3: stafkasirtoko] Bootstrap + SecureStore + TLS Pinning & HMAC Client + WSS Heartbeat + Pairing & PIN Login
         |
         v
[Tahap 4: stafkasirtoko] SQLite Cache & Persistent Cart + Barcode/POS UI + Individual/Shared Shift Flow
         |
         v
[Tahap 5: stafkasirtoko] Idempotent Checkout + Offline/Admin-Down Lock + In-Flight Reconciliation + Print/Drawer Flow
         |
         v
[Tahap 6: Dual-Repo Integration] Contract Tests + Migration Tests + Capacity/Stress Benchmark + Field Tests + Release Signing & Build APK
```

### Rincian Urutan & Ketergantungan
1. **Milestone M1 (`kasirtoko` Core & DB v5):** Tidak bergantung pada `stafkasirtoko`. Harus selesai dan lulus unit + migration test v4->v5 terlebih dahulu agar struktur DB, KDF PIN, dan logika `SHARED_DRAWER`/`INDIVIDUAL_DRAWER` stabil.
2. **Milestone M2 (`kasirtoko` HTTPS/WSS Server & UI Pairing):** Bergantung pada M1. Menghasilkan server nyata di HP Admin yang siap diuji dengan `curl`/test suite. *(Opsional: Tahap awal `stafkasirtoko` M3a — skeleton, `staff_terminal.db`, `CartProvider`, dan `RequestSigner` — dapat dikerjakan paralel terhadap mock server, namun integrasi akhir M3b–M5 bergantung pada M2).*
3. **Milestone M3 (`stafkasirtoko` Pairing, TLS Pinning, PIN Login, & Shift Context):** Bergantung pada M2 endpoint `/health`, `/pairing/*`, `/auth/*`, `/shifts/*`, `/cash-registers`.
4. **Milestone M4 (`stafkasirtoko` Katalog Cache, POS UI, & Checkout Idempoten):** Bergantung pada M2 endpoint `/catalog/*`, `/customers/*`, `/transactions/*`.
5. **Milestone M5 (`stafkasirtoko` Print Queue & Cash Drawer):** Bergantung pada M2 endpoint `/printers/*`, `/print/*`, dan event WSS `print_job_updated`.
6. **Milestone M6 (QA Terintegrasi, Capacity Test, & Build APK):** Bergantung pada M1–M5. Kedua APK (Admin v2.3.0 & Staff v1.0.0) diuji bersama pada router Wi-Fi, hotspot Android, dan printer thermal nyata sebelum build release APK ditandatangani.
