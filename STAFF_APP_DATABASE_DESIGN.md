# STAFF_APP_DATABASE_DESIGN.md — Desain Database POS Admin (v5 Reference) & POS Staff (`staff_terminal.db`)

**Prinsip Utama:**
1. **POS Admin (`kasirtoko.db`) adalah satu-satunya pusat database transaksi, shift, laci kas, user/PIN, dan audit.**
2. **POS Staff (`staff_terminal.db`) bukan database transaksi pusat kedua**, melainkan hanya cache katalog read-only, persistensi keranjang lokal, tracker idempotency in-flight, dan cache 30 struk terakhir yang sudah dikonfirmasi Admin.
3. **Migrasi DB POS Admin (`v4 -> v5`) wajib non-destruktif**, ber-backup otomatis (`kasirtoko_pre_v5_backup.db`), teruji dari snapshot v4, dan menjaga kompatibilitas seluruh transaksi lama. *(Belum dieksekusi sampai fase implementasi disetujui).*

---

## 1. ERD Final POS Admin (Entitas Inti Multi-Device)

```text
+-----------------------+          +---------------------------+
|         users         |          |      paired_terminals     |
+-----------------------+          +---------------------------+
| PK id                 |          | PK terminal_id (TEXT)     |
|    username (UNIQUE)  |          |    terminal_code          |
|    name, role         |          |    device_uuid (UNIQUE)   |
|    password_hash      |          |    device_name            |
|    password_salt      |          |    device_token_hash      |
|    pin_hash (KDF)     |          |    device_secret_enc      |
|    pin_salt (UNIQUE)  |          | FK assigned_register_id   |--+
|    hash_version       |          |    allow_auto_open_drawer |  |
|    permissions_json   |          |    allow_manual_open_drw  |  |
|    failed_pin_count   |          |    is_active (revokable)  |  |
|    pin_locked_until   |          |    paired_at, last_seen   |  |
|    is_active          |          +-------------+-------------+  |
+-----------+-----------+                        |                |
            | 1..*                               | 1..*           |
            |                                    |                |
            v                                    v                |
+------------------------------------------------+                |
|               terminal_sessions                |                |
+------------------------------------------------+                |
| PK id                                          |                |
|    session_token_hash (UNIQUE)                 |                |
| FK user_id          -> users.id                |                |
| FK terminal_id      -> paired_terminals        |                |
|    created_at, expires_at, revoked_at          |                |
+------------------------------------------------+                |
                                                                  |
+-----------------------+                                         |
|    cash_registers     | <---------------------------------------+
+-----------------------+
| PK id                 |
|    register_code(UNQ) |  e.g. 'REG-MAIN', 'REG-S1', 'REG-S2'
|    name               |  e.g. 'Laci Kasir Utama'
| FK printer_id         |-> printers.id (nullable)
|    is_shared          |  1 = shared, 0 = individual
|    is_active          |
+-----------+-----------+
            | 1..*
            v
+------------------------------------------------+
|                     shifts                     |
+------------------------------------------------+
| PK id                                          |
| FK cashier_id        -> users.id               |
|    cashier_name                                |
|    terminal_id       -> paired_terminals / ADM |
| FK cash_register_id  -> cash_registers.id      |
|    drawer_mode       ('SHARED' | 'INDIVIDUAL') |
|    start_time, end_time                        |
|    starting_cash, total_sales_*, expected/act  |
|    status ('open' | 'closed')                  |
+-----------+------------------------------------+
            | 1..*
            v
+------------------------------------------------+       +-----------------------------+
|                  transactions                  |       |          print_jobs         |
+------------------------------------------------+       +-----------------------------+
| PK id                                          |       | PK job_id (TEXT)            |
|    invoice_number (UNIQUE)                     |       | FK transaction_id (nullable)|
|    idempotency_key (UNIQUE partial index)      |       |    invoice_number           |
| FK cashier_id        -> users.id               |------>|    terminal_id              |
|    cashier_name                                |  1..* | FK cash_register_id         |
|    terminal_id       -> paired_terminals / ADM |       | FK printer_id -> printers   |
| FK shift_id          -> shifts.id              |       |    job_type ('receipt'|'drw')|
| FK cash_register_id  -> cash_registers.id      |       |    open_drawer (0|1)        |
| FK customer_id       -> customers.id           |       |    is_reprint (0|1)         |
|    subtotal, discount_total, tax_amount        |       |    status ('queued'|'printing'|
|    grand_total, payment_method, credit_used    |       |           'printed'|'failed') |
|    amount_paid, change_amount, status          |       |    idempotency_key          |
|    qr_code_payload, printer_snapshot_json      |       |    created_at, completed_at |
+------------------------------------------------+       +-----------------------------+
```

