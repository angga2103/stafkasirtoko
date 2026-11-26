# FINAL_QA_REPORT.md — Laporan Verifikasi & QA Akhir POS Multi-Device

Laporan ini merangkum seluruh hasil pengujian terverifikasi pasca-edit akhir pada repository **POS Admin** (`c:\kasirtoko`, branch `feat/phase2-multi-device-complete`) dan **POS Staff** (`c:\StafKasirtoko`, branch `feat/pos-staff-app`), beserta batasan pengujian perangkat keras secara jujur.

---

## 1. Ringkasan Eksekutif Pengujian Terverifikasi

| Komponen | Perintah Verifikasi | Hasil Akhir | Catatan |
| :--- | :--- | :--- | :--- |
| **POS Admin Static Analysis** | `flutter analyze --no-pub --no-fatal-infos` | **PASS (Exit 0)** — `102 issues found` (44.1s) | Seluruh temuan adalah `info` (mayoritas deprecations legacy pra-Phase 2); 0 `error` dan 0 `warning`. |
| **POS Admin Test Suite** | `flutter test --no-pub -r expanded -j 1` | **PASS (Exit 0)** — `65/65` lulus (02:38) | Mencakup test Phase 1, Phase 2 E2E TLS+WSS, kapasitas, QA produksi 21 skenario, QA retur forensik, unit & widget. |
| **POS Admin Debug APK Build** | `flutter build apk --debug --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation` | **PASS (Exit 0)** (`788.7s`) | Output: `C:\kasirtoko\build\app\outputs\flutter-apk\app-debug.apk` (`1,476,323,769` bytes). |
| **POS Staff Static Analysis** | `flutter analyze --no-pub` | **PASS (Exit 0)** — `No issues found!` (56.5s) | 0 `error`, 0 `warning`, 0 `info`. |
| **POS Staff Test Suite** | `flutter test --no-pub -r expanded -j 1 --timeout 30s` | **PASS (Exit 0)** — `9/9` lulus (00:07) | Mencakup isolasi cache DB (0 `cost_price`, batas 30 struk), HMAC signer, barcode guard, offline lock, QuickCash, TLS pin rejection, in-flight drop reconciliation, & UI responsif `360x640` / `1280x800`. |
| **POS Staff Debug APK Build** | `flutter build apk --debug --no-tree-shake-icons --android-skip-build-dependency-validation` | **PASS (Exit 0)** (`866.1s`) | Output: `C:\StafKasirtoko\build\app\outputs\flutter-apk\app-debug.apk` (`1,432,641,694` bytes). |

> [!NOTE]
> Pemeriksaan `dart format --output=none --set-exit-if-changed lib/ test/` pada `c:\StafKasirtoko` mencatat perbedaan whitespace pada 17 dari 19 file; di workflow `.github/workflows/ci.yml` pemeriksaan format dijalankan non-blocking (`|| true`).

---

## 2. Benchmark Performa Terukur (`kasirtoko`)

Pengukuran dijalankan langsung di atas runtime nyata menggunakan `sqflite_common_ffi` + PointyCastle + `HttpServer.bindSecure` TLS + HMAC-SHA256 pada suite pengujian akhir (`task-1380`):

1. **PBKDF2-HMAC-SHA256 KDF v2 (`phase1_security_kdf_test.dart`):**
   - `600000 iters = 4218 ms` (terverifikasi pada runtime Dart/PointyCastle host; pada perangkat Android produksi, verifikasi benchmark melalui jembatan native tetap direkomendasikan).
2. **LAN Concurrent Checkout Capacity Benchmark (`phase2_lan_server_e2e_capacity_test.dart` — Real TLS + HMAC + SQLite atomik serial):**
   - **2 Terminal aktif bersamaan:** `avg = 112.5 ms`, `max = 148 ms`, `stock = 96.0` (dari awal 100.0, tepat 4 unit terjual, tanpa race condition).
   - **5 Terminal aktif bersamaan:** `avg = 258.3 ms`, `max = 381 ms`, `stock = 90.0` (tepat 10 unit terjual).
   - **10 Terminal aktif bersamaan:** `avg = 509.5 ms`, `max = 796 ms`, `stock = 80.0` (tepat 20 unit terjual).

---

## 3. Matriks Cakupan Uji Otomatis

