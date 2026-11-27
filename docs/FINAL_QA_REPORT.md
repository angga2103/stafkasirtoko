# FINAL_QA_REPORT.md — Laporan Verifikasi & QA Akhir POS Multi-Device

Laporan ini merangkum seluruh hasil audit, pengujian terintegrasi lintas proses, perbaikan bug, audit ukuran & optimasi APK release, verifikasi sertifikat permanen, serta batasan pengujian perangkat keras pada sistem **KasirToko Admin** (`kasirtoko`) dan **KasirToko Staff** (`stafkasirtoko`).

---

## 1. Ringkasan Eksekutif Pengujian Terverifikasi (Pasca-Optimasi Release)

| Komponen | Perintah Verifikasi | Hasil Terakhir | Catatan |
| :--- | :--- | :--- | :--- |
| **POS Admin Static Analysis** | `flutter analyze --no-pub --no-fatal-infos` | **PASS (Exit 0)** — `102 issues found` (`116.2s`) | 0 `error`, 0 `warning`; seluruh 102 temuan merupakan `info` legacy. |
| **POS Admin Full Test Suite** | `flutter test --no-pub -r expanded -j 1` | **PASS (Exit 0)** — `65/65` lulus (`02:21`) | Seluruh test Phase 1, Phase 2 E2E TLS+WSS + kapasitas, QA produksi, QA retur forensik, unit & widget lulus pasca optimasi `pubspec.yaml` & `build.gradle.kts`. |
| **POS Staff Static Analysis** | `flutter analyze --no-pub --no-fatal-infos` | **PASS (Exit 0)** — `No issues found!` (`46.5s`) | 0 `error`, 0 `warning`, 0 `info`. |
| **POS Staff Full Test Suite** | `flutter test --no-pub -r expanded -j 1` | **PASS (Exit 0)** — `10/10` lulus (`00:05`) | Seluruh test isolasi cache-only DB, HMAC signer, barcode guard, offline lock, QuickCash, TLS pin rejection, rekonsiliasi in-flight, guard dispose `LanWsClient`, serta UI `360x640` & `1280x800` lulus pasca optimasi. |
| **Live Cross-Process Admin ↔ Staff E2E** | Dua proses OS nyata (`LanPosServer` Admin TLS+WSS <-> `StaffSessionController` + `LanHttpClient` + `LanWsClient` + SQLite file) | **PASS (Exit 0)** (`27s` Admin driver, `8s` Staff driver) | Verifikasi QR pairing, manual short-PIN pairing, login PIN KDF v2, katalog (0 `cost_price`), buka shift, checkout tunai + pulsa laci `RJ11` single-shot, reprint (`drawer_pulse=false`), idempotency replay, race 5 terminal pada `stock=3` (`3` sukses, `2` ditolak, `stock=0.0`), persistensi restart, live WS `shift_changed` & revokasi (`4003`). |
| **Admin Optimized Release APKs (`v2.3.0+5`)** | `--split-per-abi` & `--target-platform android-arm,android-arm64 --split-debug-info` | **PASS (Exit 0)** (`748.0s` split, `440.0s` ARM univ) | `arm64-v8a`: **`60,051,252` B** (`57.27 MiB`, **-89.61%**), `armeabi-v7a`: **`58,749,632` B** (`56.03 MiB`, **-89.83%**), `arm-universal`: **`111,926,359` B** (`106.74 MiB`, **-80.63%**). |
| **Staff Optimized Release APKs (`v1.0.1+2`)** | `--split-per-abi` & `--target-platform android-arm,android-arm64 --split-debug-info` | **PASS (Exit 0)** (`263.7s` split, `245.6s` ARM univ) | `arm64-v8a`: **`49,784,165` B** (`47.48 MiB`, **-90.56%**), `armeabi-v7a`: **`48,736,747` B** (`46.48 MiB`, **-90.76%**), `arm-universal`: **`95,890,728` B** (`91.45 MiB`, **-81.81%**). |
| **Negative Release Signing Gate** | `flutter build apk --release ...` tanpa `key.properties`/env secrets | **PASS / Ditolak Sesuai Kebijakan (Exit 1)** | Admin gagal (26.7s) & Staff gagal (36.9s) di `build.gradle.kts` baris 37 melarang rilis tanpa signing permanen. |

---

## 2. Audit & Optimasi Ukuran APK Release (`577.9 MB -> 57.3 MB` & `527.3 MB -> 47.5 MB`)

