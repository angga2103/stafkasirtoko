# DATABASE_MIGRATION_GUIDE.md — Panduan Migrasi Database Admin (`v4 -> v5 -> v6`) & Staff (`staff_terminal.db`)

## 1. POS Admin (`kasirtoko.db`) — Versi Skema `6`
File implementasi: [`db_helper.dart`](file:///c:/kasirtoko/lib/database/db_helper.dart), [`multi_device_dao.dart`](file:///c:/kasirtoko/lib/database/multi_device_dao.dart).

### 1.1. Mekanisme Backup Pra-Migrasi & Pemulihan
Sebelum menaikkan `user_version` pada database on-disk:
1. `_prepareAndVerifyPreMigrationBackup` menutup koneksi aktif dan menjalankan `PRAGMA wal_checkpoint(TRUNCATE)`.
2. Menggandakan database sumber menjadi `kasirtoko_pre_v5_backup.db` (jika `existingVersion <= 4`) atau `kasirtoko_pre_v6_backup.db` (jika `existingVersion == 5`).
3. Membuka file backup secara `readOnly` dan menjalankan `PRAGMA integrity_check` (`'ok'`). Bila gagal, migrasi dibatalkan sebelum menyentuh database aktif.
4. Jika exception terjadi saat `_onUpgrade`, `_restoreFromBackupFile` otomatis mengembalikan file backup ke lokasi live.

### 1.2. Konfigurasi Runtime (`_onConfigure`)
- `PRAGMA foreign_keys = ON`
- `PRAGMA busy_timeout = 5000`
- `PRAGMA journal_mode = WAL` (pada database file on-disk)

### 1.3. Perubahan Skema v4 -> v5 -> v6 (Non-Destruktif)
- **v5 (Tahap 1):**
  - `users`: `pin_salt`, `hash_version`, `pin_lookup_hash`, `failed_pin_count`, `pin_locked_until`.
  - `transactions`, `shifts`, `cash_flows`, `return_settlements`: backfill `terminal_id = 'ADMIN'`, `cash_register_id = 1`, `drawer_mode = 'SHARED_DRAWER'`, serta kolom `idempotency_key`.
  - Tabel baru: `cash_registers` (seed `id=1` `'REG-MAIN'`), `cash_register_assignments`, `paired_terminals`, `terminal_sessions`, `print_jobs`, `transaction_voids`.
  - Index unik parsial: `idx_transactions_idempotency`, `idx_shifts_one_open_per_register`, `idx_shifts_one_open_per_cashier_indiv`.
- **v6 (Tahap 2):**
  - `products`, `promos`, `customers`: tambah kolom `updated_at` & `sync_version` untuk delta sync + tombstone (`is_active = 0`).
  - `paired_terminals`: tambah `terminal_code`, `device_uuid`, `device_secret_enc` (amplop AES-256-GCM dari Android Keystore Vault), `allow_auto_open_drawer`, `allow_manual_open_drawer`, `default_printer_id` + index `idx_paired_terminals_device_uuid`.
  - `print_jobs`: tambah `invoice_number`, `job_type`, `is_reprint`, `drawer_pulse_sent`, `idempotency_key`, `payload_json` + index unik parsial `idx_print_jobs_idempotency`.
  - Tabel baru: `pairing_tokens` (menyimpan SHA-256 `token_hash` dengan TTL & konsumsi sekali pakai).
  - Pengaturan `store_settings`: key monotonic `catalog_sync_version`.
  - Seluruh alter table pada `_applyV6Upgrade` dijaga oleh `_tableExists` dan `_addColumnIfMissing` agar aman pada skema parsial maupun upgrade lompat `v1/v3/v4 -> v6`.

### 1.4. Kompatibilitas Data Lama & Backfill
- Transaksi dan shift lama v1–v4 tetap terbaca normal dan otomatis terikat ke `terminal_id = 'ADMIN'` dan `cash_register_id = 1`.
- Shift ganda historis sebelum v5 dinormalisasi secara aman agar index unik baru tidak gagal dibuat dan dicatat ke `audit_logs`.

## 2. POS Staff (`staff_terminal.db`) — Versi Skema `1`
File implementasi: [`staff_local_db.dart`](file:///c:/StafKasirtoko/lib/data/local/staff_local_db.dart).
- Berfungsi **murni sebagai cache terminal**:
  - `pairing_profile`, `cached_products` (tanpa kolom `cost_price`/`quarantine_stock`/`damaged_stock`), `cached_product_units`, `cached_tiered_prices`, `cached_promos`, `cached_customers`.
  - `active_cart` & `active_cart_items` (ketahanan keranjang saat offline / restart).
  - `local_held_orders` & `local_held_order_items` (draft sementara sebelum checkout).
  - `pending_checkout_intents` (pelacakan `idempotency_key` untuk rekonsiliasi otomatis pasca koneksi putus).
  - `recent_receipt_cache` (dibatasi kueri SQL `LIMIT 30` terbaru hasil konfirmasi Admin).
