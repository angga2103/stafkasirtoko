# PRINTER_SETUP_GUIDE.md — Panduan Printer Terpusat & Pengaturan Laci Kas (RJ11)

## 1. Arsitektur Printer Terpusat
POS Staff **tidak perlu** terhubung langsung ke printer. Seluruh permintaan cetak dari terminal Staff dikirim ke POS Admin (`POST /api/v1/transactions` atau `POST /api/v1/print/receipt`), masuk ke antrean serial FIFO (`print_jobs` per printer di `PrintQueueWorker`), dan dicetak oleh printer yang terpasang pada perangkat **POS Admin**.

## 2. Jenis Printer yang Didukung oleh Server Headless LAN
| Tipe Koneksi di POS Admin | Dukungan Cetak Otomatis Terminal Staff | Catatan Teknis |
| :--- | :--- | :--- |
| **Bluetooth Thermal (SPP)** | Didukung (`58mm` / `80mm`, ESC/POS) | Pastikan printer sudah dipairing di Android Settings & izin Bluetooth Android 12+ aktif |
| **USB OTG Thermal / Dot Matrix** | Didukung (ESC/POS / ESC/P) | Izin USB Host di perangkat Admin harus diberikan sebelum terminal mengirim job |
| **LAN / Wi-Fi TCP (Port 9100)** | Didukung (ESC/POS / ESC/P) | Printer terhubung ke router Wi-Fi yang sama dengan POS Admin |
| **Android Print Service (`system` PDF)** | **Tidak Didukung Headless** (`PRINTER_NOT_HEADLESS`) | Android Print Dialog membutuhkan interaksi layar pengguna; gagal bersih pada job background Staff |

## 3. Logo Toko & QR Invoice pada Struk
- Logo toko (`logo_path`) di-render ke raster bitmap ESC/POS (`GS v 0`) di sisi Admin (`EscPosGenerator`) sesuai lebar kertas `58mm` (32 char) atau `80mm` (48 char).
- QR Code nota berisi `TRX|<INVOICE>|<TOTAL>` agar mudah dipindai kembali saat retur/void di POS Admin.

## 4. Aturan Ketat Pembukaan Laci Kas (RJ11 Cash Drawer)
Server POS Admin menegakkan **6 aturan anti-penyalahgunaan cash drawer**:
1. **Tunai Saja:** Pulse otomatis RJ11 (`0x1B 0x70 0x00 0x19 0xFA`) **hanya** diizinkan untuk `payment_method == 'tunai'`.
2. **Non-Tunai Terkunci:** Transaksi `qris`, `transfer`, `kasbon`, dan `saldo_kredit` tidak pernah memicu pembukaan laci.
3. **Kontrol Per Terminal:** Toggle `allow_auto_open_drawer` pada terminal harus diaktifkan oleh Admin (`MultiDeviceServerScreen`).
4. **Kontrol Manual Ganda:** Pembukaan laci manual (`POST /api/v1/printers/open-drawer`) membutuhkan:
   - `allow_manual_open_drawer == true` pada terminal,
   - `user.hasPermission(AppPermissions.openCashDrawer) == true`,
   - Alasan audit tidak kosong -> tercatat di `audit_logs` (`action_type: 'buka_laci'`).
5. **Satu Kali Tembak (`drawer_pulse_sent`):** Pulse pembukaan laci dilindungi klaim atomik SQLite (`WHERE id = ? AND drawer_pulse_sent = 0`) sesudah transaksi checkout sukses commit. **Retry cetak gagal atau cetak multi-salinan tidak akan pernah memicu pulse kedua.**
6. **Reprint Dilarang Membuka Laci:** Seluruh permintaan dengan `is_reprint: true` mengunci pulse RJ11 (`allowDrawerPulse = false`) dan mencatat `audit_logs` (`cetak_ulang_struk`).

## 5. Kejujuran Status Cetak (`submitted` vs Fisik Kertas)
Android OS / Bluetooth SPP / USB / TCP Socket hanya melaporkan bahwa byte ESC/POS telah **dikirim ke buffer driver printer** (`submitted`). Status tersebut **tidak membuktikan** kertas fisik tidak habis atau tidak tersangkut tanpa sensor dua arah khusus pada model printer tertentu.
