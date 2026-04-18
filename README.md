# 📸 Logbook App & Pemrosesan Citra Digital (PCD)

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)

Repository untuk proyek praktikum/ETS **Pemrosesan Citra Digital**. Aplikasi lintas platform berbasi **Flutter** untuk mencatat logbook, yang dilengkapi fitur pengolahan citra (*Image Processing*) secara *native* pada level matriks array *pixel*, **tanpa menggunakan library instan seperti OpenCV**.

---

## ✨ Fitur Utama

- 📝 **Manajemen Logbook (CRUD)**
  Mencatat kegiatan harian yang terintegrasi dengan penyimpanan database.
- 🖼️ **Pemrosesan Titik (Point Processing)**
  - Grayscale & Biner/B&W.
  - Inversi Warna (Negative Image).
  - Pengaturan Brightness & Contrast (Secara Linear).
  - **Histogram Equalization** (Meratakan spektrum warna via fungsi CDF probabilitas).
  - **Histogram Specification**.
  - Penambahan Salt & Pepper Noise.
- 🎛️ **Filter Spasial (Spatial/Frequency Filtering)**
  Bekerja dengan algoritma kernel matriks konvolusi 2-Dimensi:
  - Low-pass Filter (Blur/Pelembutan).
  - High-pass Filter (Penajaman Detail).
  - Band-pass Filter.
  - Edge Detection (Deteksi Tepi).
- 🚀 **Isolates (Background Optimization)**
  Karena komputasi array memanipulasi jutaan piksel sekaligus, beban berat pemrosesan citra diarahkan ke *background thread* melalui `compute()` Dart, memastikan UI aplikasi tidak mengalami *freeze* atau *lag*.

## 📂 Struktur Proyek

Folder *logic* krusial terkait citra digital terletak di:
`logbook_app_069/lib/features/vision/`
- `pcd_processing_page.dart`: Berisi algoritma konversi *pixel*, kalkulasi histogram, matriks konvolusi, serta sistem *thread Isolate*.
- `vision_controller.dart`: Menghandle routing dan penyimpanan permanen (*Application Documents Directory*) agar aman dari restriksi sistem Android (`content://` URI bug).

## 🚀 Cara Menjalankan Aplikasi Lokal

Pastikan komputermu sudah terinstal **Flutter SDK**, **Dart**, serta **Android Studio/VS Code** dengan emulator yang aktif.

1. **Kloning Repositori**
   ```bash
   git clone https://github.com/alatteee/PY4AI_2C_D3_2024_Modul6_069.git
   cd PY4AI_2C_D3_2024_Modul6_069/logbook_app_069

2. **Unduh Dependencies**
   ```bash
   flutter pub get
3. **Jalankan Aplikasi**
   ```
   flutter run
