import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'damage_painter.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

class VisionController extends ChangeNotifier with WidgetsBindingObserver {
  CameraController? controller;
  bool isInitialized = false;
  bool isProcessing = false;
  bool isOverlayVisible = true;
  bool isFlashOn = false;
  bool isPcdPanelVisible = false;
  bool isGrayscale = false;
  bool isHistogramVisible = false;
  double contrast = 1.0;
  double brightness = 0.0;
  double blurSigma = 0.0;

  bool isSaltPepperOn = false;
  double saltPepperProb = 0.0;
  bool isMedianDenoiseOn = false;
  ui.Image? pcdImage;

  bool isCaptured = false;
  CameraImage? _lastFrame;
  String selectedFilter = 'Original';
  ui.Image? capturedRgbImage;
  final GlobalKey previewKey = GlobalKey();

  List<int> lumaHistogram16 = List<int>.filled(16, 0);
  double lumaAvg = 0.0;
  int _pcdFrameCounter = 0;
  List<DetectionResult> currentResults = [];
  String? errorMessage;

  int currentCameraIndex = 0;
  List<CameraDescription> _cameras = [];

  VisionController() {
    WidgetsBinding.instance.addObserver(this);
    initCamera();
  }

  Future<void> initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        errorMessage = "No camera detected on device.";
        notifyListeners();
        return;
      }

      controller = CameraController(
        _cameras[currentCameraIndex],
        ResolutionPreset.max,
        enableAudio: false,
      );

      await controller!.initialize();
      await controller!.startImageStream((CameraImage image) {
        processFrame(image);
      });
      isInitialized = true;
      errorMessage = null;
    } catch (e) {
      errorMessage = "Failed to initialize camera: $e";
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_cameras.isEmpty || _cameras.length == 1) return;
    
    isInitialized = false;
    notifyListeners();
    
    currentCameraIndex = (currentCameraIndex + 1) % _cameras.length;
    await controller?.dispose();
    await initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
      isInitialized = false;
      notifyListeners();
    } else if (state == AppLifecycleState.resumed) {
      initCamera();
    }
  }

  void processFrame(CameraImage image) async {
    if (isProcessing || isCaptured) return;
    _lastFrame = image;

    isProcessing = true;

    _pcdFrameCounter++;
    if (isHistogramVisible && _pcdFrameCounter % 8 == 0) {
      _updateLumaHistogram(image);
    }

    final results = await compute(heavyInferenceTask, image);

    currentResults = results;
    notifyListeners();
    isProcessing = false;
  }

  Future<void> captureSnapshot() async {
    if (controller == null || !controller!.value.isInitialized) return;
    try {
      try {
        final boundary =
            previewKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          capturedRgbImage = await boundary.toImage();
        }
      } catch (e) {
        debugPrint("Failed to capture boundary: $e");
      }

      await controller!.pausePreview();
      isCaptured = true;
      resetPcd();
      selectedFilter = 'Original';
      notifyListeners();
    } catch (e) {
      debugPrint("Pause preview failed: $e");
    }
  }

  Future<void> resumeCamera() async {
    if (controller == null || !controller!.value.isInitialized) return;
    try {
      await controller!.resumePreview();
      isCaptured = false;
      capturedRgbImage?.dispose();
      capturedRgbImage = null;
      resetPcd();
      selectedFilter = 'Original';
      notifyListeners();
    } catch (e) {
      debugPrint("Resume preview failed: $e");
    }
  }

  Future<String?> savePhotoToGallery() async {
    try {
      final boundary =
          previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final pngBytes = byteData.buffer.asUint8List();

          final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
          final String name = "PatrolVision_$timestamp";
          final result = await ImageGallerySaverPlus.saveImage(
            pngBytes,
            name: name,
          );

          try {
            final appDir = await getApplicationDocumentsDirectory();
            final file = File('${appDir.path}/$name.png');
            await file.writeAsBytes(pngBytes);
            debugPrint("Save internal result: ${file.path}");
            return file.path;
          } catch(e) {
            return result['filePath']?.toString()?.replaceAll(RegExp(r'^file://'), '');
          }
        }
      }
    } catch (e) {
      debugPrint("Save to gallery failed: $e");
    }
    return null;
  }

  void applyFilterPreset(String preset) {
    selectedFilter = preset;

    isGrayscale = false;
    isSaltPepperOn = false;
    isMedianDenoiseOn = false;
    saltPepperProb = 0.0;
    blurSigma = 0.0;
    contrast = 1.0;
    brightness = 0.0;

    if (preset == 'Gray') {
      isGrayscale = true;
    } else if (preset == 'Noise') {
      isSaltPepperOn = true;
      saltPepperProb = 0.04;
    } else if (preset == 'Median') {
      isSaltPepperOn = true;
      saltPepperProb = 0.04;
      isMedianDenoiseOn = true;
    } else if (preset == 'Blur') {
      blurSigma = 3.0; // Peningkatan sigma agak tinggi buat kelihatan jelas
    } else if (preset == 'Contrast') {
      contrast = 1.6;
    }

    if ((isSaltPepperOn || isMedianDenoiseOn) && _lastFrame != null) {
      _updatePcdImage(_lastFrame!);
    } else {
      pcdImage = null;
    }

    notifyListeners();
  }

  void applyPixelPcd() {
    if ((isSaltPepperOn || isMedianDenoiseOn) && _lastFrame != null) {
      _updatePcdImage(_lastFrame!);
    }
  }

  void togglePcdPanel() {
    isPcdPanelVisible = !isPcdPanelVisible;
    notifyListeners();
  }

  void toggleGrayscale() {
    isGrayscale = !isGrayscale;
    notifyListeners();
  }

  void toggleSaltPepper() {
    isSaltPepperOn = !isSaltPepperOn;
    if (!isSaltPepperOn) {
      saltPepperProb = 0.0;
    } else if (saltPepperProb == 0.0) {
      saltPepperProb = 0.01;
    }
    notifyListeners();
  }

  void setSaltPepperProb(double value) {
    saltPepperProb = value;
    if (saltPepperProb > 0 && !isSaltPepperOn) {
      isSaltPepperOn = true;
    }
    notifyListeners();
  }

  void toggleMedianDenoise() {
    isMedianDenoiseOn = !isMedianDenoiseOn;
    notifyListeners();
  }

  void toggleHistogram() {
    isHistogramVisible = !isHistogramVisible;
    if (isHistogramVisible && isCaptured && _lastFrame != null) {
      _updateLumaHistogram(_lastFrame!);
    }
    notifyListeners();
  }

  void setContrast(double value) {
    contrast = value;
    notifyListeners();
  }

  void setBrightness(double value) {
    brightness = value;
    notifyListeners();
  }

  void setBlurSigma(double value) {
    blurSigma = value;
    notifyListeners();
  }

  void resetPcd() {
    isGrayscale = false;
    isHistogramVisible = false;
    contrast = 1.0;
    brightness = 0.0;
    blurSigma = 0.0;
    isSaltPepperOn = false;
    saltPepperProb = 0.0;
    isMedianDenoiseOn = false;
    lumaHistogram16 = List<int>.filled(16, 0);
    lumaAvg = 0.0;

    pcdImage?.dispose();
    pcdImage = null;
    notifyListeners();
  }

  Future<void> _updatePcdImage(CameraImage image) async {
    try {
      if (image.planes.isEmpty) return;
      final yPlane = image.planes.first.bytes;
      if (yPlane.isEmpty) return;

      final yStride = image.planes.first.bytesPerRow;
      if (yStride <= 0) return;

      final input = PcdFrameInput(
        yPlane: TransferableTypedData.fromList([yPlane]),
        srcWidth: image.width,
        srcHeight: image.height,
        yRowStride: yStride,
        contrast: contrast,
        brightness: brightness,
        grayscale: isGrayscale,
        saltPepperOn: isSaltPepperOn,
        saltPepperProb: saltPepperProb,
        medianOn: isMedianDenoiseOn,
        seed: DateTime.now().millisecondsSinceEpoch,
        maxTargetWidth:
            480, // Resolusi lebih besar saat mode Capture supaya fotonya jelas!
      );

      final result = await compute(pcdFrameTask, input);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        result.rgba,
        result.outWidth,
        result.outHeight,
        ui.PixelFormat.rgba8888,
        (ui.Image img) => completer.complete(img),
      );

      final img = await completer.future;
      pcdImage?.dispose();
      pcdImage = img;
      notifyListeners();
    } catch (_) {}
  }

  void _updateLumaHistogram(CameraImage image) {
    try {
      if (image.planes.isEmpty) return;
      final bytes =
          image.planes.first.bytes; // Plane Y (luminance) untuk YUV420
      if (bytes.isEmpty) return;

      final bins = List<int>.filled(16, 0);
      int sum = 0;
      int count = 0;

      const step = 20;
      for (int i = 0; i < bytes.length; i += step) {
        final v = bytes[i];
        bins[v >> 4] += 1; // 0..255 -> 16 bins
        sum += v;
        count += 1;
      }

      lumaHistogram16 = bins;
      lumaAvg = count == 0 ? 0.0 : (sum / count);
    } catch (_) {}
  }

  void toggleOverlay() {
    isOverlayVisible = !isOverlayVisible;
    notifyListeners();
  }

  Future<void> toggleFlash() async {
    if (controller == null || !controller!.value.isInitialized) return;

    try {
      isFlashOn = !isFlashOn;
      await controller!.setFlashMode(
        isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      notifyListeners();
    } catch (e) {
      debugPrint("Gagal mengubah status flash: $e");
      isFlashOn = !isFlashOn; // Revert jika gagal
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pcdImage?.dispose();
    controller?.dispose();
    super.dispose();
  }
}

class PcdFrameInput {
  final TransferableTypedData yPlane;
  final int srcWidth;
  final int srcHeight;
  final int yRowStride;
  final double contrast;
  final double brightness;
  final bool grayscale;
  final bool saltPepperOn;
  final double saltPepperProb;
  final bool medianOn;
  final int seed;
  final int maxTargetWidth;

  const PcdFrameInput({
    required this.yPlane,
    required this.srcWidth,
    required this.srcHeight,
    required this.yRowStride,
    required this.contrast,
    required this.brightness,
    required this.grayscale,
    required this.saltPepperOn,
    required this.saltPepperProb,
    required this.medianOn,
    required this.seed,
    required this.maxTargetWidth,
  });
}

class PcdFrameResult {
  final Uint8List rgba;
  final int outWidth;
  final int outHeight;

  const PcdFrameResult({
    required this.rgba,
    required this.outWidth,
    required this.outHeight,
  });
}

Future<PcdFrameResult> pcdFrameTask(PcdFrameInput input) async {
  final byteBuffer = input.yPlane.materialize();
  final y = byteBuffer.asUint8List();
  final srcW = input.srcWidth;
  final srcH = input.srcHeight;
  final stride = input.yRowStride;

  final maxW = input.maxTargetWidth;
  final scale = srcW > maxW ? (maxW / srcW) : 1.0;
  final outW = (srcW * scale).clamp(1, maxW).toInt();
  final outH = (srcH * scale).clamp(1, (maxW * 1.5).toInt()).toInt();

  final gray = Uint8List(outW * outH);

  final contrast = input.contrast;
  final brightnessOffset = input.brightness * 255.0;

  for (int oy = 0; oy < outH; oy++) {
    final sy = ((oy / outH) * srcH).toInt().clamp(0, srcH - 1);
    for (int ox = 0; ox < outW; ox++) {
      final sx = ((ox / outW) * srcW).toInt().clamp(0, srcW - 1);
      final v = y[sy * stride + sx];
      int vv = (v * contrast + brightnessOffset).round();
      if (vv < 0) vv = 0;
      if (vv > 255) vv = 255;
      gray[oy * outW + ox] = vv;
    }
  }

  if (input.saltPepperOn && input.saltPepperProb > 0) {
    final rand = math.Random(input.seed);
    final p = input.saltPepperProb;
    for (int i = 0; i < gray.length; i++) {
      final r = rand.nextDouble();
      if (r < p / 2) {
        gray[i] = 0;
      } else if (r < p) {
        gray[i] = 255;
      }
    }
  }

  Uint8List denoised = gray;
  if (input.medianOn) {
    denoised = _median3x3(gray, outW, outH);
  }

  final rgba = Uint8List(outW * outH * 4);
  for (int i = 0; i < denoised.length; i++) {
    final v = denoised[i];
    final o = i * 4;
    rgba[o] = v;
    rgba[o + 1] = v;
    rgba[o + 2] = v;
    rgba[o + 3] = 255;
  }

  return PcdFrameResult(rgba: rgba, outWidth: outW, outHeight: outH);
}

Uint8List _median3x3(Uint8List src, int w, int h) {
  final out = Uint8List(src.length);
  final window = List<int>.filled(9, 0);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int idx = 0;
      for (int dy = -1; dy <= 1; dy++) {
        final yy = (y + dy).clamp(0, h - 1);
        for (int dx = -1; dx <= 1; dx++) {
          final xx = (x + dx).clamp(0, w - 1);
          window[idx++] = src[yy * w + xx];
        }
      }
      window.sort();
      out[y * w + x] = window[4];
    }
  }
  return out;
}

Future<List<DetectionResult>> heavyInferenceTask(CameraImage image) async {
  final latency = math.Random().nextInt(200) + 100; // Mock latency 100-300ms
  await Future.delayed(Duration(milliseconds: latency));

  final epoch = DateTime.now().millisecondsSinceEpoch;
  final seed = (epoch ~/ 3000); // Berganti tepat setiap 3 detik
  final random = math.Random(seed);

  double w = 0.3 + random.nextDouble() * 0.3;
  double h = 0.3 + random.nextDouble() * 0.3;
  double x = random.nextDouble() * (1.0 - w);
  double y = random.nextDouble() * (1.0 - h);

  final types = [
    "[D00] LINE",
    "[D10] ALIGATOR",
    "[D20] CRACK",
    "[D40] POTHOLE",
    "[D50] MANHOLE",
  ];
  final typeIndex = random.nextInt(types.length);
  final score = 0.5 + random.nextDouble() * 0.49; // Akurasi 50% - 99%

  return [
    DetectionResult(
      box: Rect.fromLTWH(x, y, w, h),
      label: types[typeIndex],
      score: score,
    ),
  ];
}
