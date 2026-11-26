# API_DOCUMENTATION.md — Dokumentasi Resmi API HTTPS & WSS POS Admin (`v1.1`)

Base URL: `https://<admin-ip>:<port>` (Default port: `8443`)  
WebSocket URL: `wss://<admin-ip>:<port>/ws/v1/terminal`  
Versi Protokol: `1.1`

## 1. Keamanan Transport & Request Signing
Semua request terotentikasi wajib menyertakan header berikut:
- `Content-Type: application/json; charset=utf-8`
- `X-API-Version: 1.1`
- `X-Terminal-Id: <terminal_id>`
- `X-Device-Token: <device_token>`
- `X-Request-Timestamp: <unix_epoch_ms_calibrated>` (toleransi drift ±120.000 ms terhadap jam Admin)
- `X-Request-Nonce: <uuid_v4>` (ditolak bila dipakai ulang dalam 150 detik)
- `X-Signature`: HMAC-SHA256 hex dengan `device_secret` atas string kanonik:
  ```text
  METHOD\nPATH_AND_QUERY\nTIMESTAMP_MS\nNONCE\nSHA256_HEX_BODY
  ```
- `Authorization: Bearer <cashier_session_token>` (untuk seluruh endpoint pasca-login PIN)
- `X-Idempotency-Key: <uuid_v4>` (wajib pada `POST /transactions`)

Seluruh respons dibungkus envelope standar:
```json
{
  "success": true,
  "data": {},
  "meta": {
    "server_time": "2026-11-26T18:30:00.000",
    "protocol_version": "1.1",
    "sync_version": 12
  }
}
```

## 2. Daftar Endpoint REST API (`/api/v1`)

| Kelompok | Method & Path | Autentikasi | Ringkasan |
| :--- | :--- | :--- | :--- |
| Health | `GET /api/v1/health` | Publik LAN (Pinned TLS) | Cek status server, `server_time_ms`, `drawer_mode`, `cert_pin_short` |
| Pairing | `POST /api/v1/pairing/register` | `pairing_code` (TTL 5 menit, single-use) | Tukar kode pairing dengan `terminal_id`, `device_token`, `device_secret` |
| Pairing | `POST /api/v1/pairing/verify` | Device + HMAC | Verifikasi status terminal & kebijakan aktif |
| Pairing | `POST /api/v1/pairing/rotate-secret` | Device + HMAC | Rotasi `device_token` & `device_secret` baru |
| Security | `GET /api/v1/security/cert-info` | Device + HMAC | Info `current_cert_sha256`, `expires_at`, & `next_cert_sha256` |
| Pairing | `POST /api/v1/pairing/unpair` | Device + HMAC | Cabut akses terminal dari sisi Staff |
| Auth | `GET /api/v1/auth/cashiers` | Device + HMAC | Daftar user aktif berizin `access_pos` (tanpa hash/PIN) |
| Auth | `POST /api/v1/auth/pin-login` | Device + HMAC + Rate Limit | Verifikasi KDF v2 `(user_id, pin)` & terbitkan `session_token` |
| Auth | `POST /api/v1/auth/pin-logout` | Device + Session + HMAC | Cabut `session_token` aktif |
| Auth | `GET /api/v1/auth/me` | Device + Session + HMAC | Validasi sesi, permissions, & shift aktif |
| Store | `GET /api/v1/store/bootstrap` | Device + Session + HMAC | Profil toko non-sensitif, pajak, `receipt_config`, kebijakan laci |
| Registers | `GET /api/v1/cash-registers` | Device + Session + HMAC | Daftar laci aktif, izin akses terminal/kasir, & status shift |
| Shifts | `GET /api/v1/shifts/current` | Device + Session + HMAC | Shift aktif sesuai `SHARED_DRAWER` / `INDIVIDUAL_DRAWER` |
| Shifts | `POST /api/v1/shifts/open` | Device + Session + HMAC | Buka shift pada `cash_register_id` yang sah (`201`) |
| Shifts | `POST /api/v1/shifts/close` | Device + Session + HMAC | Blind count close shift (wajib `note` jika `difference != 0`) |
| Catalog | `GET /api/v1/catalog/products?page=1&limit=150&since_version=0` | Device + Session + HMAC | Daftar produk + `units` + `tiered_prices` + tombstone (`is_active=false`) tanpa `cost_price` |
| Catalog | `GET /api/v1/catalog/barcode/{code}` | Device + Session + HMAC | Lookup produk & satuan berdasarkan barcode/kode/IMEI tanpa `cost_price` |
| Catalog | `GET /api/v1/catalog/promos` | Device + Session + HMAC | Promo berjalan saat ini |
| Customers | `GET /api/v1/customers?query=&page=1&limit=100` | Device + Session + HMAC | Daftar pelanggan & `credit_balance` |
| Customers | `POST /api/v1/customers` | Device + Session + HMAC (`manage_customers`) | Tambah pelanggan baru terpusat di Admin (`201`) |
| Customers | `GET /api/v1/customers/{id}/credit-balance` | Device + Session + HMAC | Detail saldo kredit & piutang aktif |
| Transactions | `POST /api/v1/transactions` | Device + Session + HMAC + `X-Idempotency-Key` | Checkout otoritatif server (hitung ulang harga/promo/pajak, stok atomik, print enqueue) |
| Transactions | `GET /api/v1/transactions/by-idempotency/{key}` | Device + Session + HMAC | Rekonsiliasi transaksi in-flight (`200` / `404`) |
| Transactions | `GET /api/v1/transactions?scope=terminal&page=1&limit=30` | Device + Session + HMAC | Riwayat transaksi terminal (tanpa `cost_price`) |
| Printers | `GET /api/v1/printers/status` | Device + Session + HMAC | Status printer target, dukungan headless, kebijakan laci |
| Printers | `POST /api/v1/print/receipt` | Device + Session + HMAC | Enqueue cetak / reprint (`is_reprint: true` selalu kunci laci & tulis audit log) |
| Printers | `GET /api/v1/print/jobs/{jobId}` | Device + Session + HMAC | Poll status print job (`queued`/`processing`/`submitted`/`retrying`/`failed`/`cancelled`) |
| Printers | `POST /api/v1/printers/open-drawer` | Device + Session + HMAC | Buka laci manual (butuh `allow_manual_open_drawer`, izin `open_cash_drawer`, & alasan audit) |

## 3. Event WebSocket (`/ws/v1/terminal`)
- **Handshake:** Upgrade HTTPS terautentikasi `Device + HMAC + Session`.
- **Frame Server -> Client:** `hello`, `pong`, `stock_updated`, `catalog_changed`, `promo_changed`, `customer_changed`, `settings_changed`, `shift_changed`, `print_job_updated`, `terminal_policy_updated`, `terminal_revoked` (diikuti close `4003`), `session_revoked`, `server_stopping`.
- **Heartbeat:** Client mengirim `{"type":"ping","ts":...}` tiap 4 detik; server membalas `{"type":"pong","sync_version":...,"shift_open":...}`.
