# Laporan Final QA Arsitektur Operasional KasirToko

Dokumen ini mencatat hasil verifikasi statis, unit/integration/E2E/UI tests, build rilis APK bertanda tangan permanen RSA-4096, serta checklist uji perangkat Android nyata untuk **KasirToko Admin v2.4.0+7** dan **KasirToko Staff v1.1.0+5**.

## 1. Ringkasan Verifikasi Otomatis

### A. KasirToko Admin (`c:\kasirtoko`, v2.4.0+7)
- **Static Analysis (`flutter analyze --no-pub --no-fatal-infos`)**: Exit code `0` (`0` errors, `0` warnings; `106` `info` hints pra-eksisting).
- **Full Test Suite (`flutter test --no-pub -r expanded -j 1`)**: Exit code `0` — **74 passed, 0 failed, 0 skipped**.
- **Cakupan Test Suite Baru (`test/phase3_operational_architecture_test.dart`)**:
  1. **Migrasi DB v6 -> v7 Non-Destruktif**: Pembuatan backup pra-migrasi terverifikasi (`*_pre_v7_backup.db` + `PRAGMA integrity_check == 'ok'`), pelestarian data pengguna/produk/transaksi/terminal lama, pembuatan `session_policies`, `server_network_endpoints`, `backup_jobs`, `backup_artifacts`, serta konsistensi `server_id` permanen lintas buka-tutup DB.
  2. **Batas Sesi Atomik & Race Concurrency**: 2 permintaan login `POST /api/v1/auth/pin-login` bersamaan untuk kasir yang sama (`limit=1`) diserialisasi ketat oleh mutex per-kasir + transaksi SQLite (`1` sukses `200`, `1` ditolak `409 SESSION_LIMIT_EXCEEDED`, sesi HP pertama tetap valid); penegakan limit `warehouse=1` & `supervisor=2`; audit log `login_staff_ditolak_batas_sesi`.
  3. **3 Kasir / 3 HP + Pencabutan Sesi + Shift Bersama**: Pencabutan sesi tunggal (`revokeSessionById`), pencabutan seluruh sesi akun (`revokeAllSessionsForCashier`), penonaktifan karyawan (`setUserActive(false)`), penutupan WebSocket `4001`, verifikasi shift bersama `SHARED_DRAWER` tetap terbuka, replay idempotency tanpa duplikasi stok, serta pembaruan kebijakan role via `AuthProvider`.
  4. **Backup Terenkripsi `.ktbak` & Pemulihan Lintas Perangkat**: Pembuatan snapshot via `VACUUM INTO` dengan header `KTBAK001` (AES-256-GCM), salinan sekunder, verifikasi tes restore read-only (`PRAGMA integrity_check == 'ok'`), penolakan arsip korup 1-byte, penjagaan ruang penyimpanan rendah (`< 50 MB`), simulasi ganti Keystore HP baru + pemulihan sukses via Recovery Passphrase + penyimpanan artifak `pre_restore`.
  5. **Endpoint Jaringan & `PosServerProvider`**: Eksposur `server_id` dan endpoint `primary_router`/`backup_hotspot` di `/api/v1/health`.

### B. KasirToko Staff (`c:\StafKasirtoko`, v1.1.0+5)
- **Static Analysis (`flutter analyze --no-pub --no-fatal-infos`)**: Exit code `0` — **No issues found! (`0` errors, `0` warnings, `0` infos)**.
- **Full Test Suite (`flutter test --no-pub -r expanded -j 1`)**: Exit code `0` — **31 passed, 0 failed, 0 skipped**.
- **Cakupan Test Suite Baru (`test/operational_failover_and_security_test.dart` & `test/operational_ui_diagnostics_test.dart`)**:
  1. **Failover Router -> Hotspot Otomatis**: Perpindahan otomatis dari `primaryServerUrl` yang mati ke `backupServerUrl` (`Hotspot Cadangan`) sambil mempertahankan `sessionToken`, keranjang belanja, pin TLS SHA-256, dan status `canSubmitCheckout == true`.
  2. **Penolakan Keamanan Failover**: Endpoint dengan `server_id` berbeda maupun sertifikat TLS tidak cocok ditolak ketat dan memindah status ke `Server Tidak Tersedia` (`canSubmitCheckout == false`).
  3. **UDP LAN Discovery Terfilter (`LanDiscoveryClient`)**: Memfilter paket respons UDP `KASIRTOKO_HERE` berdasarkan `expectedServerId`.
  4. **UI `409 SESSION_LIMIT_EXCEEDED`, Diagnostik Jaringan & Responsive Overflow**: Verifikasi `PinLoginScreen`, `ConnectionAndReceiptsScreen`, dan `StaffPosScreen` pada viewport sempit (`320x640`) tanpa overflow, serta cakupan `global_responsive_overflow_test.dart` & `scanner_and_pos_redesign_test.dart`.

*Catatan batasan lingkungan uji otomatis:* Pengujian host dijalankan dengan `sqflite_common_ffi` serta test double untuk Android Keystore/SecretVault (`InMemoryPepperProvider`, `SoftwareAesGcmSecretVault`, 10.000–50.000 iterasi KDF pada suite fungsional dan benchmark 600.000 iterasi sebesar `5115 ms` pada runtime host).

