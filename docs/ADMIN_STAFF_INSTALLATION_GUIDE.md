# ADMIN_STAFF_INSTALLATION_GUIDE.md — Panduan Instalasi & Pengoperasian Harian

Panduan langkah demi langkah untuk memasang dan menjalankan sistem **KasirToko Admin + KasirToko Staff** di jaringan toko Anda.

---

## 1. Mengunduh APK Resmi
1. Buka halaman **Releases** (untuk rilis bertanda tangan permanen `v*`) atau tab **Actions -> Artifacts** pada masing-masing repository:
   - **KasirToko Admin:** `https://github.com/angga2103/kasirtoko` -> file `KasirToko-Admin-vX.Y.Z-release.apk`
   - **KasirToko Staff:** `https://github.com/angga2103/stafkasirtoko` -> file `KasirToko-Staff-vX.Y.Z-release.apk`
2. Unduh juga file `.sha256` jika ingin memastikan keutuhan file APK sebelum instalasi.
3. Aktifkan opsi **Instal aplikasi tidak dikenal (*Install unknown apps*)** di perangkat Android Anda saat memasang APK pertama kali.
4. *(Jika perangkat Admin sebelumnya terpasang versi debug v2.0.0–v2.2.0)*: ikuti panduan backup -> uninstall sekali -> restore pada [`UPDATE_COMPATIBILITY.md`](UPDATE_COMPATIBILITY.md).

---

## 2. Pengaturan Awal di Perangkat KasirToko Admin
1. Buka aplikasi **KasirToko Admin** dan login sebagai Owner / Admin.
2. Pastikan minimal satu printer (Bluetooth SPP, USB OTG, atau LAN ESC/POS port `9100`) telah ditambahkan pada menu **Printer**, serta pilih sebagai default bila ingin pencetakan otomatis struk dari terminal Staff.
3. Atur mode laci kas pada **Pengaturan / Shift & Laci Kas**:
   - `SHARED_DRAWER`: beberapa kasir dan terminal berbagi 1 laci kas utama.
   - `INDIVIDUAL_DRAWER`: setiap laci kasir terpisah (tambahkan cash register dan assignment per kasir/terminal bila diperlukan).
4. Sambungkan perangkat Admin ke **Wi-Fi Router Toko** (disarankan IP LAN statis di DHCP reservation router) atau aktifkan **Hotspot Wi-Fi** di HP Admin.
5. Buka menu **Server LAN (Terminal Staff)** -> tekan **Jalankan Server LAN**:
   - Pastikan notifikasi Foreground Service muncul (`Server POS Admin Aktif`).
   - Matikan pembatasan baterai (*Unrestricted / Don't optimize*) di pengaturan Android untuk **KasirToko Admin** agar server tidak ditidurkan oleh sistem/vendor OS saat layar mati.

---

## 3. Pairing & Operasional KasirToko Staff
1. Hubungkan tablet/HP **KasirToko Staff** ke **router Wi-Fi atau Hotspot yang sama** dengan perangkat Admin.
2. Di **KasirToko Admin -> Server LAN**, ketuk **Buat Tiket / QR Pairing** (berlaku 5 menit, sekali pakai), atur izin laci kas (`Buka Laci Otomatis` / `Manual`) dan laci kasir yang ditugaskan.
3. Buka **KasirToko Staff**:
   - **Cara cepat (QR):** Ketuk **Scan QR Pairing dari POS Admin** dan arahkan kamera ke QR di layar Admin. Staff otomatis menguji semua IP Admin, memverifikasi SHA-256 sertifikat TLS, dan menyimpan kredensial terenkripsi ke Android Keystore.
   - **Cara manual:** Isi `IP Server Admin`, `Port` (`8443`), `Kode Pairing (8 karakter)`, serta `PIN Checksum Sertifikat TLS (8 karakter)` lalu tekan **Verifikasi Sertifikat & Pasangkan**.
4. Pilih nama kasir aktif dan masukkan **PIN 4–6 digit** kasir.
5. Jika shift belum dibuka, buka shift pada layar **Buka Shift** (untuk `INDIVIDUAL_DRAWER`, kasir hanya bisa memilih laci yang ditugaskan).
6. Lakukan transaksi:
   - Scan barcode via kamera / scanner atau ketuk katalog produk.
   - Jika koneksi Wi-Fi terputus, tombol bayar otomatis terkunci (`Checkout Terkunci — Menunggu Koneksi Admin`) sementara keranjang tetap tersimpan aman di perangkat.
   - Jika koneksi terputus tepat di tengah proses pembayaran, tunggu hingga tersambung kembali — Staff memeriksa status transaksi lewat `idempotency_key` terlebih dahulu agar **tidak pernah terjadi transaksi ganda**.

---

## 4. Troubleshooting Cepat
- **Gagal Pairing ("Kode Pairing Tidak Valid / Kedaluwarsa"):** Buat kode pairing baru di Admin (tiket kedaluwarsa dalam 5 menit dan hanya dapat dipakai 1 kali).
- **IP Admin Berubah setelah Ganti Wi-Fi:** Buka menu **Koneksi & Struk** di Staff lalu lakukan pairing ulang dengan IP baru, atau atur DHCP reservation di router toko.
- **Terminal Terkunci ("Akses Dicabut Admin"):** Owner mencabut akses terminal di Admin. Bersihkan data pairing di Staff dan lakukan QR pairing ulang bila perangkat diizinkan kembali.
- **Struk Tidak Tercetak / Status `retrying`:** Periksa sambungan Bluetooth/USB/LAN pada perangkat Admin dan gunakan tombol **Cetak Ulang** di monitor antrean Admin (cetak ulang tidak memicu laci kas terbuka).
