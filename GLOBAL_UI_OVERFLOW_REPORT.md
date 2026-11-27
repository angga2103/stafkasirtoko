# Global UI Overflow Audit & Responsive Layout Report — KasirToko Staff (v1.0.3+4)

## 1. Ringkasan Eksekutif

Audit tata letak responsif global telah diselesaikan untuk **KasirToko Staff** (`v1.0.3+4`) bersama aplikasi **KasirToko Admin**. Seluruh potensi `RenderFlex overflow`, dropdown `Laci Kas yang Ditugaskan` yang sempat mengalami overflow pada layar sempit, keypad PIN lebar tetap, baris `AlertDialog` tanpa batas ukuran, bottom sheet non-scrollable, kartu katalog tinggi tetap, dan benturan keyboard lunak (`viewInsets.bottom`) telah diperbaiki dan diverifikasi otomatis serta visual.

## 2. Perbaikan Kasus Terlapor & Audit Per Layar

| File Layar / Dialog | Akar Masalah | Perbaikan Terverifikasi |
|---|---|---|
| `lib/ui/screens/staff_shift_screen.dart` (**Reported #2**: `Shift & Laci Kas Terminal` — `OVERFLOWED BY 9.4 PIXELS`) | `DropdownButtonFormField<int>` `Laci Kas yang Ditugaskan` tidak memakai `isExpanded: true`, label item panjang melampaui lebar kontainer pada `320px`/`360px`, dan baris status shift tidak memakai `Expanded`. | Menambahkan `isExpanded: true` dan `maxLines: 1, overflow: TextOverflow.ellipsis` pada item laci kasir, membungkus teks header `Shift Aktif #...` dan `Belum Ada Shift Terbuka` dengan `Expanded`, serta menambahkan `SafeArea` + padding `viewInsets` keyboard. |
| `lib/ui/screens/pin_login_screen.dart` | Tombol keypad PIN berlebar tetap (`72px`), 6 indikator titik PIN tanpa skala adaptif, dropdown `Pilih Akun Kasir` tanpa elipsis, dan tombol AppBar `Unpair` padat pada `<360px`. | Mengganti keypad ke `ConstrainedBox(maxWidth: 280)` dengan `Expanded`, membungkus titik PIN ke `FittedBox(scaleDown)`, menambahkan `isExpanded: true` + `ellipsis` pada dropdown kasir, serta merapikan `AppBar` + padding keyboard. |
| `lib/ui/screens/pairing_screen.dart` | Teks pembatas `'atau input manual'` memicu overflow 23px pada `320x640` skala `1.2x` dan input IP/Port berdampingan terlalu sempit pada skala font besar. | Membungkus label pembatas dengan `Flexible`, menumpuk input IP/Port via `LayoutBuilder` pada layar ultra-sempit + skala teks tinggi, serta menambahkan `SafeArea` + padding keyboard. |
| `lib/ui/screens/connection_and_receipts_screen.dart` | Teks `'30 Struk Terbaru Terminal'` tanpa `Expanded` dan dialog laci kasir manual tanpa batas/scroll. | Membungkus judul dengan `Expanded` dan konten `AlertDialog` dalam `ConstrainedBox(maxWidth: 420)` + `SingleChildScrollView`. |
| `lib/ui/screens/staff_pos_screen.dart` | Logo AppBar memicu overflow `5.5px` pada `<350px` dengan keyboard terbuka, pemilih unit & promo belum scrollable sepenuhnya, dan kartu katalog / chip kategori memakai ukuran kaku. | Mengukur `textScale` adaptif (`1.0..1.8`), menskalakan chip kategori dan `mainAxisExtent` kartu produk, menjadikan dialog unit/promo & `BottomSheet` (`isScrollControlled: true`, `maxHeight: 0.85`) scrollable, menyembunyikan logo AppBar pada `<350px`, dan membungkus `TOTAL` dalam `Expanded` + `FittedBox`. |
| `lib/ui/dialogs/staff_payment_dialog.dart` | Baris ringkasan & kembalian dan 4 tombol metode bayar sejajar sempit pada layar `320px` dengan skala `1.5x`. | Membungkus baris `spaceBetween` dengan `Expanded` + `Flexible`, menambahkan elipsis item walk-in, dan mengalihkan 4 tombol metode bayar ke grid `2x2` via `LayoutBuilder` saat lebar sel `< 64 * textScale`. |
| `lib/ui/dialogs/staff_receipt_dialog.dart` | `SizedBox(width: 390)` melampaui layar `320px`/`360px` dan memicu masalah intrinsik `AlertDialog` dengan `QrImageView`. | Menghitung lebar berbatas `(MediaQuery.sizeOf(context).width - 80).clamp(200.0, 400.0)` dan membungkus baris `_kv` dengan `Expanded` + `Flexible`. |

## 3. Matriks & Hasil Verifikasi Otomatis

Suite responsif baru di `test/global_responsive_overflow_test.dart` menguji **8 ukuran layar** (`320x640`, `360x640`, `360x800`, `390x844`, `412x915`, `480x960`, `800x1280`, `1280x800`), **3 skala font** (`1.0x`, `1.2x`, `1.5x`), **inset keyboard aktif (`bottom: 260`)**, nama kasir/laci/produk panjang, serta pemilihan interaktif dropdown **Laci Kas yang Ditugaskan** dan pergantian kasir di `PinLoginScreen`.

- **`flutter analyze --no-pub` (`v1.0.3+4`):** **No issues found! (0 issues)**
- **`flutter test --no-pub -j 1` (`v1.0.3+4`):** **27 passed, 0 failed** (mencakup `global_responsive_overflow_test.dart`, `scanner_and_pos_redesign_test.dart`, `reconciliation_and_tls_rotation_test.dart`, dan `widget_test.dart`).
- **Verifikasi Screenshot Visual (`docs/screenshots/overflow_audit/`):**
  - `staff_shift_320x640_fs15.png`
  - `staff_pin_login_320x640_fs15.png`
  - `staff_payment_dialog_320x640_fs15.png`

## 4. Release Split APK Tersertifikasi (`v1.0.3+4`)

Dibangun ulang dengan keystore rilis permanen (`kasirtoko-staff-release.jks`) dan diverifikasi menggunakan `apksigner verify --print-certs`:

- Sertifikat Penanda Tangan: `CN=KasirToko Staff Release, OU=POS Engineering, O=KasirToko, L=Indonesia, C=ID`
- Fingerprint Sertifikat (SHA-256): `e431477a7ae04cf086f099ba7da53dcf0bb65f987cbc76dac0a778c840606232`
- `KasirToko-Staff-v1.0.3-arm64-v8a-release.apk`: `49.913.517 bytes` (SHA-256: `a5d285a097a690e1fb1af9b14a1e40157aeb5870101f2592d8557b4c01f17377`)
- `KasirToko-Staff-v1.0.3-armeabi-v7a-release.apk`: `48.874.047 bytes` (SHA-256: `afa9b10655628619b2d44b74bb1a25efd3071d322b850504df722a1c3e775708`)

## 5. Catatan Pengujian Perangkat Fisik

Pada workstation pengujian ini (`adb devices`), tidak terdapat perangkat Android fisik yang terhubung melalui USB/ADB. Verifikasi penuh dijalankan melalui seluruh test matrix otomatis Flutter dan inspeksi visual render PNG Roboto (`320x640` hingga `1280x800`, skala font `1.0x`–`1.5x`). Instalasi dan uji manual langsung di perangkat fisik dapat dilakukan dengan APK rilis bertanda tangan di atas.
