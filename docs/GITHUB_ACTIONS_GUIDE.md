# GITHUB_ACTIONS_GUIDE.md — Dokumentasi Workflow CI/CD GitHub Actions

Kedua repository (`kasirtoko` dan `stafkasirtoko`) dilengkapi workflow GitHub Actions pada direktori `.github/workflows/`.

## 1. Workflow Continuous Integration (`ci.yml`)
- **Lokasi:** `c:\kasirtoko\.github\workflows\ci.yml` dan `c:\StafKasirtoko\.github\workflows\ci.yml`
- **Trigger:** Push ke branch `main` atau `feat/**`, Pull Request ke `main`, dan `workflow_dispatch`.
- **Tahapan Eksekusi:**
  1. Setup Java JDK 17 (`temurin`) dengan caching Gradle + accept Android SDK licenses + Flutter `stable`.
  2. Instalasi `libsqlite3-0` & `libsqlite3-dev` + `flutter pub get`.
  3. Static analysis (`flutter analyze --no-pub --no-fatal-infos`) & full `flutter test --no-pub -r expanded -j 1 --file-reporter json:build/test-report.json`.
  4. Build Debug APK & upload CI artifact (`*-CI-Artifacts`: APK debug, `test-report.json`, `build-metadata.json`).

## 2. Workflow PR Legacy Guard (`kasirtoko/.github/workflows/build.yml`)
- Membatasi workflow PR legacy pada `pull_request` ke `main` dan `workflow_dispatch` untuk verifikasi build `--debug` PR (`KasirToko-Admin-PR-Debug-APK`), bukan rilis bertag.

## 3. Workflow Release APK & AAB Teroptimasi (`release.yml`)
- **Lokasi:** `c:\kasirtoko\.github\workflows\release.yml` dan `c:\StafKasirtoko\.github\workflows\release.yml`
- **Trigger:** Push tag versi `v*` atau `workflow_dispatch`.
- **Signing Secrets Wajib:** `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (gagal seketika bila kosong; tanpa fallback debug).
- **Tahapan Build & Optimasi:**
  1. Static analysis (`flutter analyze --no-pub --no-fatal-infos`) + full `flutter test --no-pub -r expanded -j 1`.
  2. Build **Split-Per-ABI** (`--split-per-abi --target-platform android-arm,android-arm64 --split-debug-info=build/app/outputs/symbols`), **ARM Universal** (`--target-platform android-arm,android-arm64 --split-debug-info=build/app/outputs/symbols`), serta **Android App Bundle** (`.aab`) dengan R8 minify + tree-shaking ikon + kompresi JNI libs + NDK `llvm-strip` penuh di runner Ubuntu.
  3. Verifikasi setiap APK lewat `apksigner` (blokir `Android Debug`) & `aapt2` (`applicationId`, `versionName`, `application-label`), generate `.sha256`, upload artifact (`retensi 90 hari`), dan terbitkan **GitHub Release** otomatis bila dijalankan dari tag `v*`.
