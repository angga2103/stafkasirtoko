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
  6. Pengecekan format (`dart format --output=none --set-exit-if-changed`, non-blocking di CI).
  7. Analisis statis (`flutter analyze --no-pub --no-fatal-infos`).
  8. Menjalankan seluruh test suite dengan JSON reporter (`flutter test --no-pub -r expanded -j 1 --file-reporter json:build/test-report.json`).
  9. Build Android Debug APK (`flutter build apk --debug --no-tree-shake-icons --android-skip-build-dependency-validation`) memakai signing debug untuk validasi build.
  10. Menghasilkan `build-metadata.json` berisi `app`, `version`, `commit_sha`, `ref`, `built_at_utc`.
  11. Upload artifacts (`*-CI-Artifacts`: APK debug, `test-report.json`, `build-metadata.json`).

## 2. Workflow PR Legacy Guard (`kasirtoko/.github/workflows/build.yml`)
- Pada `kasirtoko`, workflow lama `build.yml` dibatasi hanya pada `pull_request` ke `main` dan `workflow_dispatch` untuk membangun `KasirToko-Admin-PR-Debug-APK` (`--debug`), tidak lagi memproduksi rilis bertag yang menggunakan keystore debug runner.

## 3. Workflow Release APK & AAB Permanen (`release.yml`)
- **Lokasi:**
  - Admin: `c:\kasirtoko\.github\workflows\release.yml`
  - Staff: `c:\StafKasirtoko\.github\workflows\release.yml`
- **Trigger:** Push tag versi `v*` (contoh `v2.3.0` di Admin, `v1.0.1` di Staff) atau `workflow_dispatch`.
- **Kebutuhan GitHub Repository Secrets (Wajib di Masing-Masing Repository):**
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- **Tahapan Eksekusi & Penegakan Keamanan:**
  1. Static analysis (`flutter analyze --no-pub --no-fatal-infos`) dan full `flutter test --no-pub -r expanded -j 1`.
  2. Validasi keempat `ANDROID_KEYSTORE_*` secrets — workflow **gagal seketika (`exit 1`)** bila ada secret yang kosong (tidak ada fallback ke debug keystore maupun pembuatan keystore palsu).
  3. Mendekode `ANDROID_KEYSTORE_BASE64` (`tr -d '[:space:]' | base64 -d`) ke `$RUNNER_TEMP` dan menulis `android/key.properties` sementara yang otomatis dihapus melalui `trap cleanup EXIT`.
  4. Build `flutter build apk --release` dan `flutter build appbundle --release` (`.apk` dan `.aab`).
  5. Verifikasi `apksigner verify --verbose --print-certs` (memblokir bila terdeteksi `Android Debug`), `aapt2 dump badging` (memverifikasi `applicationId`, `versionCode`, `versionName`, dan `application-label`), serta menghasilkan file `.sha256` + `release-notes.md`.
  6. Mengunggah artifact release (`KasirToko-Admin-Release` / `KasirToko-Staff-Release`, retensi 90 hari) dan menerbitkan **GitHub Release** resmi bila dijalankan dari tag `refs/tags/v*`.
