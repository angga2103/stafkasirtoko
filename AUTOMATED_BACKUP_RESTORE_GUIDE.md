# Panduan Backup Otomatis Terenkripsi & Pemulihan Database KasirToko

Dokumen ini menjelaskan format backup terenkripsi `.ktbak`, jadwal otomatis, lokasi penyimpanan terpisah, tes pemulihan otomatis, dan prosedur pemulihan database saat HP Admin rusak atau diganti.

## 1. Arsitektur Backup (`BackupService` & `BackupProvider`)

- **Snapshot Konsisten Tanpa Menghentikan Transaksi:**
  - `BackupService.createEncryptedBackup()` mengeksekusi SQLite `VACUUM INTO '<tempSnapshotPath>'` (dengan fallback WAL checkpoint aman jika diperlukan) sehingga snapshot atomik konsisten dengan transaksi checkout LAN yang sedang berjalan.
- **Format Enkripsi `.ktbak` (`KTBAK001`):**
  - Payload database dienkripsi **AES-256-GCM** menggunakan Data Encryption Key (DEK) acak 256-bit per arsip.
  - DEK dibungkus dua cara:
    1. **Vault KEK perangkat** (`SecretVault`, didukung Android Keystore di perangkat asli).
    2. **Passphrase Pemulihan Lintas Perangkat (Opsional sangat disarankan)**: diturunkan via PBKDF2-HMAC-SHA256 (`SecurityHelper.deriveKeyBytes`) agar file `.ktbak` tetap dapat dipulihkan pada **HP Admin baru/pengganti** meski Keystore HP lama hilang.
  - Setiap arsip menyimpan checksum SHA-256 untuk payload plaintext (`plain_sha256`) dan arsip terenkripsi (`encrypted_sha256`).

## 2. Verifikasi Tes Restore Otomatis (`verifyBackupArtifact`)

Setiap backup yang baru dibuat langsung diuji secara otomatis:
1. Memverifikasi SHA-256 file terenkripsi (bila referensi tersedia).
2. Mendekripsi amplop `.ktbak` dan menguji autentikasi tag GCM serta `plain_sha256`.
3. Menulis database hasil dekripsi ke file uji sementara dan membukanya read-only.
4. Menjalankan **`PRAGMA integrity_check`** (harus `ok`), **`PRAGMA foreign_key_check`** (dicatat di ringkasan diagnostik), dan memeriksa keberadaan tabel inti (`users`, `products`, `transactions`, `shifts`) beserta jumlah barisnya.
5. Hanya jika semua tahap berhasil barulah status artifak di tabel `backup_artifacts` ditandai `verified` (`verified_restore_ok = 1`).

## 3. Jadwal Otomatis & Peringatan Operasional

Tabel `backup_jobs` menyimpan dua jadwal standar:
- **`hourly_snapshot`**: Berjalan otomatis setiap **60 menit** selama aplikasi Admin aktif/dievaluasi oleh `BackupProvider`.
- **`nightly_full`**: Berjalan otomatis 1x setiap malam (default **23:30**).
- **Guard Penyimpanan Rendah (`minRequiredFreeSpaceBytes = 50 MB`):** Menggunakan Android `StatFs` via `MainActivity` channel `com.kasirtoko.app/backup`. Jika ruang kosong < 50 MB, backup ditolak bersih agar tidak menghasilkan arsip rusak, mencatat audit log `backup_gagal`, dan menampilkan peringatan di Home Admin serta `BackupManagementScreen`.

## 4. Lokasi Penyimpanan Terpisah & Konektor Cloud

- Folder utama default dipisahkan dari direktori live DB (`kasirtoko.db`) ke direktori dukungan/eksternal khusus backup (`getExternalBackupDir` Android atau `kasirtoko_backups`).
- Mendukung salinan sekunder opsional dan picker **Android Storage Access Framework (`SAF`)** (`pickBackupFolderTree` & `copyBackupToTreeUri` untuk folder lokal/SD card/penyimpanan penyedia cloud sistem Android).
- **`UnconfiguredBackupCloudConnector`**: Menyatakan secara jujur jika konektor cloud langsung belum dikonfigurasi/diotorisasi (tidak pernah memalsukan status "tersinkron ke cloud" ketika upload tidak terjadi).

## 5. Prosedur Pemulihan Database (`restoreFromFilePath`)

1. Buka menu **Backup Data** (`BackupManagementScreen`) atau **Pengaturan Toko**.
2. Konfirmasi dialog pemulihan (sistem **selalu membuat pre-restore safety snapshot** dari data saat ini sebelum menimpa database aktif dan menyimpan riwayatnya agar Owner tetap punya titik balik).
3. Validasi penuh `.ktbak` (dekripsi + SHA-256 + `PRAGMA integrity_check == 'ok'`) dijalankan terlebih dahulu. Jika file korup atau passphrase salah, database aktif **tidak disentuh sama sekali**.
4. Saat valid, `DatabaseHelper.instance.resetConnection()` menutup koneksi aktif, menghapus sisa file `-wal`/`-shm` lama, menyalin database bersih, dan membuka kembali `DatabaseHelper.instance.database` (otomatis memigrasikan versi lama jika ada).
5. **Pemulihan di HP Pengganti:** Pasang KasirToko Admin, pilih file `.ktbak` dari folder cadangan/SAF/eksternal, lalu masukkan **Passphrase Pemulihan Lintas Perangkat** yang telah dikonfigurasi sebelumnya.
