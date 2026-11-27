# APP_BRANDING_GUIDE.md — Panduan Identitas Visual & Branding Aplikasi

Kedua aplikasi **KasirToko Admin** dan **KasirToko Staff** dirancang berada dalam satu keluarga produk yang konsisten, profesional, bebas teks mikro di dalam ikon, serta langsung dapat dibedakan di laci aplikasi Android (*app drawer*).

---

## 1. Perbandingan Identitas Produk

| Aspek | KasirToko Admin | KasirToko Staff |
| :--- | :--- | :--- |
| **Nama Launcher (`android:label`)** | `KasirToko Admin` | `KasirToko Staff` |
| **Package ID** | `com.kasirtoko.app.kasirtoko` | `com.kasirtoko.app.stafkasirtoko` |
| **Konsep Simbol** | Bangunan *storefront* berkanopi 4 panel dengan layar *dashboard* analitik 3 kolom di tengah — melambangkan pusat kendali toko & server. | Struk/tiket POS bergerigi dengan baris *barcode* tajam dan lencana centang di kanan bawah — melambangkan transaksi kasir cepat & terverifikasi. |
| **Palet Latar (Keluarga Bersama)** | Navy Gelap (`#13345E` -> `#0B1F3A` -> `#071427`) dengan pendar biru lembut | Navy Gelap (`#0F354C` -> `#0B1F3A` -> `#071427`) dengan pendar teal lembut |
| **Palet Aksen Utama** | Biru Cerah (`#2563EB`), Sky Blue (`#38BDF8`), Putih (`#FFFFFF`) | Turquoise (`#14B8A6`), Hijau Emerald (`#10B981`), Mint (`#34D399`), Putih (`#FFFFFF`) |

---

## 2. Daftar Aset yang Dihasilkan & Terintegrasi

### A. KasirToko Admin (`c:\kasirtoko`)
- **Master Vektor SVG:** [`assets/branding/kasirtoko_admin_master.svg`](../assets/branding/kasirtoko_admin_master.svg)
- **Master PNG 1024x1024:** [`assets/branding/kasirtoko_admin_master_1024.png`](../assets/branding/kasirtoko_admin_master_1024.png)
- **Aset 512x512:** [`assets/branding/kasirtoko_admin_512.png`](../assets/branding/kasirtoko_admin_512.png)
- **In-App Logo (`pubspec.yaml`):** [`assets/branding/kasirtoko_admin_logo.png`](../assets/branding/kasirtoko_admin_logo.png) (digunakan di layar login jika toko belum mengunggah logo kustom)
- **Adaptive Layers 512px:** `kasirtoko_admin_adaptive_foreground_512.png`, `kasirtoko_admin_adaptive_monochrome_512.png`
- **Android Resources (`android/app/src/main/res/`):**
  - `mipmap-anydpi-v26/ic_launcher.xml` & `ic_launcher_round.xml`
  - `drawable/ic_launcher_background.xml`
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png` (zona aman tengah `66/108` dp)
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_monochrome.png` (siluet alpha putih murni untuk Material You themed icons)
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` & `ic_launcher_round.png`

### B. KasirToko Staff (`c:\StafKasirtoko`)
- **Master Vektor SVG:** [`assets/branding/kasirtoko_staff_master.svg`](../assets/branding/kasirtoko_staff_master.svg)
- **Master PNG 1024x1024:** [`assets/branding/kasirtoko_staff_master_1024.png`](../assets/branding/kasirtoko_staff_master_1024.png)
- **Aset 512x512:** [`assets/branding/kasirtoko_staff_512.png`](../assets/branding/kasirtoko_staff_512.png)
- **In-App Logo (`pubspec.yaml`):** [`assets/branding/kasirtoko_staff_logo.png`](../assets/branding/kasirtoko_staff_logo.png) (ditampilkan di `PairingScreen` & `PinLoginScreen`)
- **Adaptive Layers 512px:** `kasirtoko_staff_adaptive_foreground_512.png`, `kasirtoko_staff_adaptive_monochrome_512.png`
- **Android Resources (`android/app/src/main/res/`):**
  - `mipmap-anydpi-v26/ic_launcher.xml` & `ic_launcher_round.xml`
  - `drawable/ic_launcher_background.xml`
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png`
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_monochrome.png`
  - `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` & `ic_launcher_round.png`

---

## 3. Prinsip Kejelasan pada Ukuran Kecil & Mask Android
- Seluruh elemen utama ditempatkan dalam radius aman `< 60%` kanvas adaptive `108dp` sehingga bentuk **lingkaran**, **squircle**, **teardrop**, maupun **rounded square** tidak memotong garis luar kanopi Admin maupun sudut struk/centang Staff.
- Kontras tinggi latar gelap + ikon putih + aksen biru vs turquoise/emerald membuat perbedaan Admin dan Staff terlihat jelas bahkan pada ukuran `48dp` (`mdpi`).
