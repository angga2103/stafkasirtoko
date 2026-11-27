# UPDATE_COMPATIBILITY.md — Panduan Kompatibilitas Update Tanpa Uninstall

Dokumen ini memastikan setiap rilis **KasirToko Admin** dan **KasirToko Staff** di Android dapat di-update langsung (**in-place upgrade**) tanpa menghapus aplikasi maupun kehilangan data transaksi, produk, atau kredensial.

---

## 1. Empat Syarat Mutlak Update Tanpa Uninstall di Android

Android Package Manager hanya mengizinkan instalasi versi baru menimpa versi terpasang jika seluruh syarat berikut terpenuhi:
1. **`applicationId` identik:**
   - KasirToko Admin: `com.kasirtoko.app.kasirtoko` (tidak berubah sejak v1.0.0–v2.3.0).
   - KasirToko Staff: `com.kasirtoko.app.stafkasirtoko`.
2. **Sertifikat signing SHA-256 identik:**
   - Admin permanen: `A9:46:A3:D8:8A:0D:FB:AE:E5:6C:DD:13:D8:60:FF:F7:65:AE:EE:54:0A:6B:F2:A8:3D:34:0D:F0:51:93:42:41`
   - Staff permanen: `E4:31:47:7A:7A:E0:4C:F0:86:F0:99:BA:7D:A5:3D:CF:0B:B6:5F:98:7C:BC:76:DA:C0:A7:78:C8:40:60:62:32`
3. **`versionCode` meningkat (`new > old`):**
   - **Varian ARM Universal:** Admin `v2.3.0+5` (`versionCode=5`, rilis berikutnya `>= 6`); Staff `v1.0.1+2` (`versionCode=2`, berikutnya `>= 3`).
   - **Varian Split-Per-ABI (`--split-per-abi`):** Flutter mengalokasikan prefix ABI pada `versionCode`:
     - `armeabi-v7a`: Admin `1005` (`>= 1006` berikutnya), Staff `1002` (`>= 1003` berikutnya).
     - `arm64-v8a`: Admin `2005` (`>= 2006` berikutnya), Staff `2002` (`>= 2003` berikutnya).
   - **Catatan Penting Split vs Universal:** Upgrade dari ARM Universal (`5`/`2`) ke Split-Per-ABI (`1005`/`2005` atau `1002`/`2002`) berjalan normal tanpa uninstall karena `versionCode` lebih tinggi. Namun **setelah perangkat memakai APK Split-Per-ABI**, update selanjutnya di perangkat tersebut **wajib** memakai APK Split ABI yang sama (atau build dengan `versionCode > 2005`), karena memasang universal dengan `versionCode` lebih kecil akan ditolak Android (`INSTALL_FAILED_VERSION_DOWNGRADE`).
4. **Migrasi skema SQLite non-destruktif (`onUpgrade`):**
   - Admin v6 menjaga seluruh data lama v1–v5 dengan pra-backup terverifikasi (`_pre_v5_backup.db`, `_pre_v6_backup.db`) serta backfill kolom tanpa reset database.
   - Staff v1 menggunakan `staff_terminal.db` cache-only dan menyimpan kredensial terenkripsi di Android Keystore + SharedPreferences privat (`allowBackup="false"`).

---

## 2. Audit Rilis Lama & Konsekuensi Migrasi Satu Kali (`v2.0.0 – v2.2.0`)

Hasil audit terhadap riwayat commit (`327b1ab`, `a32efef`, `fbf7218`) dan workflow [`build.yml`](../../kasirtoko/.github/workflows/build.yml) menunjukkan fakta penting:
- Rilis KasirToko **v2.0.0, v2.1.0, dan v2.2.0** sebelumnya dibangun dengan `signingConfig = signingConfigs.getByName("debug")` pada runner ephemeral GitHub Actions.
- **Konsekuensi Teknis Android:** Sertifikat debug ephemeral runner **berbeda** dengan keystore permanen RSA-4096 yang sekarang digunakan pada **KasirToko Admin v2.3.0+5** (dan debug APK Staff `v1.0.0+1` juga berbeda dengan sertifikat permanen **KasirToko Staff v1.0.1+2**). Android **secara teknis menolak** update langsung antar sertifikat berbeda (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

### Jalur Migrasi Paling Aman (Sekali Seumur Hidup ke Permanent Signing)

**Untuk Perangkat Admin yang Sudah Memakai v2.0.0–v2.2.0:**
1. Buka aplikasi KasirToko Admin lama -> masuk menu **Pengaturan Toko -> Backup & Restore Database** -> ekspor file backup `.db` ke folder Documents / penyimpanan eksternal aman.
2. Pastikan tidak ada shift atau transaksi yang tertahan belum disimpan.
3. Uninstall versi debug lama dari perangkat Android.
4. Pasang **`KasirToko-Admin-v2.3.0-arm64-v8a-release.apk`** (atau `armeabi-v7a` / `arm-universal`) yang ditandatangani dengan keystore permanen.
5. Buka aplikasi -> lakukan **Restore Database** dari file backup pada langkah 1. Migrasi skema non-destruktif v4/v5 -> v6 berjalan otomatis menjaga seluruh data lama.
6. Jalankan **Server LAN** dan lakukan pairing ulang ke terminal Staff.

**Untuk Perangkat Staff yang Pernah Memasang Debug APK `1.0.0+1`:**
1. Pastikan keranjang belanja di Staff kosong / semua transaksi selesai.
2. Uninstall versi debug `1.0.0+1`.
3. Pasang **`KasirToko-Staff-v1.0.1-arm64-v8a-release.apk`** (atau `armeabi-v7a` / `arm-universal`).
4. Scan QR Pairing dari KasirToko Admin `v2.3.0`.
