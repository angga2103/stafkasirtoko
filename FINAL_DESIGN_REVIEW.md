# FINAL_DESIGN_REVIEW.md — Pemeriksaan Konsistensi Desain Akhir POS Multi-Device (`kasirtoko` & `stafkasirtoko`)

**Tanggal Review:** 26 November 2026  
**Status Gate:** Pra-Tahap 1 (`kasirtoko`) — Belum ada coding, belum ada migrasi DB, belum ada build APK.  
**Objek Review:** 6 dokumen desain di `c:\StafKasirtoko` beserta verifikasi silang terhadap codebase nyata `c:\kasirtoko` (`327b1ab`), `Flutter 3.47.5` (`compileSdkVersion = 36`, `targetSdkVersion = 36`), dan `Dart 3.13.4`.

---

## Ringkasan Eksekutif & Verdict Kelayakan Tahap 1

Selama pemeriksaan konsistensi akhir terhadap kode aktual `c:\kasirtoko`, ditemukan **7 Temuan Kritis**, **5 Temuan Mayor**, dan **2 Temuan Minor** yang berpotensi menyebabkan kegagalan migrasi data lama, kebocoran secret lewat backup DB, pembukaan laci kas ganda saat retry cetak, crash Foreground Service pada Android 14–16 (`targetSdk = 36`), maupun kontaminasi statistik shift pada mode `INDIVIDUAL_DRAWER`.