## 2. Verifikasi Build Rilis Bertanda Tangan Permanen (RSA-4096)

Semua artifak rilis dibangun dengan `--release --split-per-abi --target-platform android-arm,android-arm64 --split-debug-info` menggunakan keystore permanen RSA-4096 (bukan debug key) dan diverifikasi via `apksigner` serta `aapt2`:

| Aplikasi | Artifak | Ukuran (Bytes) | `versionCode` | `versionName` | File SHA-256 | Signer SHA-256 (`apksigner` v2) |
|---|---|---:|---:|---|---|---|
| KasirToko Admin | `KasirToko-Admin-v2.4.0-arm64-v8a-release.apk` | 60.143.748 | 2007 | 2.4.0 | `1d42ecec1e6836b56887bf52d9d7ac6c5c53756edfb822c2443d3a2fff0eb8c8` | `a946a3d88a0dfbaee56cdd13d860fff765aeee540a6bf2a83d340df051934241` |
| KasirToko Admin | `KasirToko-Admin-v2.4.0-armeabi-v7a-release.apk` | 58.841.104 | 1007 | 2.4.0 | `0fb2ea8886f8aec3fc90889b9672c10f1de6f45afc56f401488086124d8a8365` | `a946a3d88a0dfbaee56cdd13d860fff765aeee540a6bf2a83d340df051934241` |
| KasirToko Staff | `KasirToko-Staff-v1.1.0-arm64-v8a-release.apk` | 49.942.953 | 2005 | 1.1.0 | `fbbe3e94bd0e0063e880279dda9f5da20670fb2f06f41575e44db20a1947f92f` | `e431477a7ae04cf086f099ba7da53dcf0bb65f987cbc76dac0a778c840606232` |
| KasirToko Staff | `KasirToko-Staff-v1.1.0-armeabi-v7a-release.apk` | 48.904.163 | 1005 | 1.1.0 | `ad2e313b1702e755558ba4a9b4f759618d8231721f263fdb59638fc55f801e91` | `e431477a7ae04cf086f099ba7da53dcf0bb65f987cbc76dac0a778c840606232` |

## 3. Status Perangkat Fisik & Checklist Uji Lapangan Nyata

- **Status ADB pada saat build**: `adb devices -l` melaporkan **`0` perangkat Android fisik terhubung**. Karena tidak ada HP Android fisik yang tersambung ke mesin build, pengujian perilaku Hardware/OS Android nyata di bawah ini wajib divalidasi pada perangkat fisik toko sebelum go-live:

### Checklist Uji Perangkat Fisik Toko (Wajib Jalankan Sebelum Operasional Penuh)
- [ ] **Upgrade In-Place Data Lama**: Pasang `KasirToko-Admin-v2.4.0` di atas versi v2.3.1 yang sudah berisi produk, karyawan, shift, dan transaksi; pastikan migrasi v6 -> v7 selesai mulus dan seluruh data tampil utuh serta `Server ID` muncul di **Server LAN & Terminal Staff**.
- [ ] **Foreground Service & Optimasi Baterai**: Nyalakan server Admin, nonaktifkan pengoptimalan baterai untuk KasirToko Admin sesuai instruksi OEM, kunci layar HP server selama 30 menit, lalu lakukan transaksi dari HP Staff untuk memastikan respons cepat dan antrean printer Bluetooth/LAN berjalan.
- [ ] **3 Kasir pada 3 HP Pribadi + Print Struk**: Uji transaksi berbarengan pada mode `SHARED_DRAWER` lalu `INDIVIDUAL_DRAWER` dan pastikan struk tercetak bersih tanpa dobel/kehilangan job.
- [ ] **1 Akun Kasir di 2 HP (Tolak 409)**: Login `Kasir 1` di HP A, coba login `Kasir 1` yang sama di HP B -> pastikan HP B menampilkan pesan batas sesi tercapai (`409 SESSION_LIMIT_EXCEEDED`) dan HP A tetap aktif tanpa ter-logout.
- [ ] **Cabut Sesi & Nonaktifkan Akun**: Dari Admin, cabut sesi HP Staff saat `StaffPosScreen` terbuka -> pastikan HP Staff otomatis keluar ke login tanpa menutup shift bersama `SHARED_DRAWER`.
- [ ] **Failover Router -> Hotspot Cadangan**: Matikan Wi-Fi router toko, nyalakan Hotspot HP Admin sesuai IP cadangan, sambungkan Wi-Fi HP Staff ke Hotspot HP Admin -> pastikan HP Staff terhubung otomatis (`Hotspot Cadangan`), keranjang belanja utuh, dan transaksi langsung tersimpan ke Admin tanpa pairing ulang.
- [ ] **Backup `.ktbak` SAF + Restore di HP Pengganti**: Atur **Passphrase Pemulihan Lintas Perangkat** dan folder SAF di `BackupManagementScreen`, jalankan **Backup Sekarang**, pindahkan file `.ktbak` ke HP Admin cadangan, jalankan **Pulihkan File** menggunakan passphrase -> pastikan seluruh katalog, user, dan riwayat transaksi pulih dengan `PRAGMA integrity_check == 'ok'`.
