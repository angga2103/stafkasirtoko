# STAFF_APP_TEST_PLAN.md — Rencana Pengujian Komprehensif, Migrasi, Keamanan, & Kapasitas

**Cakupan:** Pengujian POS Staff (`stafkasirtoko`), adapter server & migrasi DB POS Admin (`kasirtoko`), serta pengujian kapasitas & lapangan multi-device sebelum build APK release.

---

## 1. Pengujian POS Admin (`kasirtoko`) — Migrasi, Keamanan, Shift, & Drawer

### 1.1. Uji Migrasi Database Non-Destruktif (`v4 -> v5`, `sqflite_common_ffi`)
1. **Legacy Data Preservation Test:**
   - Buat database SQLite v4 berisikan user lama, produk, shift lama (`status = 'closed'` dan `'open'`), transaksi lama (`transactions`, `transaction_items`), `cash_flows`, `customer_debts`, dan `return_orders`.
   - Jalankan upgrade ke `version: 5`.
   - **Verifikasi:**
     - Backup file `kasirtoko_pre_v5_backup.db` terbentuk sebelum skema diubah.
     - Tidak ada baris data lama yang hilang atau berubah nominalnya.
     - `cash_registers` memiliki `id = 1` (`REG-MAIN`).
     - Seluruh transaksi lama terisi `terminal_id = 'ADMIN'` dan `cash_register_id = 1` (atau `cash_register_id` shift asalnya).
     - Laporan kas (`getCashFlowReport`), histori transaksi, dan retur nota lama tetap berfungsi identik dengan v4.

### 1.2. Uji Keamanan `SecurityHelper` & Auth Rate Limiting
1. **KDF & Hash Strength Test:**
   - Verifikasi hash baru memakai format PHC dengan work factor standar (`Argon2id` atau `PBKDF2-HMAC-SHA256 >= 210.000` iterasi).
   - Pastikan **salt PIN (`pin_salt`) berbeda dari salt password (`password_salt`)**, dan meski PIN = password, `pin_hash != password_hash`.
   - Uji *transparent upgrade*: user berformat hash v4 berhasil login sekali -> hash otomatis ter-upgrade ke format v5 di DB tanpa memutus akses user.
2. **Rate Limit & Lockout Test:**
   - Kirim 5x PIN salah dari `TERM-01` -> attempt ke-6 langsung ditolak `429 PIN_RATE_LIMITED` dengan `retry_after_seconds`, meskipun pada attempt ke-6 dikirim PIN yang benar!
   - Pastikan `audit_logs` mencatat peringatan percobaan login gagal berulang.

### 1.3. Uji Mode Shift (`SHARED_DRAWER` & `INDIVIDUAL_DRAWER`)
1. **`SHARED_DRAWER`:**
   - Admin membuka 1 shift pada `REG-MAIN`. Transaksi dari Admin, `TERM-01` (Kasir 1), dan `TERM-02` (Kasir 2) sukses masuk ke `shift_id` & `cash_register_id = 1` yang sama, sementara kolom `cashier_id` dan `terminal_id` tercatat berbeda sesuai pengirim.
   - Terminal lain ditolak membuka shift ke-2 pada `REG-MAIN` (`409 SHIFT_CONFLICT`).
2. **`INDIVIDUAL_DRAWER`:**
   - Kasir 1 (`TERM-01`, `REG-S1`) dan Kasir 2 (`TERM-02`, `REG-S2`) masing-masing memanggil `POST /shifts/open` secara paralel -> **keduanya berhasil** tanpa error global!
   - Kasir 1 mencoba membuka shift ke-2 di `REG-S2` saat shift-nya di `REG-S1` masih `'open'` -> ditolak (`409 SHIFT_CONFLICT`).
   - Kasir 1 tutup shift (`POST /shifts/close`) hanya menghitung & menutup laci `REG-S1`, tanpa mengganggu shift aktif Kasir 2 di `REG-S2`.

