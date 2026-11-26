# ADMIN_STAFF_API_CONTRACT.md — Kontrak API Final POS Admin (`kasirtoko`) <-> POS Staff (`stafkasirtoko`)

**Versi Kontrak:** `v1.1.0` (Final Design Lock — Menunggu Persetujuan Implementasi)  
**Transport Wajib:** **HTTPS** (`TLS` self-signed cert dikelola Admin + Certificate Pinning) & **WSS** (`/ws/v1/terminal`)

---

## 1. Pemetaan Kemampuan Nyata `kasirtoko` & Adaptasi yang Dibutuhkan

Kontrak ini dibangun langsung dari domain nyata di `c:\kasirtoko` dan memisahkan secara transparan apa yang sudah ada vs apa yang harus ditambahkan pada adapter server Admin saat fase implementasi:

| Domain | Sumber Nyata di `kasirtoko` | Adaptasi di POS Admin Saat Fase Implementasi |
| :--- | :--- | :--- |
| **TLS & Server LAN** | Belum ada (`HardwareBridge` hanya TCP client printer) | Embedded HTTPS/WSS server + TLS cert generator + Foreground Service |
| **Pairing & Terminal** | Belum ada | Tabel `paired_terminals` + `allow_auto_open_drawer` / `allow_manual_open_drawer` + `default_cash_register_id` |
| **Auth, PIN & Rate Limit** | `DatabaseHelper.loginWithPin`, `SecurityHelper`, `AppPermissions`, `audit_logs` | Upgrade `SecurityHelper` ke Argon2id/PBKDF2-HMAC-SHA256 >= 210k iterasi + salt terpisah PIN + rate limiter + `terminal_sessions` + permission `open_cash_drawer` |
| **Shift & Laci Kas** | `shifts`, `DatabaseHelper.openShift`, `getCurrentOpenShift` (1 shift global) | Tabel `cash_registers`, kolom `terminal_id` & `cash_register_id` pada `shifts` & `transactions`, mode `SHARED_DRAWER` & `INDIVIDUAL_DRAWER` di `store_settings` |
| **Katalog & Pelanggan** | `getProducts`, `findProductAndUnitByBarcode`, `getActivePromos`, `getCustomers`, `getCustomerCreditBalance` | Strip `cost_price` di serializer katalog Staff, tambah `sync_version`/`updated_at` untuk delta sync |
| **Transaksi** | `DatabaseHelper.insertTransaction` | Tambah `idempotency_key`, `terminal_id`, `cash_register_id`; hitung ulang harga/promo/pajak di server; fix `creditUsed` pada return object `PosProvider` |
| **Printer & Laci Kas** | `PrinterManager.printTransactionReceipt`, `openCashDrawer` | Serial FIFO `print_jobs` queue + enforcement 6 aturan cash drawer + audit log |

---

## 2. Keamanan Header, Request Signing, & Format Envelope

### 2.1. Headers Wajib & Versioning API
- **Versioning API:** Semua endpoint menggunakan prefix path `/api/v1` + response `meta.protocol_version = "1.1"` + header opsional `X-API-Version: 1.1`.
- **Headers Wajib (Semua Endpoint Terautentikasi):**
  - `Content-Type: application/json; charset=utf-8`
  - `X-Terminal-Id`: ID terminal hasil pairing (contoh: `TERM-01`)
  - `X-Device-Token`: Token perangkat hasil pairing (dicocokkan dengan hash di `paired_terminals`)
  - `Authorization`: `Bearer <cashier_session_token>` (wajib pasca-login PIN)
  - `X-Request-Timestamp`: Unix epoch milliseconds terkalibrasi offset server (toleransi drift ±120.000 ms). Pada jaringan LAN/Hotspot tanpa NTP/internet, Staff menghitung `clock_offset_ms = server_time_ms - local_time_ms` dari `GET /api/v1/health`
  - `X-Request-Nonce`: UUID v4 (anti-replay, ditolak bila pernah dipakai dalam window 150s)
  - `X-Signature`: `HMAC-SHA256(device_secret, "$METHOD\n$PATH_AND_QUERY\n$TIMESTAMP\n$NONCE\n$SHA256_HEX_BODY")`
  - `X-Idempotency-Key`: UUID v4 (wajib pada `POST /transactions`, `POST /print/receipt`, `POST /shifts/open`)

