# Logbook App 069 (PCD Integration)

Aplikasi Flutter untuk mencatat logbook sekaligus memproses citra digital (PCD) menggunakan algoritma mandiri level pixel, tanpa menggunakan *library* OpenCV.

## Prasyarat (Prerequisites)
Sebelum menjalankan proyek ini, pastikan sistem Anda sudah terinstal:
- **Flutter SDK** (versi stabil terbaru)
- **Dart SDK**
- **Android Studio** atau **VS Code** (dengan ekstensi Flutter terpasang)
- Emulator Android atau Device Fisik yang terhubung.

## Cara Instalasi dan Menjalankan Aplikasi
Berikut adalah langkah-langkah untuk menjalankan aplikasi di komputer Anda:

1. **Buka folder proyek**
   Buka terminal atau command prompt, lalu arahkan *directory* aktif ke folder proyek ini (ekstrak file .zip terlebih dahulu jika masih terkompresi).
   \\\ash
   cd logbook_app_069
   \\\

2. **Unduh Dependencies**
   Jalankan perintah berikut untuk mengunduh semua pustaka (*packages*) yang diperlukan oleh proyek aplikasi ini:
   \\\ash
   flutter pub get
   \\\

3. **Menjalankan Aplikasi**
   Pastikan emulator sudah berjalan atau *device* sudah terhubung, lalu ketikkan:
   \\\ash
   flutter run
   \\\
   Pilih perangkat target Anda (misalnya Android/Windows) ketika muncul pilihan.

## Catatan Penting
- Diperlukan koneksi internet saat menjalankan lutter pub get.
- Proses kompilasi awal mungkin membutuhkan waktu beberapa menit untuk mengunduh Gradle (jika dijalankan spesifik di Android).
- Aplikasi ini memanfaatkan sistem *Isolates* (Background Thread) milik Flutter untuk pemrosesan Array Matematika Matrix warna, jadi proses efek gambar tidak akan membuat HP lag/kartu (*freeze*).
