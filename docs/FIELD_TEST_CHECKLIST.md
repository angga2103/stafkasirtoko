# FIELD_TEST_CHECKLIST.md — Checklist Pengujian Lapangan Perangkat Nyata

Pengujian otomatis (`flutter test`, TLS+WSS loopback E2E, dan build APK) telah lulus di host build, namun pada lingkungan build tidak terdapat emulator maupun perangkat fisik (`adb devices` kosong). Jalankan checklist berikut pada perangkat Android nyata sebelum serah terima produksi di toko.

---

## 1. Branding, Instalasi & Update Kompatibilitas
- [ ] Pasang `KasirToko-Admin-v2.3.0-release.apk` di HP/Tablet Admin: ikon *storefront + dashboard* Navy/Biru tampil tajam tanpa terpotong di launcher (circle, squircle, dan themed monochrome Android 13+), label terpasang adalah **`KasirToko Admin`**.
- [ ] Pasang `KasirToko-Staff-v1.0.2-arm64-v8a-release.apk` di HP/Tablet Staff: ikon *struk + barcode + centang* Navy/Turquoise tampil jelas bersebelahan dan mudah dibedakan dari Admin, label terpasang adalah **`KasirToko Staff`**.
- [ ] Verifikasi dengan `adb shell dumpsys package com.kasirtoko.app.kasirtoko` dan `.stafkasirtoko` bahwa sertifikat APK cocok dengan SHA-256 resmi pada [`ANDROID_SIGNING_GUIDE.md`](ANDROID_SIGNING_GUIDE.md).
- [ ] Uji update in-place dari versi `N` ke `N+1` (`versionCode` lebih tinggi, keystore sama): pastikan data produk, transaksi, pelanggan, pairing terminal, dan login tetap utuh tanpa uninstall.

## 2. Keamanan Hardware & Performa Android Nyata
- [ ] Buka **KasirToko Admin -> Karyawan -> Reset/Login PIN**, pastikan login PIN dengan PBKDF2-HMAC-SHA256 **600.000 iterasi** + Android Keystore pepper berjalan dengan durasi wajar di chipset perangkat target.
- [ ] Uji salah PIN 5 kali berturut-turut di Staff -> status terkunci `PIN_RATE_LIMITED` (429) aktif dan tercatat di Log Audit Admin.
- [ ] Putar layar Admin dengan Foreground Service berjalan (`specialUse`): notifikasi live menampilkan port & jumlah terminal terhubung, dan service tetap stabil di background selama operasional shift normal (dengan Battery Optimization = Unrestricted).

## 3. Integrasi Multi-Device LAN Nyata (Wi-Fi Router & Hotspot Android)
- [ ] Uji pairing via kamera (`mobile_scanner`) terhadap QR Admin dari layar tablet/HP berbeda.
- [ ] Uji pairing manual menggunakan IP + Kode Pairing + Short PIN Checksum 8 karakter.
- [ ] Uji transaksi bersamaan dari minimal 2–5 HP Staff secara nyata saat stok barang terbatas: pastikan tidak ada stok minus dan setiap nota menyimpan `cashier_id`, `terminal_id`, `shift_id`, dan `cash_register_id` yang akurat.
- [ ] Uji mematikan Wi-Fi di Staff saat keranjang berisi barang: keranjang utuh, checkout terkunci; setelah Wi-Fi aktif kembali, checkout kembali terbuka.
- [ ] Uji mematikan Wi-Fi tepat ketika menekan **Bayar**, lalu nyalakan lagi: pastikan rekonsiliasi idempotency menemukan transaksi jika sudah masuk ke Admin dan **tidak pernah membuat transaksi ganda**.
- [ ] Uji mode `SHARED_DRAWER` vs `INDIVIDUAL_DRAWER` beserta perpindahan laci dan tutup shift parsial.

## 4. Printer Thermal & Cash Drawer RJ11 Fisik
- [ ] Uji cetak otomatis dari Staff ke Admin dengan printer **Bluetooth SPP**, **USB OTG**, dan **LAN RAW (9100)**.
- [ ] Verifikasi pembukaan laci kas RJ11 **hanya** terbuka saat pembayaran `tunai` sukses, `allow_auto_open_drawer = true`, dan printer bukan PDF/System — serta **tidak terbuka** pada QRIS, Transfer, Kasbon, maupun cetak ulang (*reprint*).
- [ ] Matikan printer fisik saat Staff checkout -> transaksi tetap berhasil tercatat di Admin, status print job menjadi `retrying`/`failed`, dan dapat dicetak ulang dari antrean Admin setelah printer nyala tanpa mengirim pulsa laci ganda.

## 5. Pengujian Scanner & UI Kasir Nyata (`v1.0.2`)
- [ ] Uji scanner **QR Pairing** & **Barcode POS**: buka -> kembali tanpa scan -> buka lagi berkali-kali secara cepat (`5x`), pastikan layar **tidak pernah blank hitam** dan selalu kembali normal ke POS Kasir.
- [ ] Uji **tolak izin kamera -> Coba Lagi -> Input Barcode Manual -> Kembali ke Kasir**, serta uji **minimize / matikan layar (`paused` -> `resumed`)** saat scanner terbuka lalu kembali ke app.
- [ ] Uji scan **1 produk**, scan ulang produk sama cepat (`cooldown` 1,4 detik menahan duplikat), dan scan **multi-produk beruntun** dalam mode `Multi Scan` maupun `1x & Tutup`.
- [ ] Uji **stepper qty langsung (`- qty +`)** di kartu produk pada HP (`<= 412dp`), batas stok pada produk berstok, layanan `JASA` tanpa stok, penuruan qty hingga `0` (hapus item), serta scroll dialog **Pembayaran Transaksi** saat keyboard virtual terbuka.