### 2.2. Envelope Response Baku
**Sukses:**
```json
{
  "success": true,
  "data": {},
  "meta": {
    "server_time": "2026-11-26T15:10:00+07:00",
    "protocol_version": "1.1",
    "sync_version": 108
  }
}
```
**Error:**
```json
{
  "success": false,
  "error": {
    "code": "SHIFT_CLOSED",
    "message": "Shift untuk laci kas Anda belum dibuka.",
    "details": {}
  },
  "meta": {
    "server_time": "2026-11-26T15:10:00+07:00",
    "protocol_version": "1.1"
  }
}
```

### 2.3. Kode Error Utama
- `400 VALIDATION_ERROR` — input tidak valid.
- `401 UNAUTHORIZED_DEVICE` / `UNAUTHORIZED_SESSION` — device token / session token invalid atau expired.
- `401 REPLAY_TIMESTAMP_EXPIRED` / `REPLAY_NONCE_DETECTED` / `INVALID_SIGNATURE` — gagal validasi anti-replay atau HMAC.
- `403 TERMINAL_REVOKED` — terminal dicabut Admin; Staff hapus token lokal dan kembali ke `PairingScreen`.
- `403 PERMISSION_DENIED` / `DRAWER_DISABLED_FOR_TERMINAL` — tidak punya permission atau fitur laci kas dinonaktifkan Admin untuk terminal tersebut.
- `404 NOT_FOUND` — resource / idempotency key tidak ditemukan.
- `409 SHIFT_CLOSED` / `SHIFT_CONFLICT` — shift belum dibuka atau kasir/laci sudah punya shift aktif lain.
- `409 INSUFFICIENT_STOCK` / `PRICE_OR_PROMO_CHANGED` / `INSUFFICIENT_CREDIT` / `INVALID_CUSTOMER_RULE`.
- `429 PIN_RATE_LIMITED` — batas percobaan PIN gagal terlampaui (menyertakan `retry_after_seconds`).
- `503 PRINTER_NOT_HEADLESS` / `PRINTER_OFFLINE` — printer hanya `system` PDF atau printer target tidak terhubung.

---

## 3. Daftar Lengkap Endpoint REST API Final

### 3.1. Discovery, Pairing, & Rotasi Secret/Sertifikat
1. **`GET /api/v1/health`** *(Publik terbatas di LAN)*
   - Cek kesiapan server Admin. Mengembalikan: `status`, `server_id`, `app_version`, `protocol_version`, `store_name`, `drawer_mode` (`SHARED_DRAWER` | `INDIVIDUAL_DRAWER`), `server_time`, `server_time_ms` (untuk kalibrasi clock skew offline LAN).
2. **`POST /api/v1/pairing/register`** *(Auth: `pairing_code` single-use TTL 5 menit)*
   - Pada pairing manual IP, pengguna wajib memverifikasi **6–8 karakter checksum `cert_sha256`** yang tampil di layar Admin sebelum menukar `pairing_code`.
   - Request: `{ "pairing_code": "492817", "device_uuid": "...", "device_name": "HP Kasir 2", "app_version": "1.0.0" }`
   - Response `200`: `{ "terminal_id": "TERM-01", "terminal_code": "S1", "terminal_name": "HP Kasir 2", "device_token": "...", "device_secret": "...", "store_name": "...", "drawer_mode": "INDIVIDUAL_DRAWER", "assigned_cash_register_id": 2, "allow_auto_open_drawer": false, "allow_manual_open_drawer": false, "heartbeat_interval_sec": 4 }`.
3. **`POST /api/v1/pairing/verify`** *(Auth: Device + HMAC)*
   - Memverifikasi `terminal_id` belum dicabut dan mengembalikan konfigurasi terminal terkini (`allow_auto_open_drawer`, `allow_manual_open_drawer`, `assigned_cash_register_id`, `cert_rotation_pending`).
4. **`POST /api/v1/pairing/rotate-secret`** *(Auth: Device + HMAC)*
   - Rotasi berkala atau darurat atas `device_token` dan `device_secret` oleh terminal terotentikasi; token lama segera dinonaktifkan setelah response `200` diterima / konfirmasi berikutnya.
5. **`GET /api/v1/security/cert-info`** *(Auth: Device + HMAC)*
   - Mengambil informasi masa berlaku sertifikat TLS Admin dan `next_cert_sha256` (jika Admin menyiapkan rotasi sertifikat) agar terminal bisa melakukan *graceful pin update* sebelum sertifikat lama kedaluwarsa.
6. **`POST /api/v1/pairing/unpair`** *(Auth: Device + HMAC)*
   - Mencabut token terminal dari sisi Staff secara bersih.