Seluruh solusi atas temuan tersebut **telah diperbarui dan dikunci ke dalam keenam dokumen desain** ([STAFF_APP_AUDIT.md](file:///c:/StafKasirtoko/STAFF_APP_AUDIT.md), [STAFF_APP_ARCHITECTURE.md](file:///c:/StafKasirtoko/STAFF_APP_ARCHITECTURE.md), [ADMIN_STAFF_API_CONTRACT.md](file:///c:/StafKasirtoko/ADMIN_STAFF_API_CONTRACT.md), [STAFF_APP_DATABASE_DESIGN.md](file:///c:/StafKasirtoko/STAFF_APP_DATABASE_DESIGN.md), [STAFF_APP_IMPLEMENTATION_PLAN.md](file:///c:/StafKasirtoko/STAFF_APP_IMPLEMENTATION_PLAN.md), [STAFF_APP_TEST_PLAN.md](file:///c:/StafKasirtoko/STAFF_APP_TEST_PLAN.md)).

> **PERNYATAAN KELAYAKAN:** Dengan diterapkannya koreksi pada revisi dokumen ini serta konfirmasi atas **4 keputusan teknis kecil di Bagian 7.4**, arsitektur sistem **LAYAK MASUK TAHAP 1** pada repositori `kasirtoko`.

---

## 1. Validasi Shift dan Cash Drawer (`SHARED_DRAWER` & `INDIVIDUAL_DRAWER`)

### 1.1. Pembuktian Desain per Skenario

| Mode | Skenario Operasional | Mekanisme Desain & Bukti Kompatibilitas |
| :--- | :--- | :--- |
| **`SHARED_DRAWER`** | Banyak kasir (`cashier_id` berbeda, di Admin maupun Staff) bertransaksi dalam satu shift toko | `store_settings.drawer_mode = 'SHARED_DRAWER'`. Terminal menggunakan laci bersama `cash_register_id = 1` (`REG-MAIN`, `is_shared = 1`). Hanya ada 1 shift berstatus `'open'` pada `REG-MAIN`. Setiap `POST /api/v1/transactions` mewajibkan `shift_id` milik `REG-MAIN` tersebut sambil menyimpan `cashier_id` & `terminal_id` pengirim |
| **`SHARED_DRAWER`** | Satu laci kas memiliki maksimal satu shift aktif | Dijamin langsung di engine SQLite lewat **partial unique index** `idx_shifts_one_open_per_register ON shifts(cash_register_id) WHERE status = 'open'` |
| **`SHARED_DRAWER`** | Semua transaksi tercatat atas identitas kasir masing-masing & penutupan shift tidak menghilangkan keterkaitan | Setiap baris `transactions` menyimpan `(cashier_id, cashier_name, terminal_id, shift_id, cash_register_id)`. Ketika shift bersama ditutup (`status = 'closed'`), `transactions.shift_id` dan `cashier_id` tetap permanen dan tidak pernah diubah |
| **`INDIVIDUAL_DRAWER`** | Setiap laci dapat memiliki shift sendiri & penutupan satu shift tidak menutup shift kasir lain | Aturan global `WHERE status = 'open'` pada `DatabaseHelper.openShift()` dihapus. Setiap `cash_register_id` (`REG-S1`, `REG-S2`, `REG-MAIN`) boleh memiliki 1 shift `'open'` paralel. `closeShift(shiftId, ...)` hanya meng-update `WHERE id = ?` milik shift tersebut |
| **`INDIVIDUAL_DRAWER`** | Kasir hanya dapat menggunakan laci yang ditugaskan atau diizinkan | Tabel **`cash_register_assignments`** memetakan `(cash_register_id, terminal_id, cashier_id)`. Endpoint `POST /shifts/open`, `POST /transactions`, dan `POST /printers/open-drawer` memvalidasi hak akses terhadap `cash_register_id`; jika tidak berhak -> tolak `403 REGISTER_ACCESS_DENIED` |
| **`INDIVIDUAL_DRAWER`** | Tidak ada dua shift aktif yang bertentangan pada laci yang sama (atau 1 kasir pegang 2 laci aktif) | Engine SQLite menolak duplikasi atomik via 2 partial unique index: `idx_shifts_one_open_per_register` dan `idx_shifts_one_open_per_cashier_indiv` |
| **Legacy & Retur** | Query statistik shift tidak terkontaminasi baris `shift_id IS NULL` | **Temuan Kritis Ditemukan:** `DatabaseHelper.getShiftStats()` (`db_helper.dart` baris 3408) memakai fallback `OR (shift_id IS NULL AND date >= ? AND date <= ?)`. Pada mode `INDIVIDUAL_DRAWER`, transaksi lama tanpa `shift_id` akan masuk ke semua shift yang rentang waktunya beririsan! **Solusi:** Fallback `shift_id IS NULL` dibatasi hanya untuk `SHARED_DRAWER` pada `cash_register_id = 1` (dan seluruh transaksi v5 wajib memiliki `shift_id` non-null) |

### 1.2. Aturan Constraint Database yang Diperlukan (`kasirtoko.db` v5)
1. **`cash_registers`:** `id INTEGER PK`, `register_code TEXT NOT NULL UNIQUE`, `is_shared INTEGER NOT NULL DEFAULT 1`, `is_active INTEGER NOT NULL DEFAULT 1`. Seed wajib `id = 1` (`REG-MAIN`).
2. **`cash_register_assignments`:** `FOREIGN KEY (cash_register_id) REFERENCES cash_registers(id) ON DELETE CASCADE`, `UNIQUE (cash_register_id, terminal_id, cashier_id)`.
3. **`shifts`:**
   - `CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open_per_register ON shifts (cash_register_id) WHERE status = 'open';`
   - `CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open_per_cashier_indiv ON shifts (cashier_id) WHERE status = 'open' AND drawer_mode = 'INDIVIDUAL_DRAWER';`
4. **`transactions`:** `terminal_id TEXT NOT NULL DEFAULT 'ADMIN'`, `cash_register_id INTEGER NOT NULL DEFAULT 1`, `CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_idempotency ON transactions (idempotency_key) WHERE idempotency_key IS NOT NULL AND idempotency_key != '';`.

---

## 2. Validasi Migrasi Database (`v4 -> v5`)

| Aspek Uji / Validasi | Temuan dari Codebase `db_helper.dart` | Desain Final yang Ditetapkan |
| :--- | :--- | :--- |
| **Backup & Verifikasi Backup** | `db_helper.dart` baris 107–120 membuat `pre_v4_backup.db` dengan `dbFile.copy()` saja tanpa WAL checkpoint & tanpa cek integritas file | Sebelum `openDatabase(..., version: 5)`: checkpoint WAL (`PRAGMA wal_checkpoint(TRUNCATE)` jika `-wal` ada) -> copy ke `kasirtoko_pre_v5_backup.db` -> **verifikasi ukuran `> 0` & `PRAGMA integrity_check == 'ok'`** |
| **Foreign Key Safety** | `kasirtoko` v1–v4 belum pernah menyalakan `PRAGMA foreign_keys = ON`. Ada fungsi `deleteCustomer()` (baris 4069) dan `audit_logs` dengan `user_id = 0` (`auth_provider.dart` baris 287/310) | **Temuan Kritis:** Menyalakan FK retroaktif pada kolom legacy (`transactions.customer_id`, `audit_logs.user_id`) dapat memicu `FOREIGN KEY constraint failed` saat migrasi/update data lama! **Solusi:** Jangan tambah FK retroaktif ke tabel legacy; nyalakan `PRAGMA foreign_keys = ON` di `onConfigure` dan terapkan FK ketat hanya pada tabel baru v5 + tabel anak yang memang sudah punya FK |
| **Unique & Partial Unique Index** | `transactions.idempotency_key` belum ada; `shifts` belum punya index per laci | Tambah `idx_transactions_idempotency`, `idx_print_jobs_idempotency`, `idx_shifts_one_open_per_register`, `idx_shifts_one_open_per_cashier_indiv`. Sebelum membuat index `shifts`, cek defensif bila ada anomali data korup `>1` shift `'open'` di v4 |
| **WAL & `busy_timeout`** | Belum diaktifkan pada `openDatabase` di `db_helper.dart` | Set `PRAGMA journal_mode = WAL;` & `PRAGMA busy_timeout = 5000;` pada `onConfigure` (dan pertahankan `PRAGMA wal_checkpoint(FULL)` di `BackupService`) |
| **Backfill Data Lama Tidak Lengkap** | Transaksi v1/v2 bisa memiliki `shift_id IS NULL`; customer lama bisa terhapus; user v1 bisa punya legacy `pin` | Backfill defensif: `terminal_id = COALESCE(NULLIF(terminal_id, ''), 'ADMIN')`, `cash_register_id = COALESCE((SELECT cash_register_id FROM shifts WHERE id = transactions.shift_id), 1)`. Jangan mengarang `shift_id` palsu pada transaksi v1/v2 yang memang `NULL` |
| **Rollback & Recovery** | Jika `_onUpgrade` melempar exception di tengah jalan | SQLite `onUpgrade` berjalan dalam transaksi atomik (auto-rollback ke v4 jika gagal), ditambah fallback recovery otomatis dari `kasirtoko_pre_v5_backup.db` yang telah terverifikasi |
| **Kompatibilitas Restore** | `BackupService.restoreDatabase()` bisa me-restore file `.db` dari versi v1/v2/v3/v4 | `_onUpgrade` wajib mempertahankan jalur berurutan `oldVersion < 2`, `< 3`, `< 4`, `< 5` dan diuji migrasi bertahap dari fixture v4 (dan v1) menuju v5 |

---

## 3. Validasi Keamanan

| Aspek Keamanan | Status Desain & Solusi Terhadap Temuan Audit |
| :--- | :--- |
| **Migrasi Hash PIN Lama ke KDF Baru** | **Temuan Kritis:** Menghapus `SecurityHelper.verifySecret` lama (`legacy_v1`, 1000 iterasi HMAC) sekaligus saat v5 upgrade akan **mengunci seluruh akun lama** karena DB tidak menyimpan PIN plaintext untuk di-rehash! **Solusi:** Pertahankan verifier `legacy_v1` khusus untuk akun bertanda `hash_version = 'legacy_v1'`, lalu lakukan **transparent re-hash on login** ke KDF baru (`v2_pbkdf2` >= 210.000 iterasi / `v2_argon2id`) dan bersihkan `users.pin` plaintext |
| **Pemisahan Salt PIN & Password** | Kolom baru `users.pin_salt` terpisah total dari `users.password_salt`, ditambah domain separation (`"pin:"` vs `"pw:"`) & server pepper di Android Keystore |
| **Penyimpanan Secret Perangkat (Bahaya `BackupService`!)** | **Temuan Kritis:** `BackupService.createAndShareBackup()` (`backup_service.dart` baris 49–56) mengekspor `kasirtoko.db` ke WhatsApp / Google Drive! Menyimpan `device_secret` atau TLS private key di `kasirtoko.db` akan membocorkan seluruh secret. **Solusi:** TLS private key, PIN pepper, & Master Key-Encryption-Key (KEK AES-GCM) disimpan eksklusif di **Android Keystore**, sedangkan `paired_terminals.device_secret_enc` di SQLite terbungkus oleh KEK Keystore tersebut |
| **Rotasi Secret & Sertifikat** | Ditambahkan endpoint `POST /api/v1/pairing/rotate-secret` dan `GET /api/v1/security/cert-info` untuk rotasi periodik `device_token`/`device_secret` serta graceful certificate rollover (`next_cert_sha256`) |
| **Replay Attack & Jam Offline** | `X-Request-Timestamp` (kalibrasi `clock_offset_ms` dari `/health` agar HP tanpa NTP/internet tetap cocok) + `X-Request-Nonce` (UUID cache 150s) + `X-Signature` HMAC-SHA256 |
| **Brute-Force PIN** | Rate limit per `terminal_id` & per `user_id` (`users.failed_pin_count`, `pin_locked_until`), HTTP `429` + cooldown bertahap + `audit_logs`. Wajib mengirim `user_id` terpilih agar tidak ada linear scan `O(N)` maupun timing side-channel |
| **Revokasi Terminal & Expired Session** | Revoke terminal di Admin memblokir `device_token_hash` & mengirim WSS `terminal_revoked`; session di `terminal_sessions` punya `expires_at` dan otomatis di-revoke saat logout, user nonaktif, ubah izin, atau shift tutup |
| **Zero Data Leak (`cost_price`, PIN, Password)** | DTO katalog Staff menghilangkan `cost_price`, `quarantine_stock`, `damaged_stock`; `GET /auth/cashiers` hanya mengirim `id`, `name`, `username`, `role`; middleware HTTP & `audit_logs` menyensor seluruh header auth & body password/PIN |

---

## 4. Validasi Print Server & Cash Drawer

| Persyaratan | Temuan & Desain Final |
| :--- | :--- |
| **ID Unik & Idempotency** | `print_jobs.job_id` (UUID/sequential) + `idempotency_key` dengan unique partial index `idx_print_jobs_idempotency` -> retry HTTP tidak menggandakan antrean cetak |
| **Print Failure Isolation** | `POST /api/v1/transactions` meng-commit transaksi terlebih dahulu; `print_jobs` dijalankan asinkron via serial FIFO worker. Printer offline / kertas habis / `USB_PERMISSION_REQUIRED` **tidak pernah** membatalkan transaksi |
| **Reprint Tercatat** | `POST /api/v1/print/receipt` dengan `is_reprint = true` mencetak watermark `SALINAN / CETAK ULANG`, memaksa `open_drawer = false`, dan menulis `audit_logs` (`cetak_ulang_struk`) |
| **Anti Double-Open Laci (Temuan Kritis!)** | Dalam `PrinterManager.printTransactionReceipt()` saat ini (`printer_manager.dart` baris 160–168), `cashDrawerPulse` ditanam di dalam `bytes` struk yang di-loop sebanyak `copyCount`, dan akan terkirim lagi bila job cetak di-retry! **Solusi:** Pisahkan pengiriman `cashDrawerPulse` dari loop salinan cetak dan lacak dengan flag atomik **`print_jobs.drawer_pulse_sent`** (`0 -> 1`). Pulse hanya boleh terkirim 1x pada attempt pertama setelah `db.transaction` commit, dan tidak pernah terkirim ulang saat `copyCount > 1`, retry, maupun reprint |
| **Bluetooth / USB / LAN Handling** | Serial FIFO worker mencegah tabrakan socket `BluetoothSocket` (`MainActivity.kt`); pengecekan `usbManager.hasPermission` memunculkan status `usb_permission_required` ke Admin bila USB OTG baru dicolok/reboot; LAN TCP port 9100 memakai timeout `4s`; printer `system` (PDF) mengembalikan `503 PRINTER_NOT_HEADLESS` karena butuh UI dialog Android |

---

## 5. Validasi Android Server Lifecycle (`kasirtoko`, `targetSdk = 36`)

Pemeriksaan `FlutterExtension.kt` pada Flutter `3.47.5` membuktikan aplikasi ini mengompilasi dengan **`compileSdkVersion = 36` dan `targetSdkVersion = 36` (Android 16)**. Hal ini membawa konsekuensi OS kritis:
1. Android 14+ (`targetSdk >= 34`) **mewajibkan** `FOREGROUND_SERVICE` + permission spesifik tipe layanan + deklarasi `android:foregroundServiceType` di `<service>`, atau aplikasi akan langsung crash (`MissingForegroundServiceTypeException`).
2. Android 15+ membatasi tipe `dataSync` maksimal **6 jam dalam 24 jam** — tidak cocok untuk toko yang buka 12–16 jam/hari! Maka Server Admin wajib memakai **`connectedDevice`** (`FOREGROUND_SERVICE_CONNECTED_DEVICE`) dan/atau **`specialUse`** (`FOREGROUND_SERVICE_SPECIAL_USE` + property penjelasan subtype) + `POST_NOTIFICATIONS` (Android 13+) + `WAKE_LOCK`.
3. Server dijalankan dalam Android `Service` yang mengisolasi engine/server dari lifecycle `Activity` agar swipe dari Recents (`onTaskRemoved`) tidak membunuh server selama tombol **Stop Server** belum ditekan, serta memakai `ConnectivityManager.NetworkCallback` untuk mendeteksi perpindahan Wi-Fi↔Hotspot atau pergantian IP.

### Matriks Skenario Uji Lifecycle Server Android
| ID | Skenario | Mekanisme Pemulihan & Kriteria Lulus |
| :--- | :--- | :--- |
| `LS-01` | Layar HP Admin mati 15–30 menit | FGS + `PARTIAL_WAKE_LOCK` menjaga server tetap merespons ping/checkout `< 1s` |
| `LS-02` | Aplikasi Admin di-minimize / swipe Recents | `Service` tetap hidup dengan notifikasi persisten; Staff tetap `ONLINE_READY` |
| `LS-03` | Android Doze Mode aktif | Koneksi tetap bertahan atau heartbeat pulih instan; tersedia dialog saran whitelist battery optimization |
| `LS-04` | Proses Admin di-Force Stop / Crash | Dalam `<= 9s` semua Staff masuk `OFFLINE_ADMIN_UNREACHABLE`, keranjang utuh di SQLite, tombol Bayar terkunci |
| `LS-05` | Perangkat Admin Restart | Karena Android 15/16 melarang start FGS diam-diam dari `BOOT_COMPLETED`, tampil notifikasi/prompt 1-tap saat boot / auto-start saat buka Admin |
| `LS-06` | Pindah jaringan Wi-Fi Router ↔ Hotspot Android | `NetworkCallback` me-rebind / membaca IP interface baru, QR Pairing Admin otomatis ter-update |
| `LS-07` | Perubahan alamat IP LAN (DHCP renew) | Admin menampilkan IP baru di dashboard server; Staff menyambung ulang via QR / edit IP tanpa hapus keranjang |
| `LS-08` | Pemulihan server pasca-gangguan | WSS auto-reconnect -> cek `hello.sync_version` -> delta sync katalog + shift + rekonsiliasi `pending_checkout_intents` |

---

## 6. Validasi API Contract & Kelayakan Implementasi di `kasirtoko`

- **Konsistensi Format, HTTP Status, Error Code, Auth/RBAC, & Versioning:** Seluruh 26 endpoint REST (`/api/v1/...`, `protocol_version: "1.1"`) dan 1 kanal WSS (`/ws/v1/terminal`) memakai envelope seragam (`success`, `data`/`error`, `meta`).
- **Koreksi Penting yang Diterapkan pada Review Ini:**
  1. `POST /api/v1/auth/pin-login` mewajibkan `user_id` (dari `GET /api/v1/auth/cashiers`) agar verifikasi KDF `O(1)` tanpa timing leak.
  2. `GET /api/v1/catalog/products?since_version=N` wajib menyertakan produk nonaktif (`is_active = false`) sebagai delta tombstone agar Staff menghapus item terhapus dari cache (karena `DatabaseHelper.getProducts()` saat ini memfilter `is_active = 1`).
  3. Pagination standar (`page`, `limit`, `total`, `has_more`) diseragamkan pada `/catalog/products`, `/customers`, dan `/transactions?scope=terminal`.
  4. Kalibrasi clock offset (`/health` -> `server_time_ms`) ditambahkan untuk mencegah penolakan timestamp di jaringan lokal tanpa internet/NTP.
  5. Ditambahkan `/pairing/rotate-secret` & `/security/cert-info` untuk mendukung rotasi secret dan sertifikat TLS.
  6. `POST /api/v1/shifts/open` memvalidasi `cash_register_assignments` sebelum membuka shift.
- **Feasibility Terhadap Fungsi Nyata `kasirtoko`:** Semua operasi inti telah terpetakan ke metode nyata (`DatabaseHelper.insertTransaction`, `openShift`, `closeShift`, `getProducts`, `findProductAndUnitByBarcode`, `getActivePromos`, `getCustomers`, `getCustomerCreditBalance`, `PrinterManager.printTransactionReceipt`, `openCashDrawer`, `SettingsProvider`), disertai daftar adaptasi eksplisit yang diperlukan pada Tahap 1 & Tahap 2.

---

## 7. Rekap Temuan Review & Keputusan Akhir Sebelum Tahap 1

### 7.1. Temuan Kritis (7) — *Seluruhnya Sudah Teratasi di Rancangan Terbaru*
1. **Cross-Contamination `getShiftStats` (`shift_id IS NULL`)** pada mode `INDIVIDUAL_DRAWER` -> Dibatasi hanya untuk legacy `SHARED_DRAWER` `cash_register_id = 1`.
2. **Belum adanya tabel otorisasi `cash_register_assignments` & partial unique index `shifts`** -> Ditambahkan tabel assignment & 2 partial unique index SQLite.
3. **Bahaya `PRAGMA foreign_keys = ON` retroaktif pada data legacy orphan** (`deleteCustomer`, `user_id = 0`) -> Tidak menambah FK retroaktif ke kolom legacy; FK ketat diterapkan di tabel baru v5.
4. **Kebocoran secret via `BackupService` (WhatsApp/Drive)** bila `device_secret`/TLS key disimpan di `kasirtoko.db` -> Key TLS, pepper, dan Master KEK dipindah eksklusif ke Android Keystore.
5. **Penguncian akun lama jika `legacy_v1` dihapus terlalu dini** -> Diterapkan dual-verifier + *transparent re-hash on login* ke KDF `v2`.
6. **Double cash drawer pulse** di `PrinterManager` saat `copyCount > 1` atau retry `print_jobs` -> Dipisah dari buffer cetak & dikunci oleh `print_jobs.drawer_pulse_sent`.
7. **Crash Android 14–16 (`targetSdk = 36`) & limit 6 jam `dataSync` FGS** -> Memakai FGS tipe `connectedDevice`/`specialUse` + `POST_NOTIFICATIONS` + isolasi lifecycle `Service` & `NetworkCallback`.

### 7.2. Temuan Mayor (5) — *Sudah Teratasi di Rancangan Terbaru*
1. Pre-v5 backup belum menyertakan `wal_checkpoint` & `PRAGMA integrity_check` -> Ditambahkan prosedur verifikasi backup wajib.
2. Clock skew perangkat di router/hotspot tanpa internet memicu `401 REPLAY_TIMESTAMP_EXPIRED` -> Ditambahkan kalibrasi `clock_offset_ms` dari `/health`.
3. `GET /catalog/products` delta sync melewatkan produk `is_active = 0` -> Diwajibkan kirim tombstone saat `since_version > 0`.
4. Pairing manual IP tidak punya `cert_sha256` -> Diwajibkan verifikasi 6–8 karakter checksum fingerprint sertifikat di layar Admin.
5. USB OTG permission reset saat reboot/replug (`USB_PERMISSION_REQUIRED`) & belum adanya endpoint rotasi secret/cert -> Ditambahkan status printer & endpoint `/pairing/rotate-secret`, `/security/cert-info`.

### 7.3. Temuan Minor (2) — *Sudah Teratasi di Rancangan Terbaru*
1. Duplikasi nomor urut / placeholder di `ADMIN_STAFF_API_CONTRACT.md` -> Sudah dirapikan.
2. Penyeragaman metadata `pagination` pada `/customers` & `/transactions?scope=terminal` serta `X-API-Version` -> Sudah diseragamkan.

### 7.4. Daftar Keputusan Teknis Kecil yang Membutuhkan Persetujuan Anda Sebelum Mulai Coding Tahap 1
1. **Algoritma KDF `SecurityHelper` v2 (Tahap 1):** Apakah Anda menyetujui **PBKDF2-HMAC-SHA256 (`210.000` iterasi)** berbasis `package:crypto` (pure Dart, zero native FFI build risk di semua ABI Android & unit test Linux/Windows) atau ingin menambahkan library native C/FFI **Argon2id**? *(Rekomendasi praktis: PBKDF2-HMAC-SHA256 `210.000` iterasi + `pin_salt` unik + Keystore pepper + rate limit 5x/60s, karena paling stabil lintas `flutter test` & Android ARM/x86 tanpa kompilasi C/NDK tambahan; atau Argon2id bila Anda mengutamakan memory-hardness dan siap menambah native dependency).*
2. **Tipe Foreground Service Android (`kasirtoko` `targetSdk = 36`):** Apakah disetujui menggunakan **`connectedDevice`** (memanfaatkan izin Bluetooth/USB POS yang sudah ada + izin `FOREGROUND_SERVICE_CONNECTED_DEVICE`) atau **`specialUse`** (untuk dukungan penuh meski toko hanya memakai printer LAN tanpa Bluetooth/USB)? *(Rekomendasi: `connectedDevice` jika printer BT/USB terpasang atau `specialUse` agar berlaku universal untuk printer LAN/PDF sekalipun tanpa bentrok limit 6 jam Android 15).*
3. **Model Penugasan Laci di `INDIVIDUAL_DRAWER`:** Pada mode `INDIVIDUAL_DRAWER`, apakah laci kas (`cash_register_id`) ditugaskan **per perangkat terminal** (`TERM-01` -> `REG-S1`), **per kasir**, atau **admin bisa mengatur keduanya melalui `cash_register_assignments`**? *(Rancangan saat ini mendukung keduanya lewat `cash_register_assignments`).*
4. **Kebijakan `voidTransaction` Admin atas Transaksi Shift Tertutup:** Bila Admin mem-void transaksi milik Staff yang shift-nya sudah berstatus `'closed'`, apakah saldo kas shift tertutup tersebut tetap disesuaikan seperti perilaku `kasirtoko` saat ini, atau dicatat sebagai penyesuaian kas shift aktif saat void dilakukan?

---

**Menunggu Persetujuan Tertulis Anda:** Setelah Anda menyetujui review ini dan menjawab 4 poin di atas, implementasi baru akan dimulai dari **Tahap 1 (`kasirtoko`)**.