### A. Kontribusi Komponen APK Sebelum Optimasi
| Komponen | Admin (`577,909,592` B) | Persentase Admin | Staff (`527,253,000` B) | Persentase Staff | Catatan Analisis |
| :--- | ---: | ---: | ---: | ---: | :--- |
| **`lib/x86_64/`** | `198,115,224` B | `34.28%` | `180,971,320` B | `34.32%` | ABI emulator/x64 desktop — tidak dipakai perangkat Android ARM |
| **`lib/arm64-v8a/`** | `194,809,704` B | `33.71%` | `178,964,072` B | `33.94%` | Berisi `165.16 MB` `libflutter.so` unstripped + `libapp.so` + ML Kit |
| **`lib/armeabi-v7a/`** | `177,269,816` B | `30.67%` | `163,880,408` B | `31.08%` | Berisi `151.59 MB` `libflutter.so` unstripped + `libapp.so` + ML Kit |
| **`assets/` native/ML Kit** | `4,724,789` B | `0.82%` | `881,863` B | `0.17%` | Model TFLite ML Kit (`face_detection` liveness & `barcode_scanning`) — **dipertahankan penuh** |
| **`classes.dex`** | `1,538,825` B | `0.27%` | `1,146,416` B | `0.22%` | Bytecode Java/Kotlin ter-R8 |
| **`flutter_assets/` (runtime/fonts)** | `786,519` B | `0.14%` | `779,193` B | `0.15%` | Memuat `MaterialIcons` penuh (`556 KB`) & `CupertinoIcons` tidak terpakai (`116 KB`) |
| **`resources.arsc` + `res/`** | `375,531` B | `0.07%` | `388,708` B | `0.07%` | Resource XML & ikon launcher PNG |
| **`assets/branding/*_logo.png`** | `34,773` B | `0.01%` | `41,079` B | `0.01%` | Logo in-app resmi |
| **`META-INF/` + `AndroidManifest` + `DebugProbesKt.bin` + lain** | `30,683` B | `0.01%` | `21,795` B | `0.00%` | Memuat duplikat `LICENSE.txt` (`10 KB`) & coroutine `DebugProbesKt.bin` |

