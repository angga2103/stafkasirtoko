# FINAL_RELEASE_REPORT.md — Laporan Kesiapan Produksi, Signing & Distribusi APK

Dokumen ini merupakan laporan rilis akhir untuk sistem POS Multi-Device **KasirToko Admin** (`com.kasirtoko.app.kasirtoko`) dan **KasirToko Staff** (`com.kasirtoko.app.stafkasirtoko`).

---

## 1. Spesifikasi Rilis & Artefak APK Terverifikasi (Hasil Optimasi)

### A. KasirToko Admin (`v2.3.0`)
- **Repository & Branch:** `https://github.com/angga2103/kasirtoko` (branch `feat/phase2-multi-device-complete`; `main` tetap di `327b1ab`)
- **Package ID (`applicationId`):** `com.kasirtoko.app.kasirtoko` | **Launcher Label:** `KasirToko Admin`
- **Certificate Permanen (`apksigner`):** Valid (v2 scheme), `CN=KasirToko Admin Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`, RSA **4096-bit**, SHA-256: `a9:46:a3:d8:8a:0d:fb:ae:e5:6c:dd:13:d8:60:ff:f7:65:ae:ee:54:0a:6b:f2:a8:3d:34:0d:f0:51:93:42:41`
- **Varian APK Lokal (di luar Git, `C:\Users\Toshiba\KasirToko-Signing\release-builds\`):**
  1. **`KasirToko-Admin-v2.3.0-arm64-v8a-release.apk`** *(Rekomendasi utama perangkat ARM 64-bit modern)*
     - **Ukuran:** **`60,051,252` bytes** (`57.27 MiB` — turun `89.61%` dari `577,909,592` B) | `versionCode = 2005`
     - **SHA-256:** `4f3a3030f4ed9cfd4a16f03c3bdce329c53331274d3d6e315f142bf199451422`
  2. **`KasirToko-Admin-v2.3.0-armeabi-v7a-release.apk`** *(Perangkat Android 32-bit)*
     - **Ukuran:** **`58,749,632` bytes** (`56.03 MiB` — turun `89.83%`) | `versionCode = 1005`
     - **SHA-256:** `ac9ebfcfa18586e8945abf6ebb42d2110f3710d48b281309b546a61047a7e7c2`
  3. **`KasirToko-Admin-v2.3.0-arm-universal-release.apk`** *(ARM64 + ARMv7a universal, tanpa `x86_64`)*
     - **Ukuran:** **`111,926,359` bytes** (`106.74 MiB` — turun `80.63%`) | `versionCode = 5`
     - **SHA-256:** `bd45239e38e1f6fd06e2eaf1401c082c436ef68b014826c799e6755e41b88355`

### B. KasirToko Staff (`v1.0.2+3` — Rilis Terbaru)
- **Repository & Branch:** `https://github.com/angga2103/stafkasirtoko` (`main` & `feat/pos-staff-app`)
- **Package ID (`applicationId`):** `com.kasirtoko.app.stafkasirtoko` | **Launcher Label:** `KasirToko Staff`
- **Certificate Permanen (`apksigner`):** Valid (v2 scheme), `CN=KasirToko Staff Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`, RSA **4096-bit**, SHA-256: `e4:31:47:7a:7a:e0:4c:f0:86:f0:99:ba:7d:a5:3d:cf:0b:b6:5f:98:7c:bc:76:da:c0:a7:78:c8:40:60:62:32`
- **Varian APK Lokal (di luar Git, `C:\Users\Toshiba\KasirToko-Signing\release-builds\`):**
  1. **`KasirToko-Staff-v1.0.1-arm64-v8a-release.apk`** *(Rekomendasi utama perangkat ARM 64-bit modern)*
     - **Ukuran:** **`49,784,165` bytes** (`47.48 MiB` — turun `90.56%` dari `527,253,000` B) | `versionCode = 2002`
     - **SHA-256:** `4dd048fdbc42ff670f3e7c7dd05a5748b9ee4de28aad10be0339e8bb1748276e`
  2. **`KasirToko-Staff-v1.0.1-armeabi-v7a-release.apk`** *(Perangkat Android 32-bit)*
     - **Ukuran:** **`48,736,747` bytes** (`46.48 MiB` — turun `90.76%`) | `versionCode = 1002`
     - **SHA-256:** `20976d37beb39084726426d66a9b9758c51fd452fd042a1b50484dbfd02858d4`
  3. **`KasirToko-Staff-v1.0.1-arm-universal-release.apk`** *(ARM64 + ARMv7a universal, tanpa `x86_64`)*
     - **Ukuran:** **`95,890,728` bytes** (`91.45 MiB` — turun `81.81%`) | `versionCode = 2`
     - **SHA-256:** `3f1126abfcf567c8a4fe9deeafce4c75b3a748cf1eb0181a3e5fa0f37cfb81fe`

---

## 2. Pengaman Signing Keystore & Gerbang Penolakan Rilis Tanpa Kunci Permanen

- Kedua keystore permanen (`kasirtoko-admin-release.jks`, `kasirtoko-staff-release.jks`, masa berlaku 10.950 hari hingga 19 Nov 2056) beserta arsip backup AES-256-GCM (`kasirtoko-signing-backup.aesgcm`) dan catatan pemulihan offline (`SIGNING_RECOVERY.txt`) disimpan di luar repository Git pada `C:\Users\Toshiba\KasirToko-Signing\`.
- Seluruh `android/key.properties` sementara telah dihapus (`admin=False`, `staff=False`), dan gerbang penolakan rilis tanpa permanent signing di `android/app/build.gradle.kts` terverifikasi aktif (`exit 1`).

---

## 3. Tindakan Wajib Pemilik Repository Sebelum Rilis GitHub Pertama

1. Isi 4 GitHub Repository Secrets di masing-masing repository (**Settings -> Secrets and variables -> Actions**):
   - **`ANDROID_KEYSTORE_BASE64`** (isi file `.jks.b64` aplikasi terkait), **`ANDROID_KEYSTORE_PASSWORD`**, **`ANDROID_KEY_ALIAS`** (`kasirtoko_admin` / `kasirtoko_staff`), **`ANDROID_KEY_PASSWORD`** (PKCS12: bernilai sama dengan `ANDROID_KEYSTORE_PASSWORD`).
2. Merge branch `feat/phase2-multi-device-complete` -> `main` pada `kasirtoko`.
3. Push tag rilis (`v2.3.0` di `kasirtoko`, `v1.0.2` di `stafkasirtoko`) agar GitHub Actions Ubuntu runner (dengan NDK asli untuk stripping penuh `libflutter.so` + build `.aab` & split APKs) menerbitkan halaman **GitHub Release** resmi beserta `.apk` (`arm64-v8a`, `armeabi-v7a`, `arm-universal`), `.aab`, dan `.sha256`.
4. Eksekusi verifikasi perangkat keras fisik sesuai `FIELD_TEST_CHECKLIST.md`.