---

## 2. Rancangan Perubahan Database POS Admin (`kasirtoko.db` v4 -> v5)

### 2.1. Langkah Keselamatan Migrasi & Konfigurasi Multi-Koneksi
1. **Pre-Migration Backup & Verifikasi Integritas:**
   - Sebelum `openDatabase(..., version: 5)` pada upgrade `v4 -> v5`, tutup koneksi aktif / checkpoint WAL (`PRAGMA wal_checkpoint(TRUNCATE)` bila file `-wal` ada).
   - Salin `kasirtoko.db` ke `kasirtoko_pre_v5_backup.db` (mengikuti pola `preV3Backup` & `preV4Backup` di `db_helper.dart` baris 108–119).
   - **Verifikasi backup wajib:** Pastikan `kasirtoko_pre_v5_backup.db` ada, ukuran byte `> 0`, dan lulus `PRAGMA integrity_check` (`'ok'`) sebelum migrasi dimulai.
2. **PRAGMA Multi-Connection & Foreign Key Safety:**
   - Pada callback `onConfigure` (di luar transaksi DDL):
     - Aktifkan `PRAGMA journal_mode = WAL;` dan `PRAGMA busy_timeout = 5000;` agar koneksi paralel dari server LAN tidak terkena `SQLITE_BUSY`.
     - Aktifkan `PRAGMA foreign_keys = ON;` **secara hati-hati**: karena DB v1–v4 sebelumnya tidak menyalakan `PRAGMA foreign_keys = ON` (dan memiliki fitur `deleteCustomer()` serta `audit_logs` dengan `user_id = 0`), **jangan menambahkan constraint `FOREIGN KEY` retroaktif pada kolom legacy** (`transactions.customer_id`, `transactions.cashier_id`, `audit_logs.user_id`) yang berisiko memicu `FOREIGN KEY constraint failed` pada data lama. Constraint `FOREIGN KEY` ketat diterapkan pada **tabel baru v5** (`cash_register_assignments`, `terminal_sessions`, `print_jobs`) setelah backfill valid.
3. **Non-Destruktif & Rollback Otomatis (`_onUpgrade` `oldVersion < 5`):**
   - Seluruh DDL/DML migrasi dijalankan di dalam transaksi `onUpgrade` bawaan SQLite/sqflite; bila terjadi error di tengah jalan, SQLite otomatis melakukan rollback ke versi `4`.
   - Bila kegagalan atau kerusakan terdeteksi pasca-migrasi, mekanisme recovery memulihkan dari `kasirtoko_pre_v5_backup.db` yang telah terverifikasi.
   - Mendukung upgrade berantai dari backup versi lama (`v1/v2/v3/v4 -> v5`) yang dipulihkan melalui `BackupService.restoreDatabase()`.

### 2.2. Skema Perubahan pada Tabel Lama di POS Admin
1. **`store_settings`:**
   - Seed default key baru jika belum ada:
     - `'drawer_mode'`: `'SHARED_DRAWER'` (opsi: `'SHARED_DRAWER'`, `'INDIVIDUAL_DRAWER'`)
     - `'server_port'`: `'8443'`
     - `'auto_print_staff_transactions'`: `'1'`
2. **`users` (Perbaikan Audit `SecurityHelper`):**
   - `_addColumnIfMissing(db, 'users', 'pin_salt', "TEXT NOT NULL DEFAULT ''")`
   - `_addColumnIfMissing(db, 'users', 'hash_version', "TEXT NOT NULL DEFAULT 'legacy_v1'")`
   - `_addColumnIfMissing(db, 'users', 'failed_pin_count', 'INTEGER NOT NULL DEFAULT 0')`
   - `_addColumnIfMissing(db, 'users', 'pin_locked_until', 'TEXT')`
   - *Migrasi progresif:* Akun lama tetap dapat login pertama kali lalu otomatis di-rehash ke KDF kuat (`$pbkdf2-sha256$...` atau `$argon2id$...`) dengan `pin_salt` terpisah dari `password_salt`, dan `pin` plaintext dibersihkan.
