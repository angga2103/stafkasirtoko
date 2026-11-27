# FINAL_RELEASE_REPORT.md — Laporan Kesiapan Produksi, Signing & Distribusi APK

Dokumen ini merupakan laporan rilis akhir untuk sistem POS Multi-Device **KasirToko Admin** (`com.kasirtoko.app.kasirtoko`) dan **KasirToko Staff** (`com.kasirtoko.app.stafkasirtoko`).

---

## 1. Spesifikasi Rilis & Artefak APK Terverifikasi

### A. KasirToko Admin (`v2.3.0+5`)
- **Repository & Branch:** `https://github.com/angga2103/kasirtoko` (branch `feat/phase2-multi-device-complete`; branch `main` dipertahankan di commit `327b1ab` untuk merge PR terkontrol)
- **Package ID (`applicationId`):** `com.kasirtoko.app.kasirtoko`
- **Launcher Label (`android:label`):** `KasirToko Admin`
- **Version:** `2.3.0` (`versionCode = 5`, `compileSdk = 36`, `targetSdk = 36`)
- **Release APK Output Lokal (di luar Git):** `C:\Users\Toshiba\KasirToko-Signing\release-builds\KasirToko-Admin-v2.3.0-release.apk`
  - **Ukuran File:** `577,909,592` bytes (`551.1 MB`)
  - **APK SHA-256 Checksum:** `9ec47cd80c178eae0779455496f5612c7fab48227a6347c87dd4633075490a5b`
  - **Signature Verification (`apksigner`):** Valid (APK Signature Scheme v2), 0 indikasi `Android Debug`
  - **Signer DN:** `CN=KasirToko Admin Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`
  - **Key:** RSA **4096-bit**, Certificate SHA-256 `a9:46:a3:d8:8a:0d:fb:ae:e5:6c:dd:13:d8:60:ff:f7:65:ae:ee:54:0a:6b:f2:a8:3d:34:0d:f0:51:93:42:41`, SHA-1 `2c:38:7e:2c:86:0a:a3:b4:b6:be:00:04:a6:e5:e9:60:ed:b7:c4:49`
- **Debug APK Verifikasi:** `app-debug.apk` (`1,476,484,616` bytes), signed `CN=Android Debug` (RSA 2048, SHA-256 `c7:7f:52:55:...`), label `KasirToko Admin`.

### B. KasirToko Staff (`v1.0.1+2`)
- **Repository & Branch:** `https://github.com/angga2103/stafkasirtoko` (branch `main` dan `feat/pos-staff-app`)
- **Package ID (`applicationId`):** `com.kasirtoko.app.stafkasirtoko`
- **Launcher Label (`android:label`):** `KasirToko Staff`
- **Version:** `1.0.1` (`versionCode = 2`, `compileSdk = 36`, `targetSdk = 36`)
- **Release APK Output Lokal (di luar Git):** `C:\Users\Toshiba\KasirToko-Signing\release-builds\KasirToko-Staff-v1.0.1-release.apk`
  - **Ukuran File:** `527,253,000` bytes (`502.8 MB`)
  - **APK SHA-256 Checksum:** `ea10696c58e6bd3a9eadad39fac1c6bfc50f96d556573d935955b4edd8346adf`
  - **Signature Verification (`apksigner`):** Valid (APK Signature Scheme v2), 0 indikasi `Android Debug`
  - **Signer DN:** `CN=KasirToko Staff Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`
  - **Key:** RSA **4096-bit**, Certificate SHA-256 `e4:31:47:7a:7a:e0:4c:f0:86:f0:99:ba:7d:a5:3d:cf:0b:b6:5f:98:7c:bc:76:da:c0:a7:78:c8:40:60:62:32`, SHA-1 `de:37:f6:71:98:5a:dd:65:ec:bc:d4:f6:97:34:22:14:a9:3a:ac:06`
- **Debug APK Verifikasi:** `app-debug.apk` (`1,432,829,721` bytes), signed `CN=Android Debug` (RSA 2048, SHA-256 `c7:7f:52:55:...`), label `KasirToko Staff`.

---

## 2. Pengaman Signing Keystore & Gerbang Penolakan Rilis Tanpa Kunci Permanen

