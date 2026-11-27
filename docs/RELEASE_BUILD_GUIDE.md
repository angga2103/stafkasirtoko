# RELEASE_BUILD_GUIDE.md — Panduan Build & Release Otomatis

Dokumen ini menjelaskan cara membangun APK Debug/Release secara lokal maupun melalui GitHub Actions CI/CD untuk **KasirToko Admin** (`kasirtoko`) dan **KasirToko Staff** (`stafkasirtoko`).

---

## 1. Alur GitHub Actions CI & Release Otomatis

### A. Continuous Integration (`ci.yml`)
Berjalan otomatis pada `push` ke `main`, `feat/**`, `pull_request` ke `main`, dan `workflow_dispatch`:
1. Setup JDK 17 (`temurin`) & Android SDK Licenses.
2. Setup Flutter `stable` + instalasi `libsqlite3-0 libsqlite3-dev`.
3. `flutter pub get`, `flutter analyze --no-pub --no-fatal-infos`.
4. Eksekusi penuh seluruh `flutter test --no-pub -r expanded -j 1`.
5. Build `app-debug.apk` untuk validasi integrasi.
6. Upload CI artifact (`KasirToko-Admin-CI-Artifacts` / `KasirToko-Staff-CI-Artifacts`) berisi APK debug, `test-report.json`, dan `build-metadata.json`.

### B. Automated Signed Release (`release.yml`)
Berjalan otomatis ketika tag versi `v*` di-push (misal `v2.3.0` pada Admin atau `v1.0.1` pada Staff) atau via **Actions -> Run workflow (`workflow_dispatch`)**:
1. Memastikan seluruh 4 GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) tersedia — **gagal otomatis** bila secret belum diisi (tidak pernah memproduksi release unsigned/debug).
2. Mendekode keystore sementara ke `$RUNNER_TEMP` dan membuat `android/key.properties` sementara (dihapus via `trap EXIT`).
3. Menjalankan static analysis + full test suite.
4. Membangun `flutter build apk --release` dan `flutter build appbundle --release`.
5. Memverifikasi APK menggunakan `apksigner verify --verbose --print-certs` (memastikan sertifikat bukan `Android Debug`) dan `aapt2 dump badging` (memastikan `applicationId`, `versionCode`, dan `versionName` sesuai `pubspec.yaml`).
6. Menghasilkan `KasirToko-Admin-vX.Y.Z-release.apk` / `KasirToko-Staff-vX.Y.Z-release.apk`, `.aab`, serta checksum `.sha256`.
7. Mengunggah artifact release (retensi 90 hari) dan menerbitkan **GitHub Release** lengkap dengan release notes berisi SHA-256 checksum & fingerprint sertifikat.

---

## 2. Langkah Membuat Release Baru di GitHub

1. Pastikan `version:` di `pubspec.yaml` sudah dinaikkan dengan aturan:
   - Naikkan `versionName` (`X.Y.Z`).
   - **Selalu naikkan `versionCode` (+N)** agar Android menerima pembaruan tanpa uninstall.
2. Commit dan push perubahan ke repository:
   ```bash
   git add pubspec.yaml
   git commit -m "chore(release): bump version to vX.Y.Z"
   git push origin main
   ```
3. Buat dan push tag versi:
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
4. Pantau tab **Actions -> Release** di GitHub hingga selesai dan periksa halaman **Releases** untuk mengunduh APK bertanda tangan permanen serta file `.sha256`.

---

## 3. Build Release Lokal Secara Manual (Tanpa Menyentuh Git)

1. Buat `android/key.properties` sementara (sudah masuk `.gitignore`):
   ```properties
   storePassword=<ISI_DARI_SIGNING_RECOVERY>
   keyPassword=<ISI_DARI_SIGNING_RECOVERY>
   keyAlias=<kasirtoko_admin_atau_kasirtoko_staff>
   storeFile=C:/Users/Toshiba/KasirToko-Signing/<nama-keystore>.jks
   ```
2. Jalankan build dan verifikasi:
   ```bash
   flutter pub get
   flutter analyze --no-pub --no-fatal-infos
   flutter test --no-pub -r expanded -j 1
   flutter build apk --release --no-tree-shake-icons --android-skip-build-dependency-validation
   ```
3. Verifikasi tanda tangan & manifest APK:
   ```bash
   apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
   aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk
   ```
4. **Wajib:** Hapus `android/key.properties` segera setelah build lokal selesai agar tidak tertinggal di folder proyek.
