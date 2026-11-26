# STAFF_APP_GUIDE.md — Panduan Aplikasi POS Staff (`stafkasirtoko`)

## 1. Peran & Prinsip Desain POS Staff
Aplikasi **KasirToko Staff** (`com.kasirtoko.app.stafkasirtoko`) adalah **terminal kasir thin-client**.
- **Tidak ada database transaksi kedua** di perangkat Staff (`staff_terminal.db` hanya menyimpan cache baca produk/promo/pelanggan tanpa `cost_price`, keranjang aktif, draft lokal ditahan, intent rekonsiliasi in-flight, dan maksimal 30 pratinjau struk resmi terbaru).
- Seluruh harga akhir, promo, diskon, pajak, mutasi stok, kredit pelanggan, piutang kasbon, serta antrean printer diputuskan dan disimpan oleh **POS Admin**.

## 2. Langkah Pertama: Pairing Terminal
1. Pastikan perangkat Staff terhubung ke jaringan Wi-Fi atau Hotspot yang sama dengan POS Admin.
2. Buka aplikasi **KasirToko Staff** (muncul `PairingScreen`).
3. Masukkan **Nama Perangkat Kasir** (contoh: `HP Kasir 2`).
4. Pilih salah satu metode:
   - **Scan QR Pairing dari POS Admin** (otomatis membaca IP, port, kode pairing sekali pakai, dan pin sertifikat TLS).
   - **Input Manual**: isi **IP Server Admin**, **Port** (`8443`), **Kode Pairing**, dan **PIN Checksum Sertifikat TLS (8 karakter)** persis seperti yang tampil pada layar Server POS Admin. Jika checksum tidak cocok, koneksi TLS akan ditolak demi keamanan.
5. Token perangkat, secret HMAC, dan fingerprint TLS tersimpan terenkripsi menggunakan `AndroidKeyStore` AES-256-GCM.

## 3. Login Kasir (PIN Individual) & Manajemen Shift
1. Setelah pairing sukses, `PinLoginScreen` mengambil daftar kasir aktif berizin `access_pos` dari Admin.
2. Pilih nama kasir, masukkan PIN 4–6 digit. Salah PIN berulang kali akan dikenai pembatasan laju (`PIN_RATE_LIMITED`) oleh POS Admin.
3. Pada layar **Shift & Laci Kas** (`StaffShiftScreen`):
   - Pada mode **`SHARED_DRAWER`**: jika shift toko bersama sudah dibuka di Admin/terminal lain, terminal langsung siap bertransaksi (`ONLINE_READY`).
   - Pada mode **`INDIVIDUAL_DRAWER`**: kasir membuka shift pada laci kas yang ditugaskan (`starting_cash`), dan dapat melakukan **Tutup Shift (Blind Cash Count)** di akhir sesi.

## 4. Transaksi Penjualan, Barcode & Pembayaran
- **Katalog & Multi-Satuan:** Ketuk kartu produk. Jika produk memiliki satuan turunan (mis. Dus/Pack), pilih satuan di bottom sheet; harga bertingkat otomatis diterapkan.
- **Scan Barcode:** Ketuk ikon kamera QR/Barcode atau gunakan scanner USB/Bluetooth HID langsung di kolom pencarian (`BarcodeScanGuard` mencegah double-scan dalam 1.200 ms).
- **Pelanggan, Diskon & Promo:** Pilih pelanggan terdaftar untuk mengaktifkan pembayaran **Kasbon** atau **Saldo Kredit** (`Pelanggan Umum` hanya untuk tunai/QRIS/transfer). Diskon manual hanya aktif bagi akun kasir dengan permission `apply_discount`.
- **Tahan Keranjang (`Hold`)**: Keranjang dapat ditahan secara lokal sebagai draft (`local_held_orders`) dan dipanggil kembali kapan saja. Draft ini belum menjadi transaksi resmi sebelum disahkan Admin saat checkout.

## 5. Penanganan Koneksi Terputus & Rekonsiliasi
- Jika Wi-Fi/Hotspot terputus atau Server Admin dimatikan, banner merah **"Terputus dari POS Admin"** tampil jelas, **keranjang tidak hilang** (tersimpan di `active_cart_items`), dan tombol **Bayar Terkunci** (`canSubmitCheckout == false`).
- Apabila koneksi terputus tepat saat tombol bayar ditekan (`pending_checkout_intents`), ketika jaringan kembali tersambung POS Staff otomatis memeriksa `GET /api/v1/transactions/by-idempotency/{key}` ke Admin:
  - Jika transaksi sudah tersimpan di Admin -> struk resmi diunduh dan keranjang dikosongkan tanpa penagihan ganda.
  - Jika transaksi belum masuk Admin -> keranjang tetap dipertahankan agar kasir dapat mengirim ulang dengan aman.

## 6. Struk, Cetak Ulang & Buka Laci Manual
- Ketuk **Cetak Ulang** pada `StaffReceiptDialog` atau buka **Status Koneksi & 30 Struk Terbaru**. Permintaan cetak ulang ke Admin **tidak pernah** membuka laci kasir.
- Tombol **Buka Laci Manual** hanya muncul bila Admin mengaktifkan `allow_manual_open_drawer` untuk terminal tersebut **DAN** akun kasir memiliki izin `open_cash_drawer`. Kasir wajib mengisi alasan audit.