- Kedua keystore permanen (masa berlaku **10.950 hari**, 27 Nov 2026 – 19 Nov 2056) beserta arsip backup terenkripsi AES-256-GCM + PBKDF2-HMAC-SHA256 600.000 iterasi (`kasirtoko-signing-backup.aesgcm`) dan catatan pemulihan offline (`SIGNING_RECOVERY.txt`) disimpan **strictly di luar repository Git** di `C:\Users\Toshiba\KasirToko-Signing\`.
- Seluruh file sementara `android/key.properties` telah dihapus pasca build (`admin=False`, `staff=False`), dan build release tanpa signing permanen telah teruji **ditolak seketika (`exit 1`)** oleh `android/app/build.gradle.kts` baris 37 pada kedua repository.
- Tidak ada `.jks`, `.b64`, `.aesgcm`, `key.properties`, password, atau database runtime di dalam tree Git maupun arsip APK (`Secret/DB leakage check: []`).

---

## 3. Branding & Identitas Produk

- **KasirToko Admin:** Palet Navy (`#0B1F3A`) + Azure/Sky Blue (`#2563EB` / `#38BDF8`) + Putih, simbol bangunan *storefront* 4-panel kanopi + 3-bar *dashboard* analitik, bebas teks mikro.
- **KasirToko Staff:** Palet Navy (`#0B1F3A`) + Turquoise/Emerald (`#14B8A6` / `#10B981` / `#34D399`) + Putih, simbol struk POS bergerigi + baris *barcode* + lencana centang kanan bawah, bebas teks mikro.
- Seluruh lapisan ikon adaptif (`mipmap-anydpi-v26/ic_launcher.xml`, `drawable/ic_launcher_background.xml`, `mipmap-*/ic_launcher_foreground.png`, `mipmap-*/ic_launcher_monochrome.png`, serta raster legacy `mdpi`–`xxxhdpi`) dan logo in-app tervalidasi ada di aset proyek & APK terkompilasi.

---

## 4. Tindakan Wajib Pemilik Repository Sebelum Rilis GitHub Pertama

Karena CLI `gh` pada lingkungan build dalam kondisi logged out, agent mendorong seluruh kode, branding, dokumentasi, dan workflow CI/CD melalui credential Git yang tersedia. Untuk mengaktifkan **GitHub Releases otomatis** di kedua repository GitHub:

1. Buka masing-masing repository di GitHub -> **Settings -> Secrets and variables -> Actions -> New repository secret**, lalu tambahkan 4 secrets:
   - **`angga2103/kasirtoko`** (Admin):
     - `ANDROID_KEYSTORE_BASE64`: isi `C:\Users\Toshiba\KasirToko-Signing\kasirtoko-admin-release.jks.b64`
     - `ANDROID_KEYSTORE_PASSWORD`: sesuai `SIGNING_RECOVERY.txt` bagian `ADMIN`
     - `ANDROID_KEY_ALIAS`: `kasirtoko_admin`
     - `ANDROID_KEY_PASSWORD`: sama persis dengan `ANDROID_KEYSTORE_PASSWORD` (format PKCS12)
   - **`angga2103/stafkasirtoko`** (Staff):
     - `ANDROID_KEYSTORE_BASE64`: isi `C:\Users\Toshiba\KasirToko-Signing\kasirtoko-staff-release.jks.b64`
     - `ANDROID_KEYSTORE_PASSWORD`: sesuai `SIGNING_RECOVERY.txt` bagian `STAFF`
     - `ANDROID_KEY_ALIAS`: `kasirtoko_staff`
     - `ANDROID_KEY_PASSWORD`: sama persis dengan `ANDROID_KEYSTORE_PASSWORD` (format PKCS12)
2. Merge branch `feat/phase2-multi-device-complete` -> `main` di `kasirtoko` setelah review PR CI.
3. Buat dan push tag rilis (`git tag v2.3.0 && git push origin v2.3.0` di `kasirtoko`; `git tag v1.0.1 && git push origin v1.0.1` di `stafkasirtoko`) untuk menerbitkan halaman **GitHub Release** beserta file `.apk`, `.aab`, dan `.sha256`.
4. Eksekusi pengujian fisik toko sesuai `FIELD_TEST_CHECKLIST.md` dan ikuti panduan migrasi satu kali bagi pengguna Admin v2.0.0–v2.2.0 pada `UPDATE_COMPATIBILITY.md`.
