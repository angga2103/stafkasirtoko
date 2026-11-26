# STAFF_APP_AUDIT.md — Audit Awal Sistem POS Multi-Device (`stafkasirtoko` & `kasirtoko`)

**Tanggal Audit:** 26 November 2026 (Revisi Keputusan Final Arsitektur)  
**Status:** Tahap Audit & Perancangan Final (Read-Only terhadap `kasirtoko`, belum ada implementasi atau build APK)  
**Repositori Referensi (POS Admin):** `https://github.com/angga2103/kasirtoko` (lokal: `c:\kasirtoko`, commit `327b1ab`, versi `2.2.0+4`)  
**Repositori Target (POS Staff):** `https://github.com/angga2103/stafkasirtoko` (lokal: `c:\StafKasirtoko`)

---

## 1. Ringkasan Eksekutif

Audit ini memverifikasi kondisi aktual repositori `stafkasirtoko` serta arsitektur, database, autentikasi, mekanisme shift/laci kas, dan printer pada codebase berjalan POS Admin `kasirtoko` untuk menyelaraskan rancangan dengan **Keputusan Final Desain POS Multi-Device**.

### Temuan Utama
1. **Kondisi `stafkasirtoko`:** Repositori lokal `c:\StafKasirtoko` maupun remote GitHub `angga2103/stafkasirtoko` masih **kosong** (belum ada proyek Flutter/Android maupun commit; baru berisi 6 dokumen rancangan arsitektur).
2. **Kondisi `kasirtoko` (POS Admin):** Aplikasi **Flutter Android v2.2.0+4** berarsitektur **Full Offline-First single-device** dengan SQLite `version: 4` (31 tabel), namun **belum memiliki server jaringan (HTTPS/WebSocket)** maupun dukungan multi-terminal/multi-laci.
3. **Temuan Kritis Audit Keamanan (`SecurityHelper` & Auth):** Implementasi `SecurityHelper` (`lib/utils/security_helper.dart`) dan `DatabaseHelper.loginWithPin` **belum memenuhi standar keamanan multi-device LAN** (bukan KDF standar PBKDF2/Argon2id, work factor hanya `1000` iterasi, memakai salt bersama untuk password dan PIN, tidak ada versi hash/pepper, linear scan PIN `O(N)`, masih ada fallback plaintext legacy, dan belum ada rate limiting).
4. **Temuan Kritis Audit Shift & Cash Drawer:** `DatabaseHelper.openShift()` (`lib/database/db_helper.dart` baris 3299–3319) memaksakan **hanya 1 shift berstatus `'open'` secara global**, dan belum memisahkan entitas `terminal_id` maupun `cash_register_id`. Aturan ini harus direfaktor agar mendukung mode `SHARED_DRAWER` dan `INDIVIDUAL_DRAWER` tanpa merusak data transaksi dan shift lama.
5. **Temuan Kritis Audit Cash Drawer & Printer:** `PrinterManager.printTransactionReceipt()` memicu pulse RJ11 apabila `!isReprint && target.openDrawer && transaction.paymentMethod == 'tunai'`, tetapi belum memiliki izin granular per kasir, konfigurasi per terminal, maupun verifikasi commit server sebelum eksekusi untuk terminal remote.
6. **Kesiapan SDK Lokal:** Mesin pengembangan sudah memiliki **Flutter `3.47.5` (`stable`)** dan **Dart `3.13.4`**, sesuai dengan constraint `kasirtoko` (`sdk: ^3.13.4`).

---

## 2. Kondisi Repositori `stafkasirtoko` Saat Ini

| Aspek | Kondisi Teramati |
| :--- | :--- |
| Direktori lokal (`c:\StafKasirtoko`) | Berisi 6 dokumen desain arsitektur; belum ada proyek Flutter/Android |
| Inisialisasi Git lokal | Belum ada `.git` |
| Remote GitHub (`angga2103/stafkasirtoko`) | Ada (`public`, dibuat `2026-11-25T23:56:18Z`, `default_branch: main`), `size: 0`, belum ada commit |
| Source code / APK | Belum ada (menunggu persetujuan akhir desain sebelum fase coding) |

---

## 3. Audit Teknis Repositori POS Admin (`kasirtoko`)

Seluruh temuan berikut diverifikasi langsung dari file di `c:\kasirtoko`.

### 3.1. Framework, Bahasa, Build, & Dependensi
- **Framework & Bahasa:** Flutter `3.47.5` / Dart `^3.13.4`, Android Kotlin (`MainActivity.kt`, JVM 17, `minSdk = 21`, `applicationId = com.kasirtoko.app.kasirtoko`).
- **Catatan Signing Build:** `android/app/build.gradle.kts` saat ini memakai `signingConfigs.getByName("debug")` untuk build `release`; untuk produksi multi-device wajib memakai release keystore resmi.
- **Izin Android (`AndroidManifest.xml`):** Sudah mendeklarasikan `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CAMERA`, `VIBRATE`, `BLUETOOTH*`, `ACCESS_FINE_LOCATION` (maxSdk 30), `READ_MEDIA_IMAGES`, dan USB host.
- **State Management:** `provider: ^6.1.5+1` (`MultiProvider` dengan 11 provider di `lib/main.dart`).
- **CI/CD (`.github/workflows/build.yml`):** GitHub Actions Ubuntu + Java 17 + `libsqlite3-dev` + `flutter test` + `flutter build apk --release --no-tree-shake-icons`.