### B. Penyebab Utama Ukuran Awal Membengkak & Solusi yang Diterapkan
1. **Temuan Utama #1 (83–92% total APK): DWARF Debug Symbols di `libflutter.so` & Stub NDK Lokal Windows:**
   - Inspeksi ELF `lib/arm64-v8a/libflutter.so` (`165,164,528` B) menunjukkan `153,419,040` B (**92.9%**) adalah section debug non-runtime (`.debug_str` `61.09 MB`, `.debug_info` `49.68 MB`, `.debug_loc` `19.57 MB`, `.debug_line` `10.30 MB`, `.debug_ranges` `5.53 MB`, `.strtab` `4.27 MB`, `.symtab` `2.95 MB`) sementara segmen runtime `PT_*` hanya berakhir di **`11,745,488` B** (`armeabi-v7a`: **`8,614,072` B**).
   - Penyebab lokal Windows: executable `llvm-strip.exe`, `llvm-objcopy.exe`, dan `llvm-readelf.exe` pada `C:\src\android-sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\` berukuran `4,096` byte ternyata merupakan stub .NET `File.Copy` tanpa proses stripping. Hal ini juga menyebabkan `flutter build appbundle --release` gagal pada pengecekan lokal NDK strip, sementara **runner GitHub Actions `ubuntu-latest` memiliki NDK Linux penuh** yang men-strip simbol tersebut bersih saat build rilis CI.
2. **Native Libraries Tidak Terkompresi (`[STORED]` vs `[DEFLATED]`):**
   - Diaktifkan `packaging { jniLibs { useLegacyPackaging = true } }` di `build.gradle.kts` kedua repo sehingga seluruh `.so` dikompresi (`~60–75%` lebih kecil saat distribusi APK).
3. **Semua ABI (`x86_64`, `arm64-v8a`, `armeabi-v7a`) Digabung + Bug Filter ABI Plugin Flutter:**
   - Selain menghapus `x86_64` lewat `--target-platform android-arm,android-arm64` & `--split-per-abi`, audit juga menemukan `FlutterPlugin.kt` tetap memasukkan `lib/x86_64/*.so` dari plugin pihak ketiga (`libbarhopper_v3.so`, `libface_detector_v2_jni.so`) saat non-split. Ditambahkan guard `packaging.jniLibs.excludes` untuk `**/x86_64/*.so` & `**/x86/*.so` bila `--target-platform` tidak meminta x64/x86.
4. **Tree-Shaking Ikon, Split Debug Info Dart & Pembersihan Bloat:**
   - Menghapus `--no-tree-shake-icons`: `MaterialIcons-Regular.otf` turun **`1,645,184 -> 28,884` B** (Admin, `-98.2%`) dan **`1,645,184 -> 6,244` B** (Staff, `-99.6%`).
   - Menghapus dependensi `cupertino_icons` yang 0 referensi (`-257 KB` font) dan memindahkan `pointycastle` di Staff ke `dev_dependencies`.
   - Menambahkan `--split-debug-info=build/app/outputs/symbols` (`libapp.so` Admin `16.14 MB -> 5.51 MB` terkompresi), `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-android-optimize.txt` + `proguard-rules.pro`, serta mengecualikan `DebugProbesKt.bin` dan `META-INF/**/LICENSE*`.

### C. Perbandingan Ukuran Sebelum vs Sesudah Optimasi (Hasil Terukur Lokal)
| Varian APK | Sebelum Optimasi | Sesudah Optimasi | Pengurangan | Sertifikat & Status Verifikasi |
| :--- | ---: | ---: | ---: | :--- |
| **Admin `arm64-v8a` Split** | `577,909,592` B (`551.1 MiB`) | **`60,051,252` B (`57.27 MiB`)** | **-89.61%** (`-517.86 MB`) | RSA-4096 `a9:46:a3:d8...` Valid (`versionCode=2005`) |
| **Admin `armeabi-v7a` Split** | `577,909,592` B (`551.1 MiB`) | **`58,749,632` B (`56.03 MiB`)** | **-89.83%** (`-519.16 MB`) | RSA-4096 `a9:46:a3:d8...` Valid (`versionCode=1005`) |
| **Admin ARM Universal** | `577,909,592` B (`551.1 MiB`) | **`111,926,359` B (`106.74 MiB`)** | **-80.63%** (`-465.98 MB`) | RSA-4096 `a9:46:a3:d8...` Valid (`versionCode=5`) |
| **Staff `arm64-v8a` Split** | `527,253,000` B (`502.8 MiB`) | **`49,784,165` B (`47.48 MiB`)** | **-90.56%** (`-477.47 MB`) | RSA-4096 `e4:31:47:7a...` Valid (`versionCode=2002`) |
| **Staff `armeabi-v7a` Split** | `527,253,000` B (`502.8 MiB`) | **`48,736,747` B (`46.48 MiB`)** | **-90.76%** (`-478.52 MB`) | RSA-4096 `e4:31:47:7a...` Valid (`versionCode=1002`) |
| **Staff ARM Universal** | `527,253,000` B (`502.8 MiB`) | **`95,890,728` B (`91.45 MiB`)** | **-81.81%** (`-431.36 MB`) | RSA-4096 `e4:31:47:7a...` Valid (`versionCode=2`) |

> [!NOTE]
> Pada hasil build lokal di atas, `libflutter.so` masih menyumbang `~42.17 MB` terkompresi (`arm64-v8a`) / `~41.26 MB` (`armeabi-v7a`) karena stub `llvm-strip.exe` 4 KB lokal Windows. Saat workflow `release.yml` berjalan di **GitHub Actions Linux runner** dengan Android NDK asli, `.debug_*` / `.symtab` pada `libflutter.so` ter-strip bersih (~`11.7 MB` raw -> `~4.5 MB` terkompresi), sehingga ukuran APK split produksi di CI diperkirakan berada di kisaran **`~18–23 MB` (Admin)** dan **`~10–13 MB` (Staff)**.

---

## 3. Benchmark Performa Terukur (`kasirtoko`)

Pengukuran pasca-optimasi (`task-2124`):
1. **PBKDF2-HMAC-SHA256 KDF v2 (`600.000` iterasi):** `4275 ms` pada runtime Dart/PointyCastle host.
2. **LAN Concurrent Checkout Benchmark (Real TLS + HMAC + SQLite):**
   - `2` terminal: `avg = 119.0 ms`, `max = 157 ms`, `stock = 96.0`
   - `5` terminal: `avg = 273.0 ms`, `max = 391 ms`, `stock = 90.0`
   - `10` terminal: `avg = 553.0 ms`, `max = 841 ms`, `stock = 80.0`

---

## 4. Bug Nyata yang Telah Diperbaiki
1. Broadcast `shift_changed` saat `_handleCloseShift` & guard `touchTerminalLastSeen` ketika shutdown di `kasirtoko`.
2. Guard `_emitEvent` / `_emitConnectionState` & `_onSocketClosed` dispose race pada `LanWsClient` di `stafkasirtoko` (+ test regresi).
3. Penyelarasan PKCS12 `keyPassword == storePassword`, penyesuaian Gradle heap `-Xmx2560m`, penghapusan dependensi tak terpakai, tree-shaking ikon, kompresi JNI libs, dan guard exclude `x86_64`/`x86`.

---

## 5. Batasan Pengujian Perangkat Keras (Belum Dieksekusi Fisik)

`adb devices -l` mengembalikan daftar kosong pada workstation build. Pengujian pada hardware Android nyata (kamera `mobile_scanner`, `AndroidKeyStore` hardware chipset, Foreground Service di bawah Doze, printer Bluetooth/USB/LAN + laci kas RJ11, serta instalasi APK split/universal pada tablet POS fisik) mengikuti [`FIELD_TEST_CHECKLIST.md`](FIELD_TEST_CHECKLIST.md).
