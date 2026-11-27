# Kebijakan Keamanan Sesi & Manajemen Akun Multi-Device KasirToko

Dokumen ini menetapkan aturan desain keamanan akun, batas sesi atomik per role/akun, mekanisme pencabutan sesi instan, serta penyimpanan lokal minimal di terminal Staff.

## 1. Prinsip Penyimpanan & Kredensial Staff (`SecureCredentialStore`)

- Kredensial sensitif terminal (`device_token`, `device_secret`, `session_token`, `tls_cert_sha256`, `next_cert_sha256`, `server_id`, endpoint failover) dibungkus dan disimpan menggunakan Android Keystore via `AndroidKeystoreCredentialStore`.
- PIN dan Password karyawan disimpan di Admin menggunakan **SecurityHelper KDF v2** (PBKDF2-HMAC-SHA256 600.000 iterasi di produksi + salt unik + Keystore pepper + pemisahan domain, serta rate limiting/lockout).
- Terminal Staff tidak pernah menerima atau menyimpan `cost_price`, margin laba, laporan keuangan pusat, maupun database `users`.

## 2. Kebijakan Batas Sesi Aktif (`session_policies` & `users.max_active_sessions`)

### Default per Role (`AppRoles.defaultMaxActiveSessions`)
- `cashier` (Kasir): **1** HP aktif bersamaan
- `warehouse` (Gudang): **1** HP aktif bersamaan
- `technician` (Teknisi): **1** HP aktif bersamaan
- `delivery` (Kurir / Antar): **1** HP aktif bersamaan
- `supervisor` (Supervisor): **2** HP aktif bersamaan
- `admin` (Admin): **2** HP aktif bersamaan
- `owner` (Pemilik / Owner): **3** HP aktif bersamaan

### Hirarki Resolusi (`DatabaseHelper.resolveEffectiveMaxSessionsTxn`)
1. Jika akun memiliki nilai `users.max_active_sessions > 0`, nilai per-akun tersebut digunakan sebagai prioritas tertinggi.
2. Jika kosong (`NULL`), sistem membaca tabel `session_policies` untuk `role` akun bersangkutan (dapat diubah Owner/Admin berizin melalui menu **Manajemen Karyawan -> Kebijakan Batas Sesi**).
3. Fallback terakhir adalah default kode `AppRoles.defaultMaxActiveSessions(role)`.

## 3. Penegakan Atomik Tanpa Auto-Logout Diam-Diam (`MultiDeviceDao.issueSession`)

- Saat `/api/v1/auth/pin-login` dipanggil, server memperoleh mutex per-kasir (`_runWithCashierSessionLock`) dan mengeksekusi transaksi SQLite `transaction(...)` untuk:
  1. Menghitung baris aktif di `terminal_sessions` (`revoked_at IS NULL AND expires_at > now`).
  2. Membandingkan jumlah sesi aktif di **terminal lain** terhadap batas `maxAllowed`.
  3. Jika sudah mencapai batas (`>= maxAllowed`), **permintaan login baru ditolak** (`HTTP 409 Conflict`, error code **`SESSION_LIMIT_EXCEEDED`**) dan dicatat ke audit log dengan aksi `login_staff_ditolak_batas_sesi`.
- **Anti-Hijack:** Login baru yang ditolak **tidak pernah mencabut** sesi HP yang sedang dipakai secara diam-diam. Jika kasir resmi perlu pindah HP atau HP lama tertinggal/hilang, Admin wajib mencabut sesi lama terlebih dahulu.
- Jika login datang dari `terminal_id` yang sama yang sudah memiliki sesi akun yang sama, sesi lama di terminal yang sama diganti bersih tanpa menambah kuota berlebih.

## 4. Pencabutan Sesi, Penonaktifan Akun & Terminal (`HTTP + WebSocket`)

1. **Cabut Sesi Perangkat Tertentu (`revokeSessionById`):**
   - Menandai `revoked_at`, `revoked_reason`, dan `revoked_by` pada baris `terminal_sessions`.
   - Server mengirim event WS `session_revoked` lalu menutup socket sesi bersangkutan dengan close code **`4001`**, mencatat audit log `cabut_sesi_staff`.
2. **Cabut Semua Sesi Akun (`revokeAllSessionsForCashier`):**
   - Mencabut seluruh token aktif milik akun tersebut pada semua HP Staff, memutus seluruh WebSocket aktif milik akun tersebut, mencatat audit log `cabut_semua_sesi_akun`.
3. **Nonaktifkan Akun Karyawan (`DatabaseHelper.setUserActive(userId, false)`):**
   - Menolak login baru dan mencabut semua `terminal_sessions` aktif milik karyawan tersebut sekaligus memicu callback pemutusan socket HTTP/WS.
   - **Perlindungan Shift Bersama:** Pencabutan sesi atau penonaktifan akun **tidak otomatis menutup shift bersama** (`SHARED_DRAWER`) pada mesin laci kas yang masih digunakan kasir aktif lain.
4. **Cabut Akses Terminal (`MultiDeviceDao.revokeTerminal`):**
   - Menandai `paired_terminals.is_revoked = 1`, mencabut seluruh sesi terminal itu, memutus WS dengan close code **`4003`**, dan membuat Staff mengembalikan state `TerminalConnectionState.revoked` sambil membersihkan kredensial Keystore & cache lokal.