3. **`shifts`:**
   - `_addColumnIfMissing(db, 'shifts', 'terminal_id', "TEXT NOT NULL DEFAULT 'ADMIN'")`
   - `_addColumnIfMissing(db, 'shifts', 'cash_register_id', 'INTEGER NOT NULL DEFAULT 1')`
   - `_addColumnIfMissing(db, 'shifts', 'drawer_mode', "TEXT NOT NULL DEFAULT 'SHARED_DRAWER'")`
   - Backfill defensif: baris shift lama dengan `terminal_id IS NULL OR terminal_id = ''` diisi `'ADMIN'`, `cash_register_id` yang null/invalid diisi `1`.
   - **Constraint DB anti-bentrok shift (Partial Unique Indexes):**
     ```sql
     -- Menjamin pada SATU laci kas (cash_register_id) tidak pernah ada >1 shift 'open' bersamaan (baik SHARED maupun INDIVIDUAL)
     CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open_per_register
     ON shifts (cash_register_id)
     WHERE status = 'open';

     -- Menjamin pada mode INDIVIDUAL_DRAWER satu kasir tidak membuka >1 shift aktif secara paralel
     CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open_per_cashier_indiv
     ON shifts (cashier_id)
     WHERE status = 'open' AND drawer_mode = 'INDIVIDUAL_DRAWER';
     ```
   - *(Catatan kompatibilitas: sebelum membuat partial unique index di atas saat migrasi v4→v5, verifikasi tidak ada kondisi historis >1 shift `'open'` pada `cash_register_id = 1`; bila ditemukan anomali data korup v4, pertahankan hanya shift `'open'` terbaru atau laporkan ke Admin sebelum aktivasi).*
4. **`transactions`:**
   - `_addColumnIfMissing(db, 'transactions', 'terminal_id', "TEXT NOT NULL DEFAULT 'ADMIN'")`
   - `_addColumnIfMissing(db, 'transactions', 'cash_register_id', 'INTEGER NOT NULL DEFAULT 1')`
   - `_addColumnIfMissing(db, 'transactions', 'idempotency_key', 'TEXT')`
   - Index unik idempotency:
     ```sql
     CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_idempotency
     ON transactions (idempotency_key)
     WHERE idempotency_key IS NOT NULL AND idempotency_key != '';
     ```
   - Backfill kompatibel data lama (defensif terhadap transaksi v1/v2 yang `shift_id IS NULL`):
     ```sql
     UPDATE transactions
     SET terminal_id = COALESCE(NULLIF(terminal_id, ''), 'ADMIN'),
         cash_register_id = COALESCE(
           (SELECT s.cash_register_id FROM shifts s WHERE s.id = transactions.shift_id),
           1
         )
     WHERE terminal_id IS NULL OR terminal_id = '' OR cash_register_id IS NULL;
     ```
   - **Perbaikan query `getShiftStats` (`db_helper.dart` baris 3408):** Fallback `shift_id IS NULL AND date >= ? AND date <= ?` hanya boleh dipakai bila `shift.drawer_mode == 'SHARED_DRAWER'` dan `shift.cash_register_id == 1` (legacy v1/v2), agar transaksi lama tidak bocor ke shift kasir lain pada mode `INDIVIDUAL_DRAWER`.
5. **`cash_flows` & `products`:**
   - Tambah `terminal_id` & `cash_register_id` (default `'ADMIN'` / `1`) di `cash_flows` untuk audit kas lintas laci.
   - Tambah `updated_at` & `sync_version` di `products` agar sinkronisasi delta ke terminal cepat (termasuk produk yang di-soft-delete `is_active = 0`).

