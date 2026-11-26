# ADMIN_SERVER_GUIDE.md — Panduan Aplikasi POS Admin (`kasirtoko`)

## 1. Peran & Tanggung Jawab POS Admin
POS Admin (`com.kasirtoko.app.kasirtoko`) bertindak sebagai **Pusat Database, Validasi Transaksi, Stok, Keuangan, Shift/Laci Kas, dan Print Server**. Semua fitur POS offline single-device yang sudah ada tetap berfungsi penuh berdampingan dengan server LAN multi-perangkat.

## 2. Membuka Modul Server POS LAN
1. Login ke POS Admin sebagai akun yang memiliki izin `manage_store_settings` (Pemilik / Admin).
2. Buka menu **Server LAN (Terminal Staff)** dari Grid Modul Beranda atau dari **Pengaturan Toko -> Server LAN & Terminal Staff**.
3. Pastikan HP/Tablet Admin sudah mengaktifkan **Wi-Fi Router** atau **Hotspot Android** (disarankan terhubung pada SSID yang sama dengan perangkat Staff).

## 3. Menjalankan Server HTTPS & WSS
1. Biarkan port default **`8443`** (atau ganti jika diperlukan).
2. Aktifkan sakelar **Server HTTPS/WSS Aktif**.
3. Android akan menjalankan `PosServerForegroundService` bertipe **`specialUse`** dengan notifikasi persisten yang menampilkan port dan jumlah terminal terhubung.
4. Pada HP Android dengan agresivitas hemat baterai (Xiaomi MIUI, Oppo ColorOS, Vivo FuntouchOS, Samsung OneUI), ketuk tombol **Nonaktifkan Batasi Baterai** (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) agar Android tidak membekukan proses server saat layar mati.
5. **Catatan Lifecycle Nyata:** Android Foreground Service `specialUse` memberikan prioritas tinggi dan pencatatan pemulihan (`shouldRun`, `wasInterrupted`), namun OS/OEM masih dapat menghentikan proses dalam kondisi memori kritis. Karena itu, protokol transaksi menggunakan `idempotency_key` dan rekonsiliasi otomatis pada POS Staff.

## 4. Menambahkan Terminal Staff (Pairing)
1. Ketuk **Pairing Terminal Baru** pada `MultiDeviceServerScreen`.
2. Isi:
   - **Nama Terminal / Meja Kasir** (contoh: `Kasir Depan 2`).
   - **Laci Kas yang Ditugaskan** (`REG-MAIN`, `REG-S2`, dll. pada `INDIVIDUAL_DRAWER`).
   - Toggle **Izinkan Buka Laci Otomatis (Pembayaran Tunai)** (`allow_auto_open_drawer`).
   - Toggle **Izinkan Buka Laci Manual** (`allow_manual_open_drawer`).
3. Ketuk **Buat QR Pairing**:
   - **Cara QR:** Pindai kode QR menggunakan kamera di POS Staff. QR berisi alamat IP lokal, port HTTPS, kode pairing sekali pakai (berlaku 5 menit), dan fingerprint penuh sertifikat TLS `cert_sha256`.
   - **Cara Manual IP:** Masukkan `https://<IP_ADMIN>:<PORT>`, **Kode Pairing 8 karakter**, dan **PIN Checksum Sertifikat TLS (8 karakter hex)** yang tampil di layar Server Admin.

## 5. Mengelola Mode Shift & Laci Kas
Di **Pengaturan Toko**:
- **`SHARED_DRAWER`**: Banyak kasir dan banyak terminal Staff dapat bertransaksi ke dalam satu shift terbuka pada laci kas bersama (`REG-MAIN`). Penutupan shift tetap mencatat identitas masing-masing kasir pada tiap transaksi.
- **`INDIVIDUAL_DRAWER`**: Setiap laci (`cash_registers`) memiliki shift terbuka independen. Kelola assignment (`terminal_id`, `cashier_id`, atau kombinasi dengan prioritas deterministik) lewat **Kelola Laci & Assignment**.

## 6. Mengelola Kebijakan Terminal, Pencabutan & Antrean Printer
Pada daftar **Terminal Terdaftar** (`MultiDeviceServerScreen`):
- Ubah laci kasir atau printer default kapan saja; perubahan kebijakan dikirim real-time ke Staff (`terminal_policy_updated`).
- Aktifkan/nonaktifkan **Buka Laci Otomatis** dan **Buka Laci Manual** per terminal.
- Ketuk **Cabut Akses Terminal** untuk memblokir terminal secara instan (`TERMINAL_REVOKED`, kode WebSocket `4003`).
- Pantau status antrean printer di bagian **Antrean Printer Terpusat** (`queued`, `processing`, `submitted`, `failed`) dan gunakan **Cetak Ulang** bila printer sempat offline.
- Gunakan **Siapkan Rotasi TLS** sebelum masa berlaku sertifikat berakhir agar terminal yang sedang aktif menerima `next_cert_sha256` terlebih dahulu via `/api/v1/security/cert-info`.