### 1.4. Uji 6 Aturan Cash Drawer
1. Pembayaran `tunai` sukses + `allow_auto_open_drawer = 1` + printer thermal -> pulse `[0x1B, 0x70, 0x00, 0x19, 0xFA]` **dikirim setelah commit DB selesai**.
2. Pembayaran `qris` / `transfer` / `kasbon` / `saldo_kredit` -> `open_drawer` **SELALU `false`**, laci tidak pernah terbuka otomatis.
3. Transaksi tunai gagal (`409 INSUFFICIENT_STOCK`) -> tidak ada print job maupun perintah buka laci.
4. Reprint struk tunai (`is_reprint = true`) -> laci **tidak** terbuka.
5. Terminal dengan `allow_auto_open_drawer = 0` atau user tanpa `AppPermissions.openCashDrawer` mencoba buka manual -> ditolak `403`.
6. Buka laci manual sah -> laci terbuka dan baris baru tercatat di `audit_logs` (`action_type = 'buka_laci'`, lengkap dengan `terminal_id` & `cash_register_id`).

---

## 2. Pengujian POS Staff (`stafkasirtoko`) — Unit, SQLite Cache, & Widget

1. **Unit Tests:**
   - `RequestSigner` HMAC-SHA256, nonce, timestamp canonicalization.
   - `CartProvider` (multi-satuan, tiered price, promo, pajak, batas stok cache).
   - `BarcodeScanGuard` (5 skenario anti-double-scan).
   - `ConnectionProvider` state machine (`UNPAIRED`, `CONNECTING`, `ONLINE_READY`, `ONLINE_SHIFT_CLOSED`, `OFFLINE_ADMIN_UNREACHABLE`, `RECOVERING_INFLIGHT`).
2. **SQLite Lokal Verification (`sqflite_common_ffi`):**
   - Verifikasi `staff_terminal.db` **tidak memiliki** tabel `transactions`, `users`, `shifts`, `cash_flows`, maupun kolom `cost_price`.
   - Verifikasi `active_cart` & `local_held_orders` utuh setelah DB ditutup dan dibuka ulang.
   - Verifikasi unpair / `TERMINAL_REVOKED` membersihkan seluruh cache & secure keystore.
3. **Widget & UI Tests:**
   - Responsive rendering (`360x640`, `412x915`, `1024x768`) tanpa overflow.
   - Saat offline / shift tertutup, tombol **Bayar** nonaktif dan overlay/banner peringatan terlihat jelas.

---

## 3. Pengujian Keamanan & Contract API

1. **TLS Certificate Pinning Test:** Klien Staff menghubungkan ke server mock dengan sertifikat berbeda (simulasi MITM) -> handshake ditolak otomatis oleh pin verifier.
2. **Anti-Replay Test:** Mengirim ulang request valid dengan `X-Request-Nonce` dan `X-Signature` yang sama -> request ke-2 ditolak `401 REPLAY_NONCE_DETECTED`. Timestamp `> 120s` ditolak `401 REPLAY_TIMESTAMP_EXPIRED`.
3. **Idempotency & In-Flight Disconnect Test:**
   - Simulasikan socket terputus setelah server Admin commit transaksi `INV-...` sebelum respons kembali ke Staff -> saat reconnect, Staff memanggil `GET /by-idempotency/{key}` -> menerima struk resmi tanpa duplikasi transaksi maupun pemotongan stok kedua kali.
4. **Stock Concurrency Test:** 2 klien men-checkout stok terakhir `1 Pcs` bersamaan -> tepat 1 berhasil (`201`), 1 ditolak (`409 INSUFFICIENT_STOCK`), stok DB Admin `0` (tidak minus).

---

## 4. Pengujian Kapasitas & Skalabilitas (Tanpa Batas Hardcoded)

Karena sistem tidak membatasi jumlah terminal secara hardcoded, wajib dilakukan **Capacity & Stress Test** untuk mengukur batas realistis perangkat Admin dan jaringan lokal:

