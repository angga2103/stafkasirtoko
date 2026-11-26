# FINAL_ARCHITECTURE.md — Arsitektur Final Sistem POS Multi-Device (`kasirtoko` + `stafkasirtoko`)

## 1. Gambaran Topologi Sistem
Sistem POS Multi-Device terdiri dari dua aplikasi Android Flutter terpisah dengan tanggung jawab tegas:

```text
+-------------------------------------------------------------------+
|  POS ADMIN (c:\kasirtoko — com.kasirtoko.app.kasirtoko)            |
|  Pusat Database SQLite WAL v6, Bisnis, Stok, Keuangan & Printer    |
|                                                                   |
|  - Embedded HTTPS + WSS Server (`LanPosServer`, Port 8443)        |
|  - X.509 v3 RSA-2048 TLS + Keystore AES-256-GCM (`SecretVault`)   |
|  - Security Middleware: HMAC-SHA256, Timestamp ±120s, Nonce 150s  |
|  - `AuthoritativeCheckoutService`: mutex + db.transaction atomik  |
|  - `PrintQueueWorker`: serial FIFO BT/USB OTG/LAN + RJ11 guard    |
|  - `PosServerForegroundService` (`specialUse` + NetworkCallback)   |
+----------------------------------+--------------------------------+
                                   | LAN Wi-Fi Router / Hotspot
                                   | HTTPS (`POST/GET /api/v1/*`)
                                   | WSS (`/ws/v1/terminal`, 4s Ping)
                                   | TLS Pinning SHA-256 + HMAC
        +--------------------------+--------------------------+
        v                                                     v
+------------------------------+             +------------------------------+
| POS STAFF Terminal 1         |             | POS STAFF Terminal N         |
| (`com.kasirtoko.app.stafkasirtoko`)        |                              |
|                              |             |                              |
| - AndroidKeyStore Credentials|             | - Tidak ada limit hardcode   |
| - `LanHttpClient` & `LanWsClient`          | - Cache-only SQLite v1       |
| - Thin Terminal: NO cost_price,            |   (tanpa `transactions` &    |
|   NO second ledger, Offline Lock           |    tanpa `cost_price`)       |
+------------------------------+             +------------------------------+
```

## 2. Arsitektur Repository POS Admin (`c:\kasirtoko`)
- **Database Engine ([`db_helper.dart`](file:///c:/kasirtoko/lib/database/db_helper.dart), [`multi_device_dao.dart`](file:///c:/kasirtoko/lib/database/multi_device_dao.dart)):**
  - Skema SQLite v6 (`PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=ON`, `PRAGMA busy_timeout=5000`).
  - Memisahkan `cashier_id`, `terminal_id`, `shift_id`, dan `cash_register_id`.
  - Mendukung dual mode operasional `SHARED_DRAWER` dan `INDIVIDUAL_DRAWER` serta assignment laci deterministik (`cash_register_assignments`).
  - Tracking monotonic `catalog_sync_version` untuk delta sync katalog beserta tombstone penghapusan produk.
- **Keamanan & Kriptografi ([`security_helper.dart`](file:///c:/kasirtoko/lib/utils/security_helper.dart), [`secret_vault.dart`](file:///c:/kasirtoko/lib/services/secret_vault.dart), [`tls_certificate_manager.dart`](file:///c:/kasirtoko/lib/services/server/tls_certificate_manager.dart), [`MainActivity.kt`](file:///c:/kasirtoko/android/app/src/main/kotlin/com/kasirtoko/app/kasirtoko/MainActivity.kt)):**
  - PBKDF2-HMAC-SHA256 v2 (`600.000` iterasi) dengan salt terpisah PIN vs password serta Keystore pepper.
  - `SecretVault` AES-256-GCM membungkus `device_secret_enc` dan menyimpan privat key sertifikat TLS di luar database SQLite & di luar backup lokal.
  - X.509 v3 self-signed certificate manager dengan rotasi bertahap (`next_cert_sha256`).
- **Server Jaringan & Mesin Checkout ([`lan_pos_server.dart`](file:///c:/kasirtoko/lib/services/server/lan_pos_server.dart), [`request_security.dart`](file:///c:/kasirtoko/lib/services/server/request_security.dart), [`authoritative_checkout_service.dart`](file:///c:/kasirtoko/lib/services/server/authoritative_checkout_service.dart)):**
  - `HttpServer.bindSecure` + `WebSocketTransformer`.
  - Checkout server-otoritatif menghitung ulang harga satuan, tiered price, promo, diskon (validasi `apply_discount`), pajak, stok, kredit pelanggan, dan idempotency.
- **Print Server & Antrean Serial ([`print_queue_worker.dart`](file:///c:/kasirtoko/lib/services/server/print_queue_worker.dart), [`printer_manager.dart`](file:///c:/kasirtoko/lib/services/printer/printer_manager.dart)):**
  - Antrean serial `print_jobs` per printer, post-commit enqueue, dan atomik single-shot `drawer_pulse_sent`.
- **Android Service & UI ([`PosServerForegroundService.kt`](file:///c:/kasirtoko/android/app/src/main/kotlin/com/kasirtoko/app/kasirtoko/PosServerForegroundService.kt), [`server_provider.dart`](file:///c:/kasirtoko/lib/providers/server_provider.dart), [`multi_device_server_screen.dart`](file:///c:/kasirtoko/lib/screens/settings/multi_device_server_screen.dart)):**
  - Foreground Service `specialUse` terikat status server live, pengamatan perubahan IP LAN via `ConnectivityManager.NetworkCallback`, generator QR pairing, manajemen terminal dinamis, dan monitor print queue.

## 3. Arsitektur Repository POS Staff (`c:\StafKasirtoko`)
- **Keamanan & Jaringan ([`secure_credential_store.dart`](file:///c:/StafKasirtoko/lib/core/security/secure_credential_store.dart), [`request_signer.dart`](file:///c:/StafKasirtoko/lib/core/security/request_signer.dart), [`lan_http_client.dart`](file:///c:/StafKasirtoko/lib/core/network/lan_http_client.dart), [`lan_ws_client.dart`](file:///c:/StafKasirtoko/lib/core/network/lan_ws_client.dart)):**
  - Kredensial disimpan terenkripsi oleh `AndroidKeyStore` (`MainActivity.kt` Staff).
  - TLS certificate pinning wajib di `badCertificateCallback` (DER SHA-256).
  - Heartbeat WebSocket 4 detik + auto-reconnect exponential backoff + catch-up delta sync saat frame `hello`.
- **Local Cache Only ([`staff_local_db.dart`](file:///c:/StafKasirtoko/lib/data/local/staff_local_db.dart)):**
  - Tidak ada kolom `cost_price`, tidak ada ledger transaksi pusat kedua.
  - Keranjang persisten (`active_cart_items`), draft lokal (`local_held_orders`), intent rekonsiliasi in-flight (`pending_checkout_intents`), dan max 30 pratinjau struk terkonfirmasi (`recent_receipt_cache`).
- **State Machine & UI ([`staff_session_controller.dart`](file:///c:/StafKasirtoko/lib/providers/staff_session_controller.dart), [`main.dart`](file:///c:/StafKasirtoko/lib/main.dart), screens & dialogs):**
  - 6 state terminal (`unpaired`, `pairedOffline`, `connectedNoSession`, `onlineReady`, `shiftClosed`, `revoked`).
  - Hard checkout lock saat Admin unreachable / shift tertutup, dengan rekonsiliasi otomatis `GET /api/v1/transactions/by-idempotency/{key}` pasca terhubung ulang.
