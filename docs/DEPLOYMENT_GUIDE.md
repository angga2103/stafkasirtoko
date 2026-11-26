# DEPLOYMENT_GUIDE.md — Panduan Instalasi & Operasional Lapangan

## 1. Spesifikasi APK Target
| Aplikasi | Repository | Application ID | APK Output Lokal |
| :--- | :--- | :--- | :--- |
| **KasirToko (POS Admin Server)** | `angga2103/kasirtoko` | `com.kasirtoko.app.kasirtoko` | `build/app/outputs/flutter-apk/app-debug.apk` |
| **KasirToko Staff (Terminal)** | `angga2103/stafkasirtoko` | `com.kasirtoko.app.stafkasirtoko` | `build/app/outputs/flutter-apk/app-debug.apk` |

Dua `applicationId` berbeda memastikan kedua aplikasi dapat dipasang berdampingan atau pada perangkat Android terpisah (Android SDK min 21 / Android 5.0+).

## 2. Persiapan Jaringan Toko (Router Wi-Fi atau Hotspot Android)
### Opsi A — Router Wi-Fi Lokal (Direkomendasikan untuk 3–10 Terminal)
1. Hubungkan tablet/HP POS Admin dan seluruh HP/tablet POS Staff ke SSID Wi-Fi router yang sama.
2. Pada pengaturan router, tetapkan **DHCP Static Lease / IP Reservation** untuk MAC address perangkat Admin (mis. `192.168.1.50`) agar IP Admin tidak berubah setelah restart.
3. Matikan fitur **AP/Client Isolation** di router bila diaktifkan, karena fitur tersebut memblokir komunikasi antar-perangkat di jaringan LAN/Wi-Fi.

### Opsi B — Hotspot Android pada Perangkat Admin (Skala Kecil / Darurat)
1. Aktifkan Hotspot Portable di tablet/HP Admin (disarankan mode WPA2/WPA3, hindari AP isolation).
2. Hubungkan perangkat Staff ke hotspot Admin.
3. Buka layar **Server POS LAN** di Admin dan nyalakan server; alamat IP tethering Android (biasanya `192.168.43.1` atau `192.168.x.1`) tampil otomatis di daftar IP lokal Admin.

## 3. Pengaturan Daya & Stabilitas Android pada Perangkat POS Admin
1. Pada **Server LAN**, tekan **Nonaktifkan Batasi Baterai** agar Android tidak menghentikan `PosServerForegroundService` di latar belakang.
2. Sambungkan perangkat POS Admin ke charger listrik selama jam operasional toko.
3. Bila menggunakan printer USB OTG, gunakan kabel OTG berkualitas dengan dukungan daya eksternal apabila perlu.

## 4. Urutan Pemasangan & Uji Coba Awal di Toko
1. Pasang APK POS Admin pada perangkat utama, login sebagai Pemilik/Admin, cek profil toko, produk, printer Bluetooth/USB/LAN, dan mode laci (`SHARED_DRAWER` atau `INDIVIDUAL_DRAWER`).
2. Nyalakan **Server HTTPS/WSS Aktif (Port 8443)**.
3. Buat akun kasir individual + PIN unik di **Manajemen Karyawan**.
4. Pasang APK POS Staff pada setiap perangkat kasir tambahan, lakukan pairing via **Scan QR Pairing** atau **Input Manual + Verifikasi PIN Sertifikat TLS**.
5. Uji satu transaksi tunai nominal kecil + verifikasi cetak struk + uji mematikan Wi-Fi Staff sesaat (memastikan keranjang bertahan & tombol Bayar terkunci), lalu aktifkan Wi-Fi kembali.

## 5. Prosedur Cadangan & Rotasi Darurat
- **Backup Database Admin:** Lakukan backup berkala dari **Pengaturan Toko -> Backup**. Secret terminal HMAC terbungkus Keystore Admin; saat memulihkan ke perangkat baru yang berbeda Keystore-nya, lakukan pairing ulang pada terminal Staff.
- **Perangkat Staff Hilang / Dicuri:** Buka **Server LAN** di POS Admin -> tekan **Cabut Akses Terminal** pada perangkat terkait. Akses WebSocket putus seketika dan seluruh request token lama ditolak (`403 TERMINAL_REVOKED`).
- **Rotasi Sertifikat TLS:** Gunakan tombol **Siapkan Rotasi TLS** di Admin sebelum cutover sertifikat baru agar terminal online mengunduh `next_cert_sha256` terlebih dahulu.
