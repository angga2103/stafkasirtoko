# ANDROID_SIGNING_GUIDE.md — Panduan Permanent Android Release Signing

Dokumen ini menjelaskan konfigurasi tanda tangan permanen (*permanent release signing*) untuk **KasirToko Admin** dan **KasirToko Staff**.

> [!CAUTION]
> **DILARANG KERAS** menuliskan password keystore, key password, alias secret di luar konfigurasi resmi, atau file `.jks` / `.b64` / `key.properties` ke dalam repository Git, dokumen, maupun artifact build publik.

---

## 1. Desain Arsitektur Signing
Kedua aplikasi menggunakan **keystore permanen terpisah** agar risiko kompromi satu aplikasi tidak memaksa rotasi sertifikat aplikasi lainnya:

| Aplikasi | `applicationId` | File Keystore (Lokal Offline) | Key Alias | Algoritma & Masa Berlaku |
| :--- | :--- | :--- | :--- | :--- |
| **KasirToko Admin** | `com.kasirtoko.app.kasirtoko` | `kasirtoko-admin-release.jks` | `kasirtoko_admin` | PKCS12, RSA **4096-bit**, `SHA256withRSA`, valid **10.950 hari** (~30 tahun, hingga 19 Nov 2056) |
| **KasirToko Staff** | `com.kasirtoko.app.stafkasirtoko` | `kasirtoko-staff-release.jks` | `kasirtoko_staff` | PKCS12, RSA **4096-bit**, `SHA256withRSA`, valid **10.950 hari** (~30 tahun, hingga 19 Nov 2056) |

---

## 2. Fingerprint Sertifikat Publik Resmi

Gunakan fingerprint publik berikut untuk memverifikasi integritas setiap APK release resmi (`apksigner verify --verbose --print-certs`):

### KasirToko Admin (`kasirtoko_admin`)
- **Subject:** `CN=KasirToko Admin Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`
- **SHA-256:** `A9:46:A3:D8:8A:0D:FB:AE:E5:6C:DD:13:D8:60:FF:F7:65:AE:EE:54:0A:6B:F2:A8:3D:34:0D:F0:51:93:42:41`
- **SHA-1:** `2C:38:7E:2C:86:0A:A3:B4:B6:BE:00:04:A6:E5:E9:60:ED:B7:C4:49`

### KasirToko Staff (`kasirtoko_staff`)
- **Subject:** `CN=KasirToko Staff Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`
- **SHA-256:** `E4:31:47:7A:7A:E0:4C:F0:86:F0:99:BA:7D:A5:3D:CF:0B:B6:5F:98:7C:BC:76:DA:C0:A7:78:C8:40:60:62:32`
- **SHA-1:** `DE:37:F6:71:98:5A:DD:65:EC:BC:D4:F6:97:34:22:14:A9:3A:AC:06`

---

## 3. Penegakan Keamanan di Gradle
Pada kedua file [`android/app/build.gradle.kts`](../android/app/build.gradle.kts):
- Build `--debug` tetap memakai `signingConfigs.getByName("debug")` untuk pengembangan lokal dan CI.
- Build `--release` **wajib** menemukan konfigurasi signing permanen (via `android/key.properties` yang di-gitignore atau environment variables `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`).
- Apabila perintah Gradle release dijalankan tanpa signing permanen, build **langsung gagal dengan pesan error eksplisit** agar tidak pernah ada APK release unsigned atau debug-signed yang beredar.

---

## 4. Konfigurasi GitHub Repository Secrets (Langkah Pemilik)

Setiap repository (`angga2103/kasirtoko` dan `angga2103/stafkasirtoko`) harus diisi 4 secrets berikut pada menu **Settings -> Secrets and variables -> Actions -> New repository secret**:

| Nama Secret | Nilai Sumber (dari folder offline `C:\Users\Toshiba\KasirToko-Signing\`) |
| :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | Isi utuh file `kasirtoko-admin-release.jks.b64` (repo Admin) atau `kasirtoko-staff-release.jks.b64` (repo Staff) |
| `ANDROID_KEYSTORE_PASSWORD` | Store password dari catatan offline `SIGNING_RECOVERY.txt` untuk aplikasi terkait |
| `ANDROID_KEY_ALIAS` | `kasirtoko_admin` (Admin) atau `kasirtoko_staff` (Staff) |
| `ANDROID_KEY_PASSWORD` | Key password dari catatan offline `SIGNING_RECOVERY.txt` untuk aplikasi terkait (berformat PKCS12, bernilai sama dengan `ANDROID_KEYSTORE_PASSWORD`) |

### Konversi Keystore ke Base64 (jika membuat ulang dari file `.jks`)
- **PowerShell (Windows):**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\Toshiba\KasirToko-Signing\kasirtoko-admin-release.jks")) | Set-Clipboard
  ```
- **Linux / macOS:**
  ```bash
  base64 -w 0 kasirtoko-admin-release.jks
  ```

---

## 5. Backup Terenkripsi & Pemulihan Signing Key

File backup terenkripsi disimpan secara offline di luar repository Git pada:
`C:\Users\Toshiba\KasirToko-Signing\kasirtoko-signing-backup.aesgcm`

Format enkripsi: Header `KTK1` (4 byte) + Salt acak (16 byte) + Nonce GCM (12 byte) + Ciphertext ZIP berisi kedua `.jks` dan metadata JSON, dienkripsi dengan **PBKDF2-HMAC-SHA256 (600.000 iterasi)** + **AES-256-GCM** (AAD `kasirtoko-signing-backup-v1`).

**Prosedur Pemulihan Offline:**
1. Salin `kasirtoko-signing-backup.aesgcm` ke minimal dua media terpisah (cloud vault pribadi terenkripsi & flashdisk offline).
2. Dekripsi dengan Python (`cryptography`):
   ```python
   from pathlib import Path
   from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
   from cryptography.hazmat.primitives import hashes
   from cryptography.hazmat.primitives.ciphers.aead import AESGCM

   blob = Path("kasirtoko-signing-backup.aesgcm").read_bytes()
   assert blob[:4] == b"KTK1"
   salt, nonce, ct = blob[4:20], blob[20:32], blob[32:]
   passphrase = input("Backup Passphrase: ").encode("utf-8")
   key = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=600000).derive(passphrase)
   Path("restored-keystores.zip").write_bytes(AESGCM(key).decrypt(nonce, ct, b"kasirtoko-signing-backup-v1"))
   ```
3. Ekstrak `restored-keystores.zip`, verifikasi `keytool -list -v`, lalu hapus zip plaintext setelah selesai.
