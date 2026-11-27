# FINAL_QA_REPORT.md — Laporan Verifikasi & QA Akhir POS Multi-Device

Laporan ini merangkum seluruh hasil audit, pengujian terintegrasi lintas proses, perbaikan bug, verifikasi build APK Debug & Release permanen, serta batasan pengujian perangkat keras pada sistem **KasirToko Admin** (`kasirtoko`) dan **KasirToko Staff** (`stafkasirtoko`).

---

## 1. Ringkasan Eksekutif Pengujian Terverifikasi

| Komponen | Perintah Verifikasi | Hasil Terakhir | Catatan |
| :--- | :--- | :--- | :--- |
| **POS Admin Static Analysis** | `flutter analyze --no-pub --no-fatal-infos` | **PASS (Exit 0)** — `102 issues found` (53.2s) | 0 `error`, 0 `warning`; seluruh 102 temuan merupakan `info` legacy (utama `deprecated_member_use`, `unnecessary_underscores`, `use_build_context_synchronously`). |
| **POS Admin Full Test Suite** | `flutter test --no-pub -r expanded -j 1` | **PASS (Exit 0)** — `65/65` lulus (02:29) | Seluruh test Phase 1, Phase 2 E2E TLS+WSS + kapasitas, QA produksi, QA retur forensik, unit & widget lulus bersih. |
| **POS Staff Static Analysis** | `flutter analyze --no-pub --no-fatal-infos` | **PASS (Exit 0)** — `No issues found!` (6.5s) | 0 `error`, 0 `warning`, 0 `info`. |
| **POS Staff Full Test Suite** | `flutter test --no-pub -r expanded -j 1` | **PASS (Exit 0)** — `10/10` lulus (00:07) | Mencakup test inti DB cache-only, HMAC signer, barcode guard, offline lock, QuickCash, TLS pin rejection, rekonsiliasi in-flight, guard dispose `LanWsClient`, serta UI `360x640` & `1280x800`. |
| **Live Cross-Process Admin ↔ Staff E2E** | Dua proses OS nyata (`LanPosServer` Admin TLS+WSS <-> `StaffSessionController` + `LanHttpClient` + `LanWsClient` + SQLite file) | **PASS (Exit 0)** (`task-1648` 27s, `task-1649` 8s) | Verifikasi QR pairing, manual short-PIN pairing, login PIN KDF v2, sinkronisasi katalog (0 `cost_price`), buka shift, checkout tunai + pulsa laci `RJ11` single-shot, reprint (`drawer_pulse=false`), idempotency replay, **race 5 terminal bersamaan pada `stock=3`** (tepat 3 sukses, 2 ditolak, `stock=0.0`), persistensi restart Staff, recovery restart server Admin, live WS `shift_changed` & revokasi terminal (`4003`). |
| **POS Admin Release APK (`v2.3.0+5`)** | `flutter build apk --release --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation` | **PASS (Exit 0)** (221.5s) | Signed permanen RSA-4096 v2 (`577,909,592` bytes / `551.1 MB`), SHA-256 terverifikasi via `apksigner` & `aapt2`. |
| **POS Staff Release APK (`v1.0.1+2`)** | `flutter build apk --release --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation` | **PASS (Exit 0)** (168.6s) | Signed permanen RSA-4096 v2 (`527,253,000` bytes / `502.8 MB`), SHA-256 terverifikasi via `apksigner` & `aapt2`. |
| **POS Admin Debug APK (`v2.3.0+5`)** | `flutter build apk --debug --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation` | **PASS (Exit 0)** (298.5s) | Signed debug (`CN=Android Debug`, RSA 2048), `1,476,484,616` bytes, label `KasirToko Admin`. |
| **POS Staff Debug APK (`v1.0.1+2`)** | `flutter build apk --debug --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation` | **PASS (Exit 0)** (223.2s) | Signed debug (`CN=Android Debug`, RSA 2048), `1,432,829,721` bytes, label `KasirToko Staff`. |
| **Negative Release Signing Gate** | `flutter build apk --release --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation` (tanpa `key.properties`/env secrets) | **PASS / Ditolak Sesuai Kebijakan (Exit 1)** | Admin gagal (26.7s) & Staff gagal (36.9s) di `build.gradle.kts` baris 37 dengan `GradleException` eksplisit melarang release unsigned atau debug-signed. |

---

## 2. Bug Nyata yang Ditemukan Saat Integrasi & Telah Diperbaiki

1. **Sinkronisasi Penutupan Shift Shared Drawer WebSocket (`kasirtoko`):**
   - **Temuan:** Handler `_handleCloseShift` di `lib/services/server/lan_pos_server.dart` sebelumnya belum memanggil `unawaited(_broadcastWs('shift_changed', ...))`, sehingga terminal Staff pada mode `SHARED_DRAWER` tetap menganggap shift terbuka hingga polling berikutnya.
   - **Perbaikan:** Menambahkan broadcast WebSocket `shift_changed` saat shift ditutup dan menjaga panggilan `touchTerminalLastSeen` dengan guard `if (isRunning)` (serta `try/catch` pada `lib/database/multi_device_dao.dart`) guna mencegah race penutupan DB saat server shutdown.
   - **Verifikasi:** Lolos pada integrasi lintas proses `task-1648`/`task-1649` dan 65/65 suite `kasirtoko`.