### 2.3. Tabel Baru di POS Admin (v5)
1. **`cash_registers`:** Laci kas toko (`id`, `register_code UNIQUE`, `name`, `printer_id`, `is_shared`, `is_active`, `created_at`). Otomatis seed `id = 1, register_code = 'REG-MAIN', name = 'Laci Kasir Utama', is_shared = 1`.
2. **`cash_register_assignments`:** Penugasan & izin akses laci kas (`id`, `cash_register_id NOT NULL`, `terminal_id`, `cashier_id`, `is_active`, `created_at`, dengan `FOREIGN KEY (cash_register_id) REFERENCES cash_registers(id) ON DELETE CASCADE` dan `UNIQUE(cash_register_id, terminal_id, cashier_id)`). Menjamin kasir hanya dapat membuka & memakai laci yang ditugaskan/diizinkan.
3. **`paired_terminals`:** Menyimpan terminal terdaftar **tanpa batas jumlah hardcoded** (`terminal_id PK`, `terminal_code`, `device_uuid UNIQUE`, `device_name`, `device_token_hash UNIQUE`, `device_secret_enc`, `assigned_register_id`, `allow_auto_open_drawer`, `allow_manual_open_drawer`, `is_active`, `paired_at`, `last_seen_at`). **Penting (Keamanan Backup):** `device_secret_enc` wajib dienkripsi dengan master KEK AES-GCM yang disimpan di **Android Keystore** (bukan di `kasirtoko.db`), sehingga file ekspor `BackupService` (Google Drive/WhatsApp) tidak membocorkan secret perangkat atau private key TLS!
4. **`terminal_sessions`:** Menyimpan `session_token_hash UNIQUE`, `user_id`, `terminal_id`, `created_at`, `expires_at`, `revoked_at` dengan `FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE` & `FOREIGN KEY (terminal_id) REFERENCES paired_terminals(terminal_id) ON DELETE CASCADE`.
5. **`print_jobs`:** Antrean serial FIFO untuk cetak struk & pulse laci pasca-commit (`job_id PK`, `transaction_id`, `invoice_number`, `terminal_id`, `cash_register_id`, `printer_id`, `job_type`, `open_drawer`, `drawer_pulse_sent INTEGER NOT NULL DEFAULT 0`, `is_reprint`, `status`, `retry_count`, `error_message`, `idempotency_key`, `created_at`, `completed_at`, + `CREATE UNIQUE INDEX idx_print_jobs_idempotency ON print_jobs(idempotency_key) WHERE idempotency_key IS NOT NULL AND idempotency_key != ''`). Kolom `drawer_pulse_sent` menjamin pulse laci tidak pernah dikirim dua kali saat retry cetak atau multi-copy!

---

## 3. Skema Database Lokal POS Staff (`staff_terminal.db`, Version `1`)

**Penegasan:** Tidak ada tabel `users`, `transactions`, `shifts`, `cash_flows`, `customer_debts`, `inventory_movements`, `return_orders`, maupun kolom `cost_price`.

### 3.1. Penyimpanan Kredensial Sensitif (Android Keystore via `flutter_secure_storage`)
- `terminal_id`, `device_token`, `device_secret`, `tls_cert_sha256`, `cashier_session_token`.

### 3.2. Tabel SQLite Lokal POS Staff

| Nama Tabel | Fungsi | Isi Utama |
| :--- | :--- | :--- |
| `pairing_profile` | Metadata koneksi non-rahasia | `terminal_id`, `server_host`, `server_port`, `store_name`, `drawer_mode`, `receipt_config_json`, `terminal_policy_json`, `last_sync_version` |
| `cached_products` | Cache read-only katalog | `id`, `code`, `name`, `category`, `barcode`, `is_service`, `track_stock`, `base_unit`, `selling_price`, `stock`, `min_stock_alert`, `brand`, `model`, `imei_or_sn`, `warranty_info`, `is_active`, `updated_at` *(tanpa `cost_price`)* |
| `cached_product_units` | Cache multi-satuan | `id`, `product_id`, `unit_name`, `conversion_factor`, `selling_price`, `barcode` |
| `cached_tiered_prices` | Cache harga grosir bertingkat | `id`, `product_id`, `min_qty`, `price` |
| `cached_promos` | Cache promo aktif | `id`, `name`, `promo_type`, `min_purchase`, `discount_value`, `buy_qty`, `get_qty`, `target_product_id`, `start_date`, `end_date`, `is_active` |
| `cached_customers` | Cache pelanggan | `id`, `name`, `phone`, `address`, `points` |
| `active_cart` & `active_cart_items` | **Keranjang persisten** | Menjaga keranjang aman meski Wi-Fi putus atau app di-restart |
| `local_held_orders` & `local_held_order_items` | **Antrean hold order lokal** | Menggantikan RAM-only hold order dengan simpanan lokal aman |
| `pending_checkout_intents` | **Tracker idempotency in-flight** | `idempotency_key`, `cashier_id`, `shift_id`, `cash_register_id`, `payload_json`, `state` (`submitting` \| `awaiting_reconciliation` \| `aborted`), `resolved_invoice_number`. Dihapus segera setelah rekonsiliasi selesai |
| `recent_receipt_cache` | Cache maks **30** struk terkonfirmasi server | Khusus preview ulang, kirim WA, & request cetak ulang ke Admin |

---

## 4. Aturan Pembersihan Cache POS Staff
- Saat **Unpair / Revoke Terminal (`403 TERMINAL_REVOKED`)**: Hapus seluruh key di `flutter_secure_storage` dan bersihkan seluruh tabel SQLite `staff_terminal.db`.
- Saat **Ganti Kasir / Logout**: Hapus `cashier_session_token` dari secure storage.