### 3.2. Autentikasi Kasir (PIN Individual) & Daftar Kasir
7. **`GET /api/v1/auth/cashiers`** *(Auth: Device + HMAC — hanya terminal ter-pairing)*
   - Mengembalikan daftar kasir aktif yang memiliki izin `access_pos` (`[{ "id": 3, "name": "Kasir 1", "username": "kasir", "role": "cashier" }]`) tanpa informasi sensitif (`pin_hash`/`password_hash`).
8. **`POST /api/v1/auth/pin-login`** *(Auth: Device + HMAC + Rate Limited)*
   - Request: `{ "user_id": 3, "pin": "1111" }` (**`user_id` wajib** agar verifikasi KDF berjalan O(1) per akun tanpa linear scan & tanpa timing side-channel).
   - Admin memverifikasi KDF hash (`v2_pbkdf2` / `v2_argon2id`, atau `legacy_v1` + *transparent re-hash upgrade* ke `v2` saat login valid), cek `is_active = 1` & `access_pos = true`, catat `audit_logs` (`login`), terbitkan `session_token` & `expires_at`, serta mengembalikan `permissions` (termasuk `apply_discount`, `manage_customers`, `open_cash_drawer`), `drawer_mode`, dan `current_shift`.
9. **`POST /api/v1/auth/pin-logout`** *(Auth: Device + Session + HMAC)*
   - Mengakhiri `session_token` dan mencatat `audit_logs` (`logout`).
10. **`GET /api/v1/auth/me`** *(Auth: Device + Session + HMAC)*
    - Memvalidasi session aktif dan mengambil pembaruan `permissions` serta kebijakan laci terminal.

### 3.3. Pengaturan Toko, Laci Kas (`cash_registers`), & Shift
11. **`GET /api/v1/store/bootstrap`** *(Auth: Device + Session + HMAC)*
   - Mengembalikan profil toko non-sensitif (`store_name`, `store_address`, `store_phone`, `business_type`, `currency_symbol`, `tax_enabled`, `tax_rate`), `drawer_mode`, `receipt_config` (`ReceiptConfigModel`), dan kebijakan terminal (`allow_auto_open_drawer`, `allow_manual_open_drawer`, `auto_print_staff_transactions`).
12. **`GET /api/v1/cash-registers`** *(Auth: Device + Session + HMAC)*
    - Mengembalikan daftar `cash_registers` aktif yang diizinkan untuk kasir/terminal sesuai `cash_register_assignments` (beserta status apakah sedang dipakai oleh shift `'open'`).
13. **`GET /api/v1/shifts/current`** *(Auth: Device + Session + HMAC)*
    - Menyesuaikan `drawer_mode`:
      - Pada `SHARED_DRAWER`: mengembalikan shift `'open'` pada `cash_register_id` bersama (`REG-MAIN` / laci yang di-assign).
      - Pada `INDIVIDUAL_DRAWER`: mengembalikan shift `'open'` milik `cashier_id` / `cash_register_id` terminal tersebut.
    - Response memuat: `{ "drawer_mode": "...", "is_open": true, "cash_register": { "id": 2, "register_code": "REG-S1", "name": "Laci Kasir S1" }, "shift": { "id": 18, "cashier_id": 3, "cashier_name": "Kasir 1", "terminal_id": "TERM-01", "cash_register_id": 2, "start_time": "...", "status": "open" } }`.
14. **`POST /api/v1/shifts/open`** *(Auth: Device + Session + HMAC + `X-Idempotency-Key`)*
    - Digunakan terutama pada mode `INDIVIDUAL_DRAWER` (atau bila Admin mengizinkan kasir membuka shift laci sendiri).
    - Request: `{ "cash_register_id": 2, "starting_cash": 150000.0 }`.
    - Validasi Admin: pastikan `starting_cash >= 0`, kasir/terminal berhak atas `cash_register_id` (`cash_register_assignments`), laci target aktif & belum dipakai shift lain, dan (pada `INDIVIDUAL_DRAWER`) kasir belum memiliki shift `'open'` lain; pada `SHARED_DRAWER`, tolak jika sudah ada shift `'open'` pada laci bersama atau jika terminal tidak diizinkan membuka shift bersama.
15. **`POST /api/v1/shifts/close`** *(Auth: Device + Session + HMAC)*
    - Penutupan shift (Blind Cash Count) oleh kasir pemilik shift tersebut (khusus shift miliknya pada `INDIVIDUAL_DRAWER` atau jika diizinkan pada `SHARED_DRAWER`).
    - Request: `{ "shift_id": 18, "actual_cash": 450000.0, "note": "Sesuai hitungan fisik" }`.
    - Admin menghitung `difference = actual_cash - expected_cash` dan mewajibkan `note` jika `difference != 0` (konsisten dengan `DatabaseHelper.closeShift`).