2. **Race Condition StreamController Saat Dispose WebSocket (`stafkasirtoko`):**
   - **Temuan:** Saat `LanWsClient` di-dispose berdekatan dengan penutupan socket (`_onSocketClosed`), pemanggilan `.add(...)` memicu `Bad state: Cannot add new events after calling close`.
   - **Perbaikan:** Menambahkan helper `_emitEvent` dan `_emitConnectionState` yang memeriksa `!_disposed && !controller.isClosed` serta early-return di `_onSocketClosed` pada `lib/core/network/lan_ws_client.dart`, ditambah unit test regresi pada `test/widget_test.dart`.
   - **Verifikasi:** `flutter test` (`10/10` lulus) dan `task-1649` lulus bersih.
3. **Konfigurasi Heap Gradle & Proteksi Ruang Disk Build Windows:**
   - **Temuan:** `c:\StafKasirtoko\android\gradle.properties` memakai `-Xmx8G -XX:MaxMetaspaceSize=4G` yang memicu crash JVM `mmap` pada host dengan RAM terbatas saat build beruntun, serta password `keyPassword` berbeda untuk PKCS12 tidak didukung Java `KeyStore("PKCS12")` (`Given final block not properly padded`).
   - **Perbaikan:** Menyesuaikan `org.gradle.jvmargs=-Xmx2560m -XX:MaxMetaspaceSize=768m -XX:+HeapDumpOnOutOfMemoryError` pada kedua repo, menyelaraskan `keyPassword == storePassword` pada PKCS12 keystore resmi & dokumentasi, serta memperkeras `.github/workflows/release.yml` (`tr -d '[:space:]' | base64 -d` + verifikasi `application-label`).

---

## 3. Benchmark Performa Terukur (`kasirtoko`)

Pengukuran dijalankan di atas runtime host menggunakan `sqflite_common_ffi` + PointyCastle + `HttpServer.bindSecure` TLS + HMAC-SHA256 pada eksekusi akhir suite Admin:
1. **PBKDF2-HMAC-SHA256 KDF v2 (`phase1_security_kdf_test.dart`):**
   - `600000 iters = 4078 ms` pada runtime Dart VM/PointyCastle host. Benchmark pada perangkat Android target tetap wajib diuji langsung sesuai checklist lapangan.
2. **LAN Concurrent Checkout Capacity Benchmark (`phase2_lan_server_e2e_capacity_test.dart`):**
   - **2 Terminal bersamaan:** `avg = 112.8 ms`, `max = 150 ms`, `stock = 96.0`
   - **5 Terminal bersamaan:** `avg = 248.3 ms`, `max = 369 ms`, `stock = 90.0`
   - **10 Terminal bersamaan:** `avg = 501.4 ms`, `max = 784 ms`, `stock = 80.0`
3. **Race 5 Terminal Lintas Proses Nyata pada Stok Terbatas (`stock=3`):**
   - 5 terminal mengirim transaksi hampir bersamaan ke Admin: tepat 3 transaksi sukses tercommit, 2 ditolak secara deterministik, stok akhir tepat `0.0` (tanpa stok minus).

---

## 4. Verifikasi APK, Keamanan Arsip & Kompatibilitas Update

1. **Inspeksi ZIP APK Release (`zipfile` & `aapt2 dump resources`):**
   - Kedua APK release (`KasirToko-Admin-v2.3.0-release.apk` dan `KasirToko-Staff-v1.0.1-release.apk`) terverifikasi **0 kebocoran** (`Secret/DB leakage check: []` — bebas `.jks`, `.keystore`, `.b64`, `.aesgcm`, `key.properties`, `SIGNING_RECOVERY`, maupun `.db`).
   - Aset logo in-app (`assets/flutter_assets/assets/branding/kasirtoko_admin_logo.png` & `kasirtoko_staff_logo.png`) serta resource launcher adaptif (`drawable/ic_launcher_background`, `mipmap/ic_launcher`, `mipmap/ic_launcher_foreground`, `mipmap/ic_launcher_monochrome`) terkompilasi utuh.
2. **Verifikasi Kompatibilitas Update Tanpa Uninstall:**
   - Admin diuji dengan build `v2.3.1+6` vs `v2.3.0+5`: `applicationId` identik (`com.kasirtoko.app.kasirtoko`), sertifikat signing SHA-256 identik (`a9:46:a3:d8:...`), `versionCode` naik (`5 -> 6`).
   - Staff diuji dengan build `v1.0.2+3` vs `v1.0.1+2`: `applicationId` identik (`com.kasirtoko.app.stafkasirtoko`), sertifikat signing SHA-256 identik (`e4:31:47:7a:...`), `versionCode` naik (`2 -> 3`).
   - File sementara uji compat (`v2.3.1` & `v1.0.2`) sudah dihapus setelah verifikasi selesai.

---

## 5. Batasan Pengujian Perangkat Keras (Belum Dieksekusi Fisik)

Pemeriksaan `adb devices -l` menghasilkan daftar kosong (`List of devices attached` kosong — 0 perangkat fisik dan 0 emulator terpasang di workstation build). Hal berikut **belum diuji di perangkat Android fisik**:
1. Instalasi langsung via ADB / PackageInstaller antar versi serta tampilan visual ikon adaptif pada berbagai mask launcher OEM & Material You monochrome Android 13+.
2. Pemindaian QR pairing menggunakan kamera fisik (`mobile_scanner`) dan performa hardware-backed `AndroidKeyStore` pada chipset Android target (`MainActivity.kt`).
3. Ketahanan Foreground Service `specialUse` dan `ConnectivityManager.NetworkCallback` di bawah penghematan baterai OEM nyata (Doze / Background limits).
4. Pencetakan fisik Bluetooth SPP / USB OTG / LAN RAW port `9100` serta denyut fisik solenoid laci kas RJ11 (`ESC p`) pada perangkat keras toko nyata.

Lakukan seluruh verifikasi lapangan tersebut mengikuti panduan di `FIELD_TEST_CHECKLIST.md`.
