# SECURITY_GUIDE.md — Arsitektur & Kontrol Keamanan Sistem POS Multi-Device

## 1. Keamanan Kredensial & KDF v2 (`kasirtoko`)
- **Algoritma:** RFC 8018 PBKDF2-HMAC-SHA256 (`600.000` iterasi produksi, 32-byte key) melalui `SecurityHelper` (`pointycastle` / native `SecretKeyFactory PBKDF2WithHmacSHA256` Android API 26+).
- **Domain Separation & Salt Unik:** Salt acak unik per akun dan terpisah antara `password` (`domainPassword`) dan `PIN` (`domainPin`).
- **Hardware Pepper:** `kasirtoko_pepper_kek_v1` disimpan pada `AndroidKeyStore` (AES-256-GCM) di dalam `MainActivity.kt`, terpisah dari file `kasirtoko.db` & `BackupService`.
- **Transparent Migration:** Akun `legacy_v1` secara otomatis di-rehash ke `v2_pbkdf2_sha256` saat login pertama yang valid, tercatat ke `audit_logs` (`migrasi_kdf_akun`).
- **Brute-Force PIN Protection:** Progressive exponential lockout (`60s` / `300s` / `900s`) per akun & per `terminal_id`, mengembalikan HTTP `429 PIN_RATE_LIMITED` dengan `retry_after_seconds`.

## 2. Penyimpanan Secret Hardware & Proteksi Backup
- **POS Admin (`SecretVault`):**
  - `device_secret` tiap terminal Staff TIDAK pernah disimpan sebagai teks polos di SQLite. Kolom `paired_terminals.device_secret_enc` menyimpan amplop AES-256-GCM yang dibungkus oleh key `kasirtoko_vault_kek_v1` di `AndroidKeyStore`.
  - Kunci privat sertifikat TLS (`tls_server_identity_v1`) disimpan di `SharedPreferences` privat terenkripsi (`allowBackup="false"`) melalui `SecretVault` — tidak ikut tersalin saat user melakukan backup `.db` via `BackupService`.
- **POS Staff (`AndroidKeystoreCredentialStore`):**
  - Kredensial `device_token`, `device_secret`, `tls_cert_sha256`, `next_cert_sha256`, dan `cashier_session_token` disimpan terenkripsi oleh `stafkasirtoko_vault_kek_v1` (`AndroidKeyStore` AES-256-GCM), `allowBackup="false"`, `usesCleartextTraffic="false"`.

## 3. Transport TLS & Certificate Pinning
- `TlsCertificateManager` membangkitkan sertifikat X.509 v3 RSA-2048 self-signed dengan `SubjectAltName` IP lokal + DNS lokal (`localhost`, `kasirtoko.local`), mengekspor DER SHA-256 fingerprint dan PIN pendek 8 karakter.
- `LanHttpClient` & `LanWsClient` memvalidasi `sha256(X509Certificate.der)` di `badCertificateCallback`. Koneksi ditolak seketika (`HandshakeException`) apabila sertifikat tidak cocok dengan fingerprint yang dipin saat QR/manual pairing.
- **Rotasi Bertahap:** Admin memanggil `stageCertificateRotation()`; terminal aktif mengunduh `next_cert_sha256` dari `GET /api/v1/security/cert-info` sebelum pergantian sertifikat agar trust tidak terputus mendadak.

## 4. HMAC Request Signing & Perlindungan Replay Attack
- Setiap endpoint terautentikasi memverifikasi:
  1. `X-Terminal-Id` + `X-Device-Token` (dibandingkan terhadap SHA-256 `device_token_hash` dengan `constantTimeEquals`).
  2. Status `paired_terminals.is_revoked == 0` (jika dicabut -> `403 TERMINAL_REVOKED`).
  3. `X-Request-Timestamp` berada dalam toleransi `±120.000 ms` terhadap jam server Admin (dikali/kalibrasi offset dari `/api/v1/health`).
  4. `X-Request-Nonce` unik per terminal selama window 150 detik (`REPLAY_NONCE_DETECTED` bila dipakai ulang).
  5. `X-Signature` valid atas payload kanonik `METHOD\nPATH_AND_QUERY\nTIMESTAMP\nNONCE\nSHA256_BODY`.
  6. `Authorization: Bearer <session_token>` masih aktif, belum expired (`8 jam`), belum dicabut (`SESSION_REVOKED`), dan akun kasir `is_active = 1`.

## 5. Otorisasi Laci Kas, Pencabutan & Kebocoran Data
- Field sensitif **`cost_price`**, **`quarantine_stock`**, **`damaged_stock`**, `pin_hash`, `password_hash`, `device_secret_hash`, `device_token_hash` dihapus permanen dari seluruh serializer REST/WSS Staff dan skema SQLite Staff.
- Perubahan hak akses / penonaktifan kasir di Admin langsung mencabut seluruh `terminal_sessions` milik kasir tersebut.
- Pencabutan terminal langsung menutup WebSocket aktif dengan kode `4003` dan menolak seluruh API call selanjutnya dengan `403`.