### POS Admin (`c:\kasirtoko\test\`)
- [`phase1_cash_register_shift_void_test.dart`](file:///c:/kasirtoko/test/phase1_cash_register_shift_void_test.dart): `SHARED_DRAWER`, `INDIVIDUAL_DRAWER` + deterministik `cash_register_assignments`, dan closed-shift void non-mutatif.
- [`phase1_db_v5_migration_test.dart`](file:///c:/kasirtoko/test/phase1_db_v5_migration_test.dart): Backup & verifikasi pra-migrasi, integritas WAL/FK/`busy_timeout`, normalisasi open shift ganda legacy, rollback migrasi rusak.
- [`phase1_security_kdf_test.dart`](file:///c:/kasirtoko/test/phase1_security_kdf_test.dart): Vektor RFC PBKDF2-HMAC-SHA256, format PHC v2, migrasi transparan `legacy_v1`, rate limit & lockout PIN, pemisahan salt PIN vs password, benchmark KDF.
- [`phase2_lan_server_e2e_capacity_test.dart`](file:///c:/kasirtoko/test/phase2_lan_server_e2e_capacity_test.dart): 22 skenario keamanan & alur multi-device E2E di atas `HttpServer.bindSecure` TLS + WebSocket `/ws/v1/terminal` (pairing QR single-use, validasi HMAC/nonce anti-replay/clock drift, pin rejection, checkout otoritatif hitung ulang harga/promo/diskon/pajak/kredit/Kasbon, single-shot RJ11 `drawer_pulse_sent`, antrean print serial/retry, revokasi real-time close code `4003`, serta uji kapasitas 2/5/10 terminal).
- [`production_qa_scenarios_test.dart`](file:///c:/kasirtoko/test/production_qa_scenarios_test.dart), [`return_system_forensic_qa_test.dart`](file:///c:/kasirtoko/test/return_system_forensic_qa_test.dart), [`unit_logic_test.dart`](file:///c:/kasirtoko/test/unit_logic_test.dart), [`widget_test.dart`](file:///c:/kasirtoko/test/widget_test.dart): Seluruh fitur POS single-device legacy tetap teruji utuh (`65/65` lulus).

### POS Staff (`c:\StafKasirtoko\test\`)
- [`widget_test.dart`](file:///c:/StafKasirtoko/test/widget_test.dart): Isolasi schema cache-only (ketiadaan `cost_price`, ledger pusat, maupun kredensial kasir lain + batas max 30 baris `recent_receipt_cache`), kalibrasi clock offset & canonical HMAC `RequestSigner`, debounce `BarcodeScanGuard`, penguncian checkout saat offline (`canSubmitCheckout == false`) + persistensi keranjang aktif, perhitungan nominasi `QuickCashHelper`, penolakan TLS pin mismatch (`LanHttpClient`), serta rendering responsif `PairingScreen` & `StaffPosScreen` pada viewport `360x640` dan `1280x800` tanpa overflow.
- [`reconciliation_and_tls_rotation_test.dart`](file:///c:/StafKasirtoko/test/reconciliation_and_tls_rotation_test.dart): Drop koneksi TLS di tengah request checkout POST (`pending_checkout_intents`) diikuti rekonsiliasi `GET /api/v1/transactions/by-idempotency/{key}` pasca-reconnect tanpa pengiriman checkout duplikat, serta dukungan pin sertifikat transisi (`nextSha256`).

---

## 4. Resolusi Kendala Build Android & CI

- **NDK Lokal Tidak Lengkap vs `path_provider_android 2.3.1`:** SDK Android lokal hanya memiliki `ndk\28.2.13676358\toolchains` tanpa file `android.toolchain.cmake` / `platforms`, sementara `path_provider_android 2.3.1` menarik paket `jni` + `jni_flutter` yang mewajibkan kompilasi CMake C++. Penambahan `dependency_overrides: path_provider_android: ">=2.2.5 <2.3.0"` pada kedua `pubspec.yaml` mengembalikan ke `2.2.15` (pure Android Kotlin, masih dalam rentang resmi `path_provider: ^2.2.5`) sehingga kedua debug APK terkompilasi bersih (`exit code 0`).
- **Signing Keystore Release:** Kedua `android/app/build.gradle.kts` mendukung `android/key.properties` bila disediakan saat rilis CI melalui GitHub Secrets (`ANDROID_KEYSTORE_*`), dengan fallback aman ke debug signing jika tidak tersedia agar tidak ada keystore palsu yang difabrikasi.
- **Static Analysis Gate Admin CI:** Workflow `c:\kasirtoko\.github\workflows\ci.yml` dan `release.yml` menggunakan `flutter analyze --no-pub --no-fatal-infos` agar 102 `info` legacy tidak menggagalkan pipeline sambil tetap memblokir setiap `warning` dan `error`.

---

## 5. Batasan Pengujian Perangkat Keras (Belum Dieksekusi Fisik)

Hasil `adb devices` di workstation pengujian mengembalikan daftar kosong (0 perangkat fisik Android dan 0 emulator terpasang). Oleh karena itu, hal berikut **belum diverifikasi di atas hardware Android fisik**:
1. Pemindaian QR langsung menggunakan kamera fisik (`mobile_scanner`) dan enkripsi `AndroidKeyStore` hardware-backed di `MainActivity.kt` pada perangkat Android target (teruji di host melalui `SecretVault` / `SoftwareAesGcmSecretVault` serta `MemoryCredentialStorage`, sedangkan kode Kotlin terkompilasi dalam build APK Android).
2. Persistent behavior Foreground Service `specialUse` dan `ConnectivityManager.NetworkCallback` pada Android 13/14+ nyata di balik Doze/vendor battery optimization.
3. Pencetakan fisik Bluetooth SPP / USB OTG / LAN RAW port 9100 serta denyut fisik solenoid laci kas RJ11 (`ESC p`) pada printer thermal & laci kas nyata (terverifikasi di layer protokol ESC/POS byte generator, enqueue serial `print_jobs`, otorisasi 6 syarat laci kas, dan atomic `drawer_pulse_sent`).