| Tingkat Beban Uji | Skenario Pengujian | Metrik yang Diukur | Target Ambang Batas Sehat |
| :--- | :--- | :--- | :--- |
| **Tier 1 (2 Terminal)** | 2 Staff + 1 Admin checkout bergantian & paralel | Latency p50/p95 checkout, CPU/RAM Admin | p95 `< 400 ms`, 0 error `SQLITE_BUSY` |
| **Tier 2 (5 Terminal)** | 5 Staff scan & checkout berkelanjutan + WS broadcast stok | Latency p95, stabilitas WSS ping/pong, antrean printer | p95 `< 700 ms`, 0 dropped WS |
| **Tier 3 (10 Terminal)** | 10 Staff burst checkout + sync katalog awal bersamaan | Throughput (trx/menit), memory footprint server Admin, WAL checkpoint | p95 `< 1500 ms`, 0 OOM/crash, 0 stok korup |
| **Tier 4 (Batas Jaringan Hotspot Android)** | Uji pada **Hotspot Android** (beberapa HP membatasi maks klien hotspot Wi-Fi AP di level OS/chipset) vs **Wi-Fi Router** | Jumlah maksimum klien stabil sebelum packet loss / AP client limit OS | Dokumentasikan batas aman per tipe hardware & rekomendasi router |

---

## 5. Pengujian Android Server Lifecycle & Uji Lapangan Multi-Device

### 5.1. Skenario Wajib Lifecycle Server Android (`kasirtoko`, `targetSdk = 36`)
| ID Uji | Skenario OS / Jaringan | Perilaku yang Diharapkan |
| :--- | :--- | :--- |
| **LS-01** | **Layar Mati (15–30 menit)** | Foreground Service (`connectedDevice`/`specialUse`) + `WakeLock` menjaga HTTPS/WSS tetap responsif (`ping`/`checkout` < 1s) |
| **LS-02** | **Aplikasi Admin di Background / Recents Swipe** | Server Service tetap aktif di notifikasi persisten tanpa terputus meski Activity tidak tampil di layar |
| **LS-03** | **Android Doze Mode** (`adb shell dumpsys deviceidle force-idle`) | Koneksi Staff diuji pasca-Doze: tetap merespons atau langsung re-establish heartbeat + panduan whitelist battery optimization |
| **LS-04** | **Proses Dihentikan Paksa (`Force Stop` / Crash)** | Staff mendeteksi dalam `<= 9s` -> masuk `OFFLINE_ADMIN_UNREACHABLE`, transaksi baru berhenti total, keranjang tetap utuh di SQLite |
| **LS-05** | **Perangkat Admin Restart** | Saat reboot, notifikasi/prompt muncul saat buka Admin (mematuhi pembatasan `BOOT_COMPLETED` Android 15/16); Staff pulih otomatis begitu Admin start server |
| **LS-06** | **Pindah Wi-Fi Router ke Hotspot Android** | `NetworkCallback` mendeteksi perubahan interface -> server re-bind, QR IP Admin otomatis diperbarui |
| **LS-07** | **Perubahan Alamat IP LAN (DHCP Lease Baru)** | Server menampilkan IP baru secara real-time dan tetap dapat dijangkau via scan QR / update IP di terminal |
| **LS-08** | **Pemulihan Server Setelah Gangguan** | Staff otomatis reconnect WSS, menyinkronkan delta katalog (`since_version`) + status shift, dan merekonsiliasi `pending_checkout_intents` |

### 5.2. Uji Lapangan Fisik Multi-Device & Exit Criteria APK
1. **FT-01:** Pairing QR & IP Manual (verifikasi checksum sertifikat) di Wi-Fi Router.
2. **FT-02:** Pairing & transaksi penuh di **Hotspot Android** (tanpa internet, validasi kalibrasi clock offset).
3. **FT-03:** Validasi `SHARED_DRAWER` vs `INDIVIDUAL_DRAWER` (parallel shifts, penugasan laci kasir, tutup shift independen, serta laci hanya buka 1x pada pembayaran tunai pasca-commit dan tidak pernah pada non-tunai/reprint/retry).
4. **FT-04:** Cetak struk bersamaan dari 2 Staff ke 1 printer thermal Bluetooth/USB (termasuk uji cabut/pasang USB OTG permission)/LAN Admin, serta uji kegagalan printer tidak membatalkan transaksi.
5. **FT-05:** Scan QR struk hasil checkout Staff di `ReturnScreen` Admin.

**Kriteria Lulus Sebelum Build APK Release:** `flutter analyze` 0 error/warning di kedua repo, 100% unit/migration/contract tests lulus, seluruh `LS-01..LS-08` & `FT-01..FT-05` + capacity test lulus, dan release APK memakai keystore resmi (bukan debug key).
