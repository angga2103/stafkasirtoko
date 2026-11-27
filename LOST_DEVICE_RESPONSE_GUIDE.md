# Panduan Tanggap Insiden HP Hilang, Dicuri, atau Karyawan Keluar

Dokumen ini menetapkan prosedur keamanan cepat bagi Owner/Admin KasirToko saat HP pribadi karyawan hilang/dicuri, akun kasir harus diblokir saat karyawan resign, atau HP Admin utama rusak/hilang.

## Skenario 1: HP Pribadi Karyawan Hilang / Dicuri (Sedang Tersambung ke Wi-Fi Toko)

1. Buka aplikasi **KasirToko Admin -> Server LAN & Terminal Staff** atau **Manajemen Karyawan**.
2. Segera lakukan dua tindakan di Admin:
   - Pada bagian **Terminal Terdaftar**, tekan **Cabut Akses Terminal** pada perangkat yang hilang (`MultiDeviceDao.revokeTerminal`). Ini mencabut token perangkat sekaligus memutus WebSocket (`close code 4003`).
   - Pada bagian **Manajemen Karyawan**, pilih **Cabut Semua Sesi Aktif** (atau nonaktifkan sementara akun karyawan tersebut jika akun diduga ikut terbaca, lalu ganti PIN/Password akun karyawan yang bersangkutan).
3. Saat perangkat Staff menyentuh jaringan LAN Admin berikutnya, aplikasi Staff otomatis menerima `TERMINAL_REVOKED` (403 / WS event), masuk ke state `TerminalConnectionState.revoked`, menghapus token Android Keystore (`clearAll`), serta menghapus seluruh data lokal `StaffLocalDb` (`clearAllLocalData`).
4. **Dampak ke Toko:** Shift kasir bersama (`SHARED_DRAWER`) pada mesin kasir toko tetap buka sehingga kasir lain tetap dapat bertransaksi tanpa gangguan.

## Skenario 2: HP Pribadi Karyawan Hilang & Sedang Offline / Dimatikan di Luar Toko

1. **Kejujuran Arsitektur:** Aplikasi Staff **tidak dapat menghapus data lokal secara remote** jika HP dalam kondisi mati atau tidak pernah kembali ke jaringan Wi-Fi/Hotspot Admin.
2. **Mitigasi Eksposur Data yang Sudah Terjamin Secara Desain:**
   - Database lokal HP Staff (`StaffLocalDb`) **tidak pernah menyimpan** `cost_price`/HPP, laba, laporan kas/utang, daftar user/PIN karyawan lain, maupun riwayat penuh database toko (hanya cache katalog jual, keranjang sementara, dan maksimal 30 struk terminal itu sendiri).
   - Tanpa akses Wi-Fi toko dan tanpa sertifikat server + validasi admin, HP hilang tidak dapat menerbitkan transaksi baru karena tombol **Bayar** terkunci keras (`canSubmitCheckout == false`).
3. **Tindakan Wajib Owner di Admin:**
   - Cabut akses `terminal_id` perangkat tersebut di Admin agar token hardware & HMAC secret lama tidak bisa lagi digunakan jika HP suatu saat dinyalakan kembali di area Wi-Fi toko.
   - Ganti PIN karyawan terkait jika khawatir PIN tertulis/tertebak.

## Skenario 3: Karyawan Keluar / Resign (Masih Memiliki Akun)

1. Buka **Manajemen Karyawan** di POS Admin.
2. Pilih menu titik tiga pada akun karyawan -> **Nonaktifkan Akun** (`DatabaseHelper.setUserActive(userId, false)`).
   - Secara otomatis dalam satu eksekusi backend: akun ditandai nonaktif, **seluruh `terminal_sessions` milik karyawan dicabut**, dan socket WebSocket sesi akun tersebut diputus.
   - Jika HP pribadi yang bersangkutan sebelumnya juga didaftarkan secara permanen sebagai terminal khusus karyawan itu, cabut juga terminalnya pada **Server LAN & Terminal Staff -> Cabut Akses Terminal**.
3. Periksa kembali kebijakan batas sesi (`session_policies`) jika sebelumnya dinaikkan untuk akun tersebut.

## Skenario 4: HP Server Admin Utama Toko Rusak / Hilang Total

1. **Perlindungan Data:** Siapkan HP Android pengganti untuk KasirToko Admin dan pastikan Anda memiliki salinan file **`.ktbak`** terbaru (dari folder SAF/eksternal/flashdisk/Google Drive pribadi) beserta **Passphrase Pemulihan Lintas Perangkat**.
2. **Langkah Pemulihan Cepat:**
   - Pasang **KasirToko Admin** rilis permanen terbaru di HP pengganti.
   - Buka **Backup Data (`BackupManagementScreen`) -> Pulihkan File**.
   - Pilih file `.ktbak` dan masukkan **Passphrase Pemulihan**. Sistem memverifikasi integritas AES-256-GCM + SHA-256 + `PRAGMA integrity_check` lalu memulihkan database.
   - Nyalakan Server LAN Admin (`MultiDeviceServerScreen`) — karena sertifikat TLS & IP HP pengganti baru berbeda dari HP lama, generate QR pairing baru dan **pasangkan ulang (re-pair) terminal HP Staff** ke server pengganti demi keamanan sertifikat TLS pinning (`trust-on-first-pair`).
3. **Keamanan Backup Lama jika HP Admin Lama Dicuri:**
   - Arsip `.ktbak` tetap terenkripsi AES-256-GCM dan dilindungi Android Keystore pada HP lama serta passphrase di sisi owner. Segera ganti PIN/Password akun Owner & Karyawan setelah pemulihan di HP baru.
