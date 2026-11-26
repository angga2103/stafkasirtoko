# KasirToko Staff — Terminal Kasir POS Multi-Device

[![KasirToko Staff CI](https://github.com/angga2103/stafkasirtoko/actions/workflows/ci.yml/badge.svg)](https://github.com/angga2103/stafkasirtoko/actions/workflows/ci.yml)

Aplikasi Android **POS Staff Terminal** (`com.kasirtoko.app.stafkasirtoko`) yang terhubung ke server **POS Admin (`kasirtoko`)** melalui jaringan Wi-Fi router lokal atau hotspot Android Admin via **HTTPS REST API** (`/api/v1/*`) dan **WebSocket** (`/ws/v1/terminal`).

## Arsitektur Inti
- **Server-Authoritative:** Seluruh harga produk/bertingkat, promo, diskon, pajak, stok, kredit/Kasbon, shift, dan pencetakan thermal divalidasi serta disimpan secara atomik oleh POS Admin (`kasirtoko`).
- **Cache-Only Terminal (`staff_terminal.db`):** POS Staff **tidak memiliki** database transaksi pusat kedua, akun pengguna pusat, maupun kolom `cost_price`.
- **Keamanan Berlapis:** Pairing QR sekali pakai + TLS X.509 SHA-256 certificate pinning + request signing HMAC-SHA256 + timestamp (`±120 detik`) + nonce anti-replay + penyimpanan secret terenkripsi `AndroidKeyStore`.
- **Proteksi Jaringan & Offline Lock:** Keranjang persisten di SQLite lokal + hard checkout lock saat koneksi ke Admin terputus atau shift belum dibuka + rekonsiliasi transaksi in-flight via idempotency key.

## Dokumentasi Lengkap
- [`docs/FINAL_ARCHITECTURE.md`](docs/FINAL_ARCHITECTURE.md) — Arsitektur topologi multi-device final Admin & Staff.
- [`docs/ADMIN_SERVER_GUIDE.md`](docs/ADMIN_SERVER_GUIDE.md) — Panduan pengoperasian server POS Admin & Foreground Service.
- [`docs/STAFF_APP_GUIDE.md`](docs/STAFF_APP_GUIDE.md) — Panduan penggunaan aplikasi POS Staff & 6 state terminal.
- [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md) — Kontrak REST API (`/api/v1/*`), header HMAC, dan event WebSocket.
- [`docs/DATABASE_MIGRATION_GUIDE.md`](docs/DATABASE_MIGRATION_GUIDE.md) — Skema SQLite Admin v6 & cache lokal Staff v1.
- [`docs/SECURITY_GUIDE.md`](docs/SECURITY_GUIDE.md) — TLS pinning, Keystore vault, KDF v2 PBKDF2-SHA256, & rotasi sertifikat.
- [`docs/PRINTER_SETUP_GUIDE.md`](docs/PRINTER_SETUP_GUIDE.md) — Print queue serial, fallback, & aturan buka laci kas RJ11.
- [`docs/GITHUB_ACTIONS_GUIDE.md`](docs/GITHUB_ACTIONS_GUIDE.md) — Pipeline CI/CD build APK & signing secrets.
- [`docs/DEPLOYMENT_GUIDE.md`](docs/DEPLOYMENT_GUIDE.md) — Panduan pairing & deployment LAN Multi-Device.
- [`docs/FINAL_QA_REPORT.md`](docs/FINAL_QA_REPORT.md) — Laporan hasil test otomatis, benchmark kapasitas, build APK & batasan hardware.

## Pengujian & Build Lokal
```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub -r expanded -j 1
flutter build apk --debug --no-tree-shake-icons --android-skip-build-dependency-validation
```
