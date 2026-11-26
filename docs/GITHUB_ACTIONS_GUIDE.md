# GITHUB_ACTIONS_GUIDE.md — Dokumentasi Workflow CI/CD GitHub Actions

Kedua repository (`kasirtoko` dan `stafkasirtoko`) dilengkapi workflow GitHub Actions pada direktori `.github/workflows/`.

## 1. Workflow Continuous Integration (`ci.yml`)
- **Lokasi:**
  - Admin: `c:\kasirtoko\.github\workflows\ci.yml`
  - Staff: `c:\StafKasirtoko\.github\workflows\ci.yml`
- **Trigger:** Push ke branch `main` atau `feat/**`, Pull Request ke `main`, dan `workflow_dispatch`.
- **Tahapan Eksekusi:**
  1. Setup Java JDK 17 (`temurin`) dengan caching Gradle.
  2. Accept Android SDK Licenses.
  3. Setup Flutter `stable` dengan caching pub.
  4. Instalasi `libsqlite3-0` dan `libsqlite3-dev` untuk `sqflite_common_ffi`.
  5. `flutter pub get`.
  6. Pengecekan format (`dart format --output=none --set-exit-if-changed`).
  7. Analisis statis (`flutter analyze --no-pub`).
  8. Menjalankan seluruh test suite dengan JSON reporter (`flutter test --no-pub -r expanded -j 1 --file-reporter json:build/test-report.json`).
  9. Build Android Debug APK (`flutter build apk --debug --no-tree-shake-icons --android-skip-build-dependency-validation`).
  10. Menghasilkan `build-metadata.json` berisi `app`, `version`, `commit_sha`, `ref`, `built_at_utc`.
  11. Upload artifacts (`*-CI-Artifacts`: APK debug, `test-report.json`, `build-metadata.json`).

## 2. Workflow Release APK (`release.yml`)
- **Lokasi:**
  - Admin: `c:\kasirtoko\.github\workflows\release.yml`
  - Staff: `c:\StafKasirtoko\.github\workflows\release.yml`
- **Trigger:** Push tag `v*` atau `workflow_dispatch`.
- **Penanganan Signing Secrets (Aman & Tanpa Keystore Palsu):**
  - Tambahkan GitHub Repository Secrets berikut bila ingin memproduksi APK release bertanda tangan produksi:
    - `ANDROID_KEYSTORE_BASE64`
    - `ANDROID_KEYSTORE_PASSWORD`
    - `ANDROID_KEY_ALIAS`
    - `ANDROID_KEY_PASSWORD`
  - Jika keempat secret tersedia, runner mendekode keystore sementara ke `/tmp/release.jks`, membangun `--release` APK, dan menghapus file keystore + `key.properties` segera setelah build selesai.
  - Jika secret belum dikonfigurasi, workflow **tidak membuat keystore palsu**, melainkan memberi notice jujur dan membangun APK debug fallback agar artifact tetap dapat diuji.
