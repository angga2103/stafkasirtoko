# Arsitektur Operasional Final Sistem POS Multi-Device KasirToko

Dokumen ini mendokumentasikan arsitektur operasional final untuk **KasirToko Admin** (`com.kasirtoko.app.kasirtoko`) dan **KasirToko Staff** (`com.kasirtoko.app.stafkasirtoko`) pada topologi toko nyata: **satu HP Android khusus milik toko sebagai server/database utama** dan **HP pribadi karyawan sebagai terminal POS Staff**.

## 1. Topologi & Pembagian Peran Perangkat

1. **KasirToko Admin (Dedicated Store Server — Sumber Kebenaran Tunggal)**
   - Menyimpan database SQLite utama (`kasirtoko.db`, **schema v7**) dengan mode `WAL`, `PRAGMA foreign_keys = ON`, dan `busy_timeout = 5000 ms`.
   - Menjalankan `LanPosServer` (HTTPS + WSS di port `8443` dengan TLS self-signed certificate pinning SHA-256) serta `LanDiscoveryResponder` (UDP port `45843`).
   - Menjalankan Android Foreground Service bertipe `specialUse` (`PosServerForegroundService` + `ServerBootReceiver` + `server_lifecycle_bridge.dart`) untuk menjaga prioritas eksekusi server lokal tetap tinggi tanpa mengklaim kebal mutlak terhadap penghentian OS/OEM.
   - Mengeksekusi seluruh validasi stok, perhitungan promo/harga bertingkat, otoritas shift & laci kas (`SHARED_DRAWER` / `INDIVIDUAL_DRAWER`), transaksi atomik `AuthoritativeCheckoutService`, antrean cetak serial `PrintQueueWorker`, dan sistem backup terenkripsi `BackupService` (`.ktbak` AES-256-GCM).

2. **KasirToko Staff (Personal Employee Terminals — Cache-Only Client)**
   - Berjalan di HP pribadi karyawan dengan `StaffLocalDb` hanya menyimpan cache katalog produk tanpa `cost_price`/data HPP/stok gudang karantina (`quarantine_stock`/`damaged_stock`), keranjang lokal aktif (`active_cart_items`), draft hold (`local_held_orders`), intent checkout idempoten (`pending_checkout_intents`), dan maksimal 30 struk terakhir terminal (`recent_receipt_cache`).
   - Tidak pernah memiliki database pusat kedua dan tidak pernah memfinalisasi transaksi secara offline (`StaffSessionController.canSubmitCheckout` mengunci checkout saat terputus dari Admin).
   - Kredensial terminal (`device_token`, `device_secret`, `tls_cert_sha256`, `session_token`, `server_id`, `primary_server_url`, `backup_server_url`) disimpan via `AndroidKeystoreCredentialStore` (AES-GCM Keystore pada Android).

## 2. Identitas Server Permanen (`server_id`) & Keamanan Lintas-Jaringan

- Database Admin menyimpan `server_id` permanen (`SRV-<uuid>`) pada tabel `store_settings` (`key = 'server_id'`), dibaca melalui `DatabaseHelper.getOrCreateServerId()` / `getOrCreateServerIdTxn()`.
- `server_id` selalu disertakan di QR pairing v2 (`PosServerProvider.createPairingBanner`), `/api/v1/health`, `/api/v1/pairing/register`, `/api/v1/auth/pin-login`, `/api/v1/auth/me`, `/api/v1/store/bootstrap`, frame WebSocket `hello`/`pong`, header file backup `.ktbak`, serta paket respons UDP `KASIRTOKO_HERE`.
- POS Staff menyimpan `server_id` dan **menolak otomatis** endpoint mana pun (router, hotspot cadangan, maupun hasil UDP discovery) yang tidak cocok dengan `server_id` atau tidak lolos verifikasi SHA-256 DER sertifikat TLS (`LanHttpClient.checkHealthVerified`).

## 3. Skema Database Admin v7 (`db_helper.dart`)

Migrasi non-destruktif v6 -> v7 membuat backup pra-migrasi terverifikasi (`*_pre_v7_backup.db`) dengan `PRAGMA integrity_check == 'ok'`, mempertahankan data lama, dan menambahkan:
- Kolom `users.max_active_sessions` (nullable override per akun).
- Kolom metadata `terminal_sessions`: `device_name`, `revoked_reason`, `revoked_by`, `last_seen_at`, serta index `idx_terminal_sessions_cashier_active`.
- Tabel `session_policies` (batas sesi aktif default per role yang dapat diubah Admin).
- Tabel `server_network_endpoints` (profil `primary_router` dan `backup_hotspot`).
- Tabel `backup_jobs` (`hourly_snapshot` interval 60 menit & `nightly_full` default 23:30) dan `backup_artifacts` (riwayat `.ktbak`, ukuran, dual SHA-256, status verifikasi test-restore).
- Entri `store_settings` `'server_id'`.

## 4. Transaksi, Shift, Laci Kas & Printer

- **Mode Laci (`DrawerMode`):** `SHARED_DRAWER` (shift terpusat laci bersama pada mesin kasir bersama) dan `INDIVIDUAL_DRAWER` (shift per kasir/laci). Pencabutan sesi atau penonaktifan karyawan **tidak** otomatis menutup shift bersama yang masih terbuka.
- **Idempotency & Rekonsiliasi:** POS Staff menyimpan `PendingCheckoutIntent` di SQLite lokal sebelum `POST /api/v1/transactions` dengan `X-Idempotency-Key`. Jika jaringan terputus di tengah pengiriman, keranjang tetap utuh dan saat koneksi pulih Staff memeriksa `GET /api/v1/transactions/by-idempotency/<key>` untuk mencegah pengisian ganda.
- **Printer:** Seluruh perintah cetak masuk ke antrean `print_jobs` pada Admin (`PrintQueueWorker`) dan dapat dicetak ulang secara aman via endpoint idempoten.

## 5. Keterbatasan Teknis Nyata yang Didokumentasikan Secara Jujur

1. Android tidak menjamin proses latar belakang hidup selamanya pada semua vendor OEM; pengoptimalan baterai harus dinonaktifkan pada HP server dan operator tetap disarankan menjaga daya/jaringan.
2. Banyak perangkat Android tidak mendukung Wi-Fi client + Hotspot aktif bersamaan secara stabil; failover ke Hotspot HP Admin menggunakan prosedur manual yang sederhana namun terotomatisasi di sisi endpoint discovery Staff (lihat `NETWORK_FAILOVER_GUIDE.md`).
3. Remote wipe penuh terhadap perangkat karyawan pribadi yang sedang offline **tidak dapat dijamin 100%** jika perangkat tidak pernah terhubung kembali atau sudah dimatikan sebelum token dicabut; mitigasi utama tetap pembatasan data sensitif di Staff dan pencabutan kredensial instan di Admin (lihat `LOST_DEVICE_RESPONSE_GUIDE.md`).
