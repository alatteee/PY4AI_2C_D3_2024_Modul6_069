import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart'; // Tambahan untuk buka settings (Homework)
import 'package:logbook_app_069/features/vision/damage_painter.dart';
import 'package:logbook_app_069/features/vision/vision_controller.dart';
import 'package:logbook_app_069/features/logbook/log_editor_page.dart';
import 'package:logbook_app_069/features/logbook/log_controller.dart';
import 'package:logbook_app_069/features/vision/pcd_processing_page.dart';

class VisionView extends StatefulWidget {
  final LogController? logController;
  final Map<String, String>? currentUser;

  const VisionView({super.key, this.logController, this.currentUser});

  @override
  State<VisionView> createState() => _VisionViewState();
}

class _VisionViewState extends State<VisionView> {
  late VisionController _visionController;

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final Uint8List bytes = await image.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image decodedImage = frameInfo.image;

      if (mounted) {
        _visionController.controller?.pausePreview();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PcdProcessingPage(
              sourceImage: decodedImage,
              logController: widget.logController,
              currentUser: widget.currentUser,
            ),
          ),
        ).then((_) => _visionController.resumeCamera());
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  int _deviceOrientationToDegrees(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeLeft:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeRight:
        return 270;
    }
  }

  @override
  void initState() {
    super.initState();
    _visionController = VisionController();
  }

  @override
  void dispose() {
    _visionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Smart-Patrol Vision")),
      body: ListenableBuilder(
        listenable: _visionController,
        builder: (context, child) {
          if (_visionController.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      size: 80,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "No Camera Access",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _visionController.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.settings),
                      label: const Text("Open Settings"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          openAppSettings(), // Membuka pengaturan HP (Homework)
                    ),
                  ],
                ),
              ),
            );
          }

          if (!_visionController.isInitialized) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 6.0,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blueAccent,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    "Menghubungkan ke Sensor Visual...",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Mohon tunggu sebentar, sedang menyiapkan kamera.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return _buildVisionStack();
        },
      ),
    );
  }

  Widget _buildVisionStack() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 1 / _visionController.controller!.value.aspectRatio,
            child: RepaintBoundary(
              key: _visionController.previewKey,
              child: _buildPcdPreview(
                child: CameraPreview(_visionController.controller!),
              ),
            ),
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 160,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.black26, Colors.transparent],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),
        ),

        Positioned(
          top: 16,
          left: 16,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_visionController.isHistogramVisible)
                  _HistogramCard(
                    bins16: _visionController.lumaHistogram16,
                    lumaAvg: _visionController.lumaAvg,
                  ),
                const SizedBox(height: 10),
                _StatusChips(controller: _visionController),
              ],
            ),
          ),
        ),

        if (_visionController.isOverlayVisible)
          Positioned.fill(
            child: CustomPaint(
              painter: DamagePainter(
                _visionController.currentResults,
              ), // Langkah 4 & 6.5
            ),
          ),

        if (!_visionController.isCaptured)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _visionController.isFlashOn
                      ? "Torch ON"
                      : "Torch OFF",
                  icon: Icon(
                    _visionController.isFlashOn
                        ? Icons.flash_on
                        : Icons.flash_off,
                    color: _visionController.isFlashOn
                        ? Colors.yellow
                        : Colors.white,
                  ),
                  iconSize: 32,
                  onPressed: () => _visionController.toggleFlash(),
                ),

                IconButton(
                  tooltip: "Gallery",
                  icon: const Icon(Icons.image, color: Colors.white),
                  iconSize: 32,
                  onPressed: _pickImageFromGallery,
                ),

                GestureDetector(
                  onTap: () async {
                    await _visionController.captureSnapshot();
                    if (_visionController.capturedRgbImage != null &&
                        context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PcdProcessingPage(
                            sourceImage: _visionController.capturedRgbImage!,
                            logController: widget.logController,
                            currentUser: widget.currentUser,
                          ),
                        ),
                      ).then((_) => _visionController.resumeCamera());
                    }
                  },
                  child: Container(
                    height: 75,
                    width: 75,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.white.withOpacity(0.3),
                    ),
                    child: Center(
                      child: Container(
                        height: 55,
                        width: 55,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                IconButton(
                  tooltip: "Switch Camera",
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                  iconSize: 32,
                  onPressed: () => _visionController.switchCamera(),
                ),

                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Overlay",
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _visionController.isOverlayVisible,
                        onChanged: (_) => _visionController.toggleOverlay(),
                        activeThumbColor: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: _FilterCarousel(controller: _visionController, parentLogController: widget.logController, currentUser: widget.currentUser),
          ),
      ],
    );
  }

  Widget _buildPcdPreview({required Widget child}) {
    final pixelPcdEnabled =
        _visionController.isSaltPepperOn || _visionController.isMedianDenoiseOn;

    Widget baseView = child;
    if (_visionController.isCaptured &&
        _visionController.capturedRgbImage != null &&
        !pixelPcdEnabled) {
      baseView = RawImage(
        image: _visionController.capturedRgbImage,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
    }

    if (pixelPcdEnabled && _visionController.pcdImage != null) {
      final cam = _visionController.controller;
      final sensor = cam?.description.sensorOrientation ?? 0;
      final device =
          cam?.value.deviceOrientation ?? DeviceOrientation.portraitUp;
      final deviceDegrees = _deviceOrientationToDegrees(device);
      final lens = cam?.description.lensDirection ?? CameraLensDirection.back;

      final rotationDegrees = (lens == CameraLensDirection.front)
          ? (sensor + deviceDegrees) % 360
          : (sensor - deviceDegrees + 360) % 360;
      final quarterTurns = (rotationDegrees ~/ 90) % 4;

      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _visionController.pcdImage!.width.toDouble(),
          height: _visionController.pcdImage!.height.toDouble(),
          child: RotatedBox(
            quarterTurns: quarterTurns,
            child: (lens == CameraLensDirection.front)
                ? Transform.scale(
                    scaleX: -1,
                    child: RawImage(
                      image: _visionController.pcdImage,
                      filterQuality: FilterQuality.none,
                    ),
                  )
                : RawImage(
                    image: _visionController.pcdImage,
                    filterQuality: FilterQuality.none,
                  ),
          ),
        ),
      );
    }

    final matrix = _buildColorMatrix(
      grayscale: _visionController.isGrayscale,
      contrast: _visionController.contrast,
      brightness: _visionController.brightness,
    );

    Widget current = baseView;

    if (_visionController.selectedFilter == 'Normal') {
      return current;
    }
    current = ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: current,
    );

    if (_visionController.blurSigma > 0.0) {
      current = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: _visionController.blurSigma,
          sigmaY: _visionController.blurSigma,
        ),
        child: current,
      );
    }

    return current;
  }

  List<double> _buildColorMatrix({
    required bool grayscale,
    required double contrast,
    required double brightness,
  }) {
    final b = brightness * 255.0;

    if (grayscale) {
      final r = 0.2126 * contrast;
      final g = 0.7152 * contrast;
      final bl = 0.0722 * contrast;
      return <double>[
        r,
        g,
        bl,
        0,
        b,
        r,
        g,
        bl,
        0,
        b,
        r,
        g,
        bl,
        0,
        b,
        0,
        0,
        0,
        1,
        0,
      ];
    }

    return <double>[
      contrast,
      0,
      0,
      0,
      b,
      0,
      contrast,
      0,
      0,
      b,
      0,
      0,
      contrast,
      0,
      b,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}

class _HistogramCard extends StatelessWidget {
  final List<int> bins16;
  final double lumaAvg;

  const _HistogramCard({required this.bins16, required this.lumaAvg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Histogram",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Avg ${lumaAvg.toStringAsFixed(0)}",
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(painter: _HistogramPainter(bins16)),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Dark",
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              Text(
                "Bright",
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> bins16;

  _HistogramPainter(this.bins16);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;

    final maxVal = bins16.isEmpty
        ? 1
        : (bins16.reduce((a, b) => a > b ? a : b));
    final barWidth = size.width / (bins16.isEmpty ? 1 : bins16.length);

    for (int i = 0; i < bins16.length; i++) {
      final h = maxVal == 0 ? 0.0 : (bins16[i] / maxVal) * size.height;
      final rect = Rect.fromLTWH(
        i * barWidth,
        size.height - h,
        barWidth * 0.8,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) {
    return oldDelegate.bins16 != bins16;
  }
}

class _FilterCarousel extends StatelessWidget {
  final VisionController controller;
  final LogController? parentLogController;
  final Map<String, String>? currentUser;

  const _FilterCarousel({required this.controller, this.parentLogController, this.currentUser});

  Widget _buildSlider() {
    if (controller.selectedFilter == 'Noise') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Noise Probability: ${controller.saltPepperProb.toStringAsFixed(3)}",
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Slider(
            value: controller.saltPepperProb,
            min: 0.0,
            max: 0.05,
            divisions: 50,
            activeColor: Colors.blueAccent,
            inactiveColor: Colors.white24,
            onChanged: (v) => controller.setSaltPepperProb(v),
            onChangeEnd: (v) {
              controller.setSaltPepperProb(v);
              controller.applyPixelPcd();
            },
          ),
        ],
      );
    } else if (controller.selectedFilter == 'Contrast') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Contrast: ${controller.contrast.toStringAsFixed(2)}",
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Slider(
            value: controller.contrast,
            min: 0.5,
            max: 2.0,
            divisions: 30,
            activeColor: Colors.blueAccent,
            inactiveColor: Colors.white24,
            onChanged: (v) => controller.setContrast(v),
          ),
        ],
      );
    } else if (controller.selectedFilter == 'Blur') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Blur Radius (Sigma): ${controller.blurSigma.toStringAsFixed(1)}",
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Slider(
            value: controller.blurSigma,
            min: 0.0,
            max: 5.0,
            divisions: 50,
            activeColor: Colors.blueAccent,
            inactiveColor: Colors.white24,
            onChanged: (v) => controller.setBlurSigma(v),
          ),
        ],
      );
    }
    return const SizedBox(height: 52);
  }

  @override
  Widget build(BuildContext context) {
    final filters = ['Normal', 'Gray', 'Noise', 'Median', 'Blur', 'Contrast'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildSlider(),
          ),

          SizedBox(
            height: 65,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              itemBuilder: (context, index) {
                final filter = filters[index];
                final isSelected = controller.selectedFilter == filter;
                return GestureDetector(
                  onTap: () => controller.applyFilterPreset(filter),
                  child: Container(
                    width: 65,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blueAccent.withValues(alpha: 0.5)
                          : Colors.black45,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Colors.blueAccent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      filter,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 10.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => controller.resumeCamera(),
                ),

                GestureDetector(
                  onTap: () => controller.toggleHistogram(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bar_chart,
                        color: controller.isHistogramVisible
                            ? Colors.purpleAccent
                            : Colors.white70,
                        size: 28,
                      ),
                      Text(
                        "Hist",
                        style: TextStyle(
                          color: controller.isHistogramVisible
                              ? Colors.purpleAccent
                              : Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),

                IconButton(
                  icon: const Icon(
                    Icons.check,
                    color: Colors.blueAccent,
                    size: 32,
                  ),
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Menyimpan ke Galeri...')),
                    );
                    final savedPath = await controller.savePhotoToGallery();

                    String appliedFilterInfo =
                        "[Hasil Manipulasi PCD Terapan]\n";
                    appliedFilterInfo +=
                        "- Filter Dasamuka UI: ${controller.selectedFilter}\n";
                    if (controller.isGrayscale)
                      appliedFilterInfo += "- Grayscale Aktif\n";
                    if (controller.isSaltPepperOn)
                      appliedFilterInfo +=
                          "- Salt & Pepper Noise (${(controller.saltPepperProb * 100).toInt()}%)\n";
                    if (controller.isMedianDenoiseOn)
                      appliedFilterInfo += "- Median Blur (Aperture 3x3)\n";
                    if (controller.selectedFilter == 'Contrast') {
                      appliedFilterInfo +=
                          "- Contrast Ratio: ${controller.contrast.toStringAsFixed(2)}\n";
                    } else if (controller.selectedFilter == 'Blur') {
                      appliedFilterInfo +=
                          "- Blur Sigma: ${controller.blurSigma.toStringAsFixed(2)}\n";
                    }

                    if (controller.currentResults.isNotEmpty) {
                      appliedFilterInfo += "\n[Deteksi AI Ditemukan]:\n";
                      for (var res in controller.currentResults) {
                        appliedFilterInfo +=
                            "- ${res.label} (${(res.score * 100).toStringAsFixed(1)}%)\n";
                      }
                    }

                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LogEditorPage(
                            controller: parentLogController ?? LogController(
                              userId: 'anon',
                              userRole: 'student',
                              teamId: 'ETS_001',
                            ),
                            currentUser: currentUser,
                            initialTitle: "Laporan Inspeksi Camera PCD",
                            initialDescription:
                                "Foto inspeksi berhasil disimpan di galeri perangkat Anda.\n\n$appliedFilterInfo",
                            initialImagePath: savedPath,
                          ),
                        ),
                      );
                    }

                    controller.resumeCamera();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10), // Bottom padding for safety
        ],
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  final VisionController controller;

  const _StatusChips({required this.controller});

  @override
  Widget build(BuildContext context) {
    final effects = <String>[];
    if (controller.isGrayscale) effects.add("Gray");
    if (controller.isSaltPepperOn) effects.add("Noise");
    if (controller.isMedianDenoiseOn) effects.add("Median");
    if (controller.blurSigma > 0.0) effects.add("Blur");
    if (controller.isHistogramVisible) effects.add("Hist");
    if (controller.contrast != 1.0) effects.add("Ctr");
    if (controller.brightness != 0.0) effects.add("Brt");

    final chips = <String>[];
    if (effects.isNotEmpty) {
      chips.add("PCD: ${effects.join(' + ')}");
    }

    if (!controller.isOverlayVisible) {
      chips.add("Overlay: OFF");
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    Widget chip(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(chips[0]),
        if (chips.length > 1) ...[const SizedBox(width: 8), chip(chips[1])],
      ],
    );
  }
}