### 3.2. Database (`lib/database/db_helper.dart`)
- **Engine & Versi:** SQLite (`sqflite: ^2.4.6`), `version: 4`, **31 tabel** (`18` core v1 + `6` v2 + `3` v3 + `4` v4).
- **Mekanisme Migrasi yang Sudah Ada:**
  - Memiliki pre-migration safety backup otomatis sebelum upgrade (`kasirtoko_pre_v3_backup.db` dan `kasirtoko_pre_v4_backup.db`, baris 107–120).
  - Menggunakan `_addColumnIfMissing()` dan `CREATE TABLE IF NOT EXISTS` secara non-destruktif disertai SQL backfill aman untuk data lama (baris 143–309).
- **Catatan Penting untuk Skalabilitas Multi-Terminal:**
  - `openDatabase` saat ini menggunakan journal mode default dan belum mengaktifkan `PRAGMA journal_mode = WAL` serta `PRAGMA busy_timeout` maupun `PRAGMA foreign_keys = ON`. Untuk multi-terminal konkuren, mengaktifkan WAL mode dan `busy_timeout` pada fase implementasi Admin sangat krusial.
  - Tabel `return_orders` (v4) sudah memiliki `idempotency_key` dengan unique partial index, tetapi tabel `transactions` belum memiliki `idempotency_key`, `terminal_id`, maupun `cash_register_id`.

### 3.3. Audit Shift & Cash Drawer (`shifts`, `cash_flows`, `transactions`)
- **Kondisi Saat Ini:**
  - Tabel `shifts` (baris 754–774) hanya menyimpan `cashier_id` dan `cashier_name`, tanpa `terminal_id` dan tanpa `cash_register_id`.
  - `DatabaseHelper.getCurrentOpenShift()` (baris 3281–3291) mengambil `SELECT * FROM shifts WHERE status = 'open' ORDER BY id DESC LIMIT 1`.
  - `DatabaseHelper.openShift(shift)` (baris 3299–3319) melempar `StateError` jika masih ada baris `shifts` dengan `status = 'open'`, terlepas dari siapa kasirnya atau perangkat mana yang membuka.
  - `DatabaseHelper.insertTransaction()` (baris 1561–1769) mewajibkan `shiftId` berstatus `'open'` dan mengupdate `total_sales_cash/qris/transfer/kasbon/credit` pada baris `shifts` tersebut.
  - `DatabaseHelper.getCashFlowReport()` (baris 3481–3683) menjumlahkan `starting_cash` seluruh shift, penjualan `transactions`, dan `cash_flows`.
- **Gap terhadap Keputusan Final:**
  - **Mode `INDIVIDUAL_DRAWER` tidak dapat berjalan** selama aturan 1 shift terbuka global di `openShift()` dan `getCurrentOpenShift()` masih dipertahankan.
  - Belum ada entitas **`cash_registers` (laci kas)** sehingga laporan dan kontrol fisik uang tunai belum memisahkan siapa kasir (`cashier_id`), di perangkat mana (`terminal_id`), pada shift mana (`shift_id`), dan laci mana (`cash_register_id`).
  - Belum ada pelacakan audit `terminal_id` dan `cash_register_id` pada `transactions` dan `cash_flows`.

### 3.4. Audit Keamanan & `SecurityHelper` (Audit Mendalam)
Pemeriksaan baris demi baris pada `lib/utils/security_helper.dart` (baris 1–38), `lib/database/db_helper.dart` (baris 155–190, 935–958, 1084–1118), dan `lib/providers/auth_provider.dart` (baris 118–135, 190–297) menemukan **7 kelemahan nyata**:

| No | Temuan di `kasirtoko` Saat Ini | Risiko Keamanan | Wajib Diperbaiki pada Implementasi |
| :--- | :--- | :--- | :--- |
| 1 | **Custom HMAC Chaining, Bukan KDF Standar** (`hashSecret` melakukan `block = hmac.convert(block).bytes`) | Tidak setara RFC 8018 PBKDF2 atau Argon2id; tidak memiliki *memory-hardness* maupun struktur key-stretching standar | Ganti/tingkatkan ke algoritma password hashing standar kuat (**Argon2id** atau **PBKDF2-HMAC-SHA256** berstandar industri dengan parameter memadai) |
| 2 | **Work Factor Terlalu Rendah (`_iterations = 1000`)** | Untuk PIN 4–6 digit (`10^4`–`10^6` kombinasi), `1000` iterasi SHA-256 sangat cepat dipecahkan secara offline bila file DB bocor | Gunakan work factor tinggi (mis. Argon2id `m=19456 KiB, t=2, p=1` atau PBKDF2-HMAC-SHA256 `>= 210.000` iterasi + server pepper) |
| 3 | **Tanpa Version/Algorithm Header (PHC Format)** | Hash tersimpan hanya `base64UrlEncode(block)` mentah; tidak bisa membedakan hash lama v1 vs hash kuat baru untuk migrasi progresif | Simpan format terstruktur (mis. `$argon2id$v=19$m=...,t=...,p=...$salt$hash` atau kolom `hash_algo`) dan lakukan *re-hash on login* secara non-destruktif |
| 4 | **Salt Bersama Password & PIN (`password_salt`)** | `AuthProvider` dan `_seedInitialData` memakai `password_salt` yang sama untuk `password_hash` dan `pin_hash`. Bila PIN = password, hash identik (`password_hash == pin_hash`) | Gunakan **salt unik terpisah** (`pin_salt` tersendiri atau domain separation eksplisit) untuk PIN dan Password |
| 5 | **Tanpa Pepper / Domain Separation** | Serangan dictionary/brute-force offline terhadap backup DB menjadi lebih mudah karena PIN berentropi rendah | Tambahkan *domain separation* + *application/keystore pepper* saat memverifikasi PIN di perangkat Admin |
| 6 | **`loginWithPin(pin)` Linear Scan O(N) & Fallback Plaintext** | Loop seluruh user aktif (baris 1086–1096): rentan non-deterministik bila PIN kembar, bottleneck CPU jika KDF dinaikkan ke iterasi tinggi, timing leak, dan masih menyisakan fallback plaintext `user.pin == pin` | Wajibkan identifikasi kasir (`user_id`/`username` + PIN atau lookup hash keyed-HMAC) + verifikasi KDF tunggal O(1), wajibkan keunikan PIN jika mode PIN-only tetap ada, dan bersihkan fallback plaintext |
| 7 | **Tanpa Rate Limit / Lockout** | Tidak ada batas percobaan gagal di `loginWithPin` maupun `AuthProvider` | Terapkan rate limiting & progressive lockout per `terminal_id` dan per `user_id` (mis. 5x salah -> cooldown 60s, 10x -> lock 5 menit + catat `audit_logs`) |

### 3.5. Audit Model Produk, Transaksi, & Printer
- **Model Produk (`ProductModel`):** Mendukung multi-satuan (`product_units`), harga bertingkat (`tiered_prices`), batch (`product_batches`), produk jasa (`is_service`), kontrol stok (`track_stock`), 3 bucket stok (`stock`, `quarantine_stock`, `damaged_stock`), serta `cost_price` (**sensitif HPP**, `AppPermissions.viewCostPrice = false` untuk kasir).
- **Model Transaksi (`TransactionModel`):** Mendukung pembayaran `tunai`, `qris`, `transfer`, `kasbon`, `saldo_kredit`, snapshot struk historis (`printer_snapshot_json`), dan QR nota (`TRX|<invoice>|<total>`). Catatan minor yang ditemukan: `PosProvider.checkout()` lupa menyalin `creditUsed` pada instance `savedTrx` return object (line 532–555).
- **Model Printer & Cash Drawer (`PrinterManager` & `MainActivity.kt`):**
  - Mendukung `bluetooth` (RFCOMM SPP), `usb` (USB OTG bulk transfer), `lan` (TCP 9100), dan `system` (Android Print Service PDF).
  - Mode `system` memicu dialog UI Android sehingga **tidak bisa** dipakai untuk silent remote printing dari Staff.
  - `EscPosGenerator.cashDrawerPulse` (`[0x1B, 0x70, 0x00, 0x19, 0xFA]`) dikirim otomatis di `PrinterManager.printTransactionReceipt()` saat `!isReprint && target.openDrawer && transaction.paymentMethod == 'tunai'`, dan manual di `PrinterManager.openCashDrawer()`.
  - **Gap terhadap Keputusan Final Cash Drawer:** Saat ini belum ada permission `open_cash_drawer`, belum ada toggle izin per terminal (`allow_auto_open_drawer`, `allow_manual_open_drawer`), dan belum ada keterikatan ke `cash_register_id`.

---

## 4. Kesesuaian Batasan & Larangan Arsitektur

1. **Zero Business Feature Recreation:** Modul produk CRUD, pembelian supplier, stok opname, retur & tukar barang, pelunasan kasbon, laporan laba/HPP, absensi selfie, dan manajemen karyawan **tetap 100% berada di POS Admin (`kasirtoko`)**.
2. **Zero Second Central Transaction DB:** POS Staff **tidak** menyimpan tabel transaksi pusat, ledger stok, atau tabel user/PIN.
3. **Zero Hardcoded Terminal Limit:** Penambahan dan pencabutan terminal sepenuhnya dinamis melalui tabel `paired_terminals` di Admin tanpa batas angka tetap di source code.