### 3.4. Katalog Produk, Barcode, Promo, & Pelanggan (Read-Only Sync)
16. **`GET /api/v1/catalog/products?page=1&limit=200&since_version=0`** *(Auth: Device + Session + HMAC)*
    - Mengembalikan `ProductModel` terhidrasi `units` (`product_units`) & `tiered_prices` (`tiered_prices`) beserta `pagination: { page, limit, total, has_more }`.
    - **Delta Tombstones:** Saat `since_version > 0`, produk yang dinonaktifkan (`is_active = false`) **tetap disertakan** dalam delta agar Staff dapat menonaktifkannya dari cache lokal (saat `since_version == 0`, cukup kirim `is_active = true`).
    - **Field `cost_price`, `quarantine_stock`, `damaged_stock` dihapus total** (tidak pernah dikirim ke Staff).
17. **`GET /api/v1/catalog/barcode/{code}`** *(Auth: Device + Session + HMAC)*
    - Memetakan `DatabaseHelper.findProductAndUnitByBarcode(code)`.
18. **`GET /api/v1/catalog/promos`** *(Auth: Device + Session + HMAC)*
    - Memetakan `DatabaseHelper.getActivePromos()` yang sedang aktif.
19. **`GET /api/v1/customers?query=&page=1&limit=100`** *(Auth: Device + Session + HMAC)*
    - Memetakan `DatabaseHelper.getCustomers()` dengan `pagination` standar.
20. **`GET /api/v1/customers/{id}/credit-balance`** *(Auth: Device + Session + HMAC)*
    - Memetakan `DatabaseHelper.getCustomerCreditBalance(id)`.
21. **`POST /api/v1/customers`** *(Auth: Device + Session + HMAC, wajib permission `manage_customers`)*
    - Memetakan `DatabaseHelper.insertCustomer()`.

### 3.5. Transaksi Terpusat (Authoritative Admin Checkout)
22. **`POST /api/v1/transactions`** *(Auth: Device + Session + HMAC + Wajib `X-Idempotency-Key`)*
    - **Request:**
    ```json
    {
      "idempotency_key": "7f3c8e2b-9a10-4b23-889a-2299441100aa",
      "shift_id": 18,
      "cash_register_id": 2,
      "customer_id": null,
      "customer_name": "Pelanggan Umum",
      "customer_phone": "",
      "promo_id": null,
      "manual_discount": 0.0,
      "payment_method": "tunai",
      "credit_used": 0.0,
      "amount_paid": 100000.0,
      "expected_grand_total": 67000.0,
      "note": "",
      "request_print": true,
      "items": [
        {
          "product_id": 1,
          "unit_name": "Pcs",
          "conversion_factor": 1.0,
          "qty": 2.0,
          "item_discount": 0.0
        }
      ]
    }
    ```
    - **Logika Server POS Admin (`db.transaction` atomik):**
      1. Cek `idempotency_key` di `transactions`: bila sudah ada, kembalikan `200 OK` dengan payload transaksi existing (tanpa double-insert / double-deduct!).
      2. Validasi ulang `shift_id` & `cash_register_id` sesuai `drawer_mode` dan `cash_register_assignments`: shift harus `'open'`, `cash_register_id` diizinkan untuk kasir/terminal, dan pada `INDIVIDUAL_DRAWER` `shift.cashier_id` harus sama dengan kasir login.
      3. Validasi izin diskon (`AppPermissions.applyDiscount`) jika ada `manual_discount > 0` atau `item_discount > 0`.
      4. Hitung ulang harga jual (`products` / `product_units` / `tiered_prices`), promo (`promos`), pajak (`store_settings`), validasi stok jual, validasi pelanggan terdaftar (`kasbon`/`saldo_kredit`), dan saldo kredit live (`customer_credit_ledger`).
      5. Terbitkan `invoice_number` resmi, simpan `transactions` (mencatat `cashier_id`, `terminal_id`, `shift_id`, `cash_register_id`, `idempotency_key`) + `transaction_items` + `inventory_movements` + update `shifts` + `audit_logs`.
      6. **Setelah commit DB sukses**, jika `request_print == true` (atau `auto_print_staff_transactions == true`), enqueue `print_jobs` (`idempotency_key = "AUTO:" + trx.idempotency_key`). Pulse `open_drawer` **HANYA** dikirim sekali (`drawer_pulse_sent = 0 -> 1`) apabila `payment_method == 'tunai'` **DAN** `paired_terminal.allow_auto_open_drawer == true` **DAN** printer terhubung BT/USB/LAN dengan `printer.openDrawer == true`. Retry cetak tidak pernah mengirim ulang pulse laci!
      7. Broadcast event WSS `stock_updated`.
    - **Response `201 Created`:** Mengembalikan objek transaksi lengkap resmi (`id`, `invoice_number`, `date`, `cashier_id`, `cashier_name`, `terminal_id`, `shift_id`, `cash_register_id`, `subtotal`, `discount_total`, `tax_amount`, `grand_total`, `payment_method`, `credit_used`, `amount_paid`, `change_amount`, `qr_code_payload`, `printer_snapshot_json`, `items[]` tanpa `cost_price`) + status `print_job`.

23. **`GET /api/v1/transactions/by-idempotency/{key}`** *(Auth: Device + Session + HMAC)*
    - Rekonsiliasi transaksi in-flight saat koneksi sempat terputus. Mengembalikan `200 OK` (struktur sama dengan `POST /transactions`) atau `404 NOT_FOUND`.

24. **`GET /api/v1/transactions?scope=terminal&page=1&limit=30`** *(Auth: Device + Session + HMAC)*
    - Daftar transaksi terbaru milik `terminal_id` (dan/atau `cashier_id` shift aktif) untuk kebutuhan riwayat cetak ulang struk, disertai `pagination: { page, limit, total, has_more }`.

### 3.6. Printer & Cash Drawer Terpusat
25. **`GET /api/v1/printers/status`** *(Auth: Device + Session + HMAC)*
    - Mengembalikan printer yang terkait dengan terminal/laci (atau default printer Admin), tipe koneksi (`bluetooth`/`usb`/`lan`/`system`), `headless_supported`, status izin USB OTG (`usb_permission_granted`), serta flag `allow_auto_open_drawer` & `allow_manual_open_drawer`.
26. **`POST /api/v1/print/receipt`** *(Auth: Device + Session + HMAC + `X-Idempotency-Key`)*
    - Request: `{ "invoice_number": "...", "is_reprint": true }`.
    - Aturan keras: saat `is_reprint == true`, pulse buka laci **SELALU `false`**!
    - Setiap reprint sukses mencatat `audit_logs` (`cetak_ulang_struk`).
27. **`GET /api/v1/print/jobs/{jobId}`** *(Auth: Device + Session + HMAC)*
    - Cek status cetak (`queued` | `printing` | `printed` | `failed` | `requires_admin_manual_print` | `usb_permission_required`).
28. **`POST /api/v1/printers/open-drawer`** *(Auth: Device + Session + HMAC + `X-Idempotency-Key`)*
    - Request: `{ "reason": "Tukar uang kembalian pelanggan", "cash_register_id": 2 }`.
    - Validasi wajib: `paired_terminal.allow_manual_open_drawer == true` **DAN** `user.hasPermission(AppPermissions.openCashDrawer) == true` **DAN** kasir berhak atas `cash_register_id` dengan shift `'open'` terkait -> eksekusi `PrinterManager.openCashDrawer(...)` -> wajib tulis `audit_logs` (`action_type: 'buka_laci'`, mencatat `user_id`, `terminal_id`, `cash_register_id`, `shift_id`, `reason`).

---

## 4. Kontrak WebSocket (`/ws/v1/terminal`) & Reconnect Catch-Up

- **Transport:** `wss://<admin_ip>:<port>/ws/v1/terminal` dengan TLS Cert Pinning + header handshake ter-sign HMAC (`X-Terminal-Id`, `X-Device-Token`, `Authorization`, `X-Request-Timestamp`, `X-Request-Nonce`, `X-Signature`).
- **Heartbeat:** Client kirim `{"type":"ping","ts":...}` tiap **4 detik**; Admin balas `{"type":"pong","ts":...,"shift_open":true,"sync_version":108}`. Putus setelah 2x gagal (~9 detik).
- **Mekanisme Reconnect & Anti-Missed-Event:** Saat WSS reconnect berhasil, Admin mengirim frame `hello` berisi `sync_version`, `drawer_mode`, dan `current_shift`. Jika `hello.sync_version > local.last_sync_version`, Staff otomatis memicu `GET /catalog/products?since_version=...`, `GET /catalog/promos`, `GET /shifts/current`, dan polling `GET /print/jobs/{jobId}` untuk job yang masih berstatus `queued`/`printing`.
- **Event Server -> Client:**
  - `hello`, `pong`, `stock_updated`, `catalog_changed`, `promo_changed`, `settings_changed`, `shift_changed`, `print_job_updated`, `terminal_policy_updated`, `terminal_revoked`, `server_stopping`.
