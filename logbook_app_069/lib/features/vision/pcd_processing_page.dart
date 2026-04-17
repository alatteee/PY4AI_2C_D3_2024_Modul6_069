import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import '../logbook/log_editor_page.dart';
import '../logbook/log_controller.dart' show LogController;

class PcdProcessingPage extends StatefulWidget {
  final ui.Image sourceImage;
  final LogController? logController;
  final Map<String, String>? currentUser;

  const PcdProcessingPage({
    super.key,
    required this.sourceImage,
    this.logController,
    this.currentUser,
  });

  @override
  State<PcdProcessingPage> createState() => _PcdProcessingPageState();
}

class _PcdProcessingPageState extends State<PcdProcessingPage> {
  ui.Image? _processedImage;
  bool _isProcessing = false;

  bool _isGrayscale = false;
  bool _isNoise = false;
  bool _isEdge = false;
  bool _isEqualize = false;
  bool _isSpec = false;
  bool _isLowpass = false;
  bool _isHighpass = false;
  bool _isBandpass = false;

  double _contrast = 1.0;
  double _brightness = 0.0;
  double _blur = 0.0;
  double _sharpen = 0.0;

  List<int> _histogram = List.filled(64, 0);
  double _lumaAvg = 0.0;

  @override
  void initState() {
    super.initState();
    _processedImage = widget.sourceImage;
    _runPcdPipeline();
  }

  Future<void> _runPcdPipeline() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final byteData = await widget.sourceImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final input = PcdPipelineInput(
        rgba: byteData.buffer.asUint8List(),
        width: widget.sourceImage.width,
        height: widget.sourceImage.height,
        grayscale: _isGrayscale,
        noise: _isNoise,
        edge: _isEdge,
        equalize: _isEqualize,
        spec: _isSpec,
        lowpass: _isLowpass,
        highpass: _isHighpass,
        bandpass: _isBandpass,
        contrast: _contrast,
        brightness: _brightness,
        blur: _blur,
        sharpen: _sharpen,
      );

      final result = await compute(_heavyPcdTask, input);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        result.rgba,
        result.width,
        result.height,
        ui.PixelFormat.rgba8888,
        (ui.Image img) => completer.complete(img),
      );

      final img = await completer.future;

      if (!mounted) return;
      setState(() {
        if (_processedImage != widget.sourceImage) {
          _processedImage?.dispose();
        }
        _processedImage = img;
        _histogram = result.histogram64;
        _lumaAvg = result.lumaAvg;
        _isProcessing = false;
      });
    } catch (e) {
      debugPrint("PCD Processing Error: $e");
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _reset() {
    setState(() {
      _isGrayscale = false;
      _isNoise = false;
      _isEdge = false;
      _isEqualize = false;
      _isSpec = false;
      _isLowpass = false;
      _isHighpass = false;
      _isBandpass = false;
      _contrast = 1.0;
      _brightness = 0.0;
      _blur = 0.0;
      _sharpen = 0.0;
    });
    _runPcdPipeline();
  }

  Future<void> _saveAndLog() async {
    if (_processedImage == null) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Menyimpan ke Galeri...')));

    final byteData = await _processedImage!.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) return;
    final pngBytes = byteData.buffer.asUint8List();

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final result = await ImageGallerySaverPlus.saveImage(pngBytes, name: "PCD_$timestamp");
    
    String? finalPath;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File('${appDir.path}/PCD_$timestamp.png');
      await file.writeAsBytes(pngBytes);
      finalPath = file.path;
    } catch(e) {
      finalPath = result is Map && result['filePath'] != null 
        ? result['filePath'].toString().replaceAll(RegExp(r'^file://'), '')
        : null;
    }
    
    final String? savedPath = finalPath;

    String info = "[Hasil Manipulasi PCD Test]\n";
    if (_isGrayscale) info += "- Grayscale Aktif\n";
    if (_isNoise) info += "- Noise Aktif\n";
    if (_isEdge) info += "- Edge Detection Aktif\n";
    if (_isEqualize) info += "- Histogram Equalization Aktif\n";
    if (_isSpec) info += "- Histogram Specification Aktif\n";
    if (_isLowpass) info += "- Lowpass Filter Aktif\n";
    if (_isHighpass) info += "- Highpass Filter Aktif\n";
    if (_isBandpass) info += "- Bandpass Filter Aktif\n";
    info += "- Contrast: ${_contrast.toStringAsFixed(2)}\n";
    info += "- Brightness: ${_brightness.toStringAsFixed(2)}\n";
    if (_blur > 0) info += "- Blur: ${_blur.toStringAsFixed(1)}\n";
    if (_sharpen > 0) info += "- Sharpen: ${_sharpen.toStringAsFixed(1)}\n";

    if (mounted) {
      final success = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LogEditorPage(initialImagePath: savedPath, 
            controller:
                widget.logController ??
                LogController(
                  userId: 'anon',
                  userRole: 'student',
                  teamId: 'ETS_001',
                ),
            currentUser: widget.currentUser,
            initialTitle: "Laporan Filter PCD Lengkap",
            initialDescription: "Foto dengan 12 Filter (Logbook app).\n$info",
          ),
        ),
      );

      if (success == true) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    }
  }

  Widget _buildFilterButton(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blue.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.blue : Colors.black87,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.blue : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistogram() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Histogram",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Text(
            "Luma avg: ${_lumaAvg.toStringAsFixed(0)}",
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            width: double.infinity,
            child: CustomPaint(painter: _HistogramPainter(_histogram)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String pcdStatus = "Natural";
    if (_isGrayscale) pcdStatus = "Grayscale";
    if (_isEdge) pcdStatus = "Edge Detection";
    if (_isNoise) pcdStatus = "Salt&Pepper Noise";
    if (_isEqualize) pcdStatus = "Hist Equalize";
    if (_isSpec) pcdStatus = "Hist Spec";
    if (_isLowpass) pcdStatus = "Lowpass";
    if (_isHighpass) pcdStatus = "Highpass";
    if (_isBandpass) pcdStatus = "Bandpass";

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: const Text(
          "PCD Processing",
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check, color: Colors.blue, size: 28),
              onPressed: _saveAndLog,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black12,
              ),
              clipBehavior: Clip.hardEdge,
              child: _processedImage != null
                  ? RawImage(
                      image: _processedImage,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 12),
            Text(
              "PCD: $pcdStatus",
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 20),
            _buildHistogram(),

            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterButton(
                          "Grayscale",
                          Icons.tonality,
                          _isGrayscale,
                          () {
                            setState(() => _isGrayscale = !_isGrayscale);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFilterButton(
                          "Noise",
                          Icons.grain,
                          _isNoise,
                          () {
                            setState(() => _isNoise = !_isNoise);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterButton(
                          "Equalize",
                          Icons.equalizer,
                          _isEqualize,
                          () {
                            setState(() => _isEqualize = !_isEqualize);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFilterButton(
                          "H. Spec",
                          Icons.query_stats,
                          _isSpec,
                          () {
                            setState(() => _isSpec = !_isSpec);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterButton(
                          "Edge",
                          Icons.broken_image,
                          _isEdge,
                          () {
                            setState(() => _isEdge = !_isEdge);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFilterButton(
                          "Lowpass",
                          Icons.blur_on,
                          _isLowpass,
                          () {
                            setState(() => _isLowpass = !_isLowpass);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterButton(
                          "Highpass",
                          Icons.grain,
                          _isHighpass,
                          () {
                            setState(() => _isHighpass = !_isHighpass);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFilterButton(
                          "Bandpass",
                          Icons.linear_scale,
                          _isBandpass,
                          () {
                            setState(() => _isBandpass = !_isBandpass);
                            _runPcdPipeline();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterButton(
                          "Reset",
                          Icons.refresh,
                          false,
                          _reset,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 30),

                  _buildSliderRow(
                    "Contrast",
                    _contrast,
                    0.5,
                    2.0,
                    (v) => setState(() => _contrast = v),
                  ),
                  _buildSliderRow(
                    "Brightness",
                    _brightness,
                    -1.0,
                    1.0,
                    (v) => setState(() => _brightness = v),
                  ),
                  _buildSliderRow(
                    "Blur",
                    _blur,
                    0.0,
                    5.0,
                    (v) => setState(() => _blur = v),
                  ),
                  _buildSliderRow(
                    "Sharpen",
                    _sharpen,
                    0.0,
                    5.0,
                    (v) => setState(() => _sharpen = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: const Color(0xFF4C5D8A),
          inactiveColor: Colors.black12,
          onChanged: onChanged,
          onChangeEnd: (_) => _runPcdPipeline(),
        ),
      ],
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> bins;
  _HistogramPainter(this.bins);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4C5D8A)
      ..style = PaintingStyle.fill;
    final maxVal = bins.isEmpty ? 1 : bins.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) return;

    final barW = size.width / bins.length;
    for (int i = 0; i < bins.length; i++) {
      final h = (bins[i] / maxVal) * size.height;
      canvas.drawRect(
        Rect.fromLTWH(i * barW, size.height - h, barW * 0.7, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) => true;
}

class PcdPipelineInput {
  final Uint8List rgba;
  final int width;
  final int height;

  final bool grayscale;
  final bool noise;
  final bool edge;
  final bool equalize;
  final bool spec;
  final bool lowpass;
  final bool highpass;
  final bool bandpass;

  final double contrast;
  final double brightness;
  final double blur;
  final double sharpen;

  PcdPipelineInput({
    required this.rgba,
    required this.width,
    required this.height,
    required this.grayscale,
    required this.noise,
    required this.edge,
    required this.equalize,
    required this.spec,
    required this.lowpass,
    required this.highpass,
    required this.bandpass,
    required this.contrast,
    required this.brightness,
    required this.blur,
    required this.sharpen,
  });
}

class PcdPipelineResult {
  final Uint8List rgba;
  final int width;
  final int height;
  final List<int> histogram64;
  final double lumaAvg;
  PcdPipelineResult(
    this.rgba,
    this.width,
    this.height,
    this.histogram64,
    this.lumaAvg,
  );
}

Future<PcdPipelineResult> _heavyPcdTask(PcdPipelineInput input) async {
  final w = input.width;
  final h = input.height;
  Uint8List pixels = Uint8List.fromList(input.rgba); // clone so we can mutate

  if (input.grayscale ||
      input.equalize ||
      input.spec ||
      input.edge ||
      input.lowpass ||
      input.highpass ||
      input.bandpass) {
    for (int i = 0; i < pixels.length; i += 4) {
      int r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
      int luma = (0.299 * r + 0.587 * g + 0.114 * b).round();
      pixels[i] = pixels[i + 1] = pixels[i + 2] = luma;
    }
  }

  if (input.contrast != 1.0 || input.brightness != 0.0) {
    double factor = input.contrast;
    int offset = (input.brightness * 255.0).round();
    for (int i = 0; i < pixels.length; i += 4) {
      for (int c = 0; c < 3; c++) {
        int v = (pixels[i + c] * factor + offset).round().clamp(0, 255);
        pixels[i + c] = v;
      }
    }
  }

  if (input.noise) {
    final rand = math.Random(12345);
    for (int i = 0; i < pixels.length; i += 4) {
      double r = rand.nextDouble();
      if (r < 0.02) {
        pixels[i] = pixels[i + 1] = pixels[i + 2] = 0; // pepper
      } else if (r < 0.04) {
        pixels[i] = pixels[i + 1] = pixels[i + 2] = 255; // salt
      }
    }
  }

  if (input.equalize) {
    List<int> hist = List.filled(256, 0);
    for (int i = 0; i < pixels.length; i += 4) {
      hist[pixels[i]]++;
    }
    List<int> cdf = List.filled(256, 0);
    cdf[0] = hist[0];
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + hist[i];
    }
    int cdfMin = cdf.firstWhere((x) => x > 0);
    for (int i = 0; i < pixels.length; i += 4) {
      int v = pixels[i];
      int nv = ((cdf[v] - cdfMin) / ((w * h) - cdfMin) * 255).round();
      pixels[i] = pixels[i + 1] = pixels[i + 2] = nv.clamp(0, 255);
    }
  }

  if (input.spec) {
    List<int> hist = List.filled(256, 0);
    for (int i = 0; i < pixels.length; i += 4) {
      hist[pixels[i]]++;
    }
    List<int> cdf = List.filled(256, 0);
    cdf[0] = hist[0];
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + hist[i];
    }
    int cdfMin = cdf.firstWhere((x) => x > 0);
    double total = ((w * h) - cdfMin).toDouble();

    for (int i = 0; i < pixels.length; i += 4) {
      int v = pixels[i];
      double p = (cdf[v] - cdfMin) / total;
      int nv = (math.pow(p, 0.5) * 255).round();
      pixels[i] = pixels[i + 1] = pixels[i + 2] = nv.clamp(0, 255);
    }
  }

  if (input.edge ||
      input.sharpen > 0 ||
      input.blur > 0 ||
      input.lowpass ||
      input.highpass ||
      input.bandpass) {
    pixels = _applySpatialFilters(input, pixels, w, h);
  }

  List<int> hist64 = List.filled(64, 0);
  int sumLuma = 0;
  for (int i = 0; i < pixels.length; i += 4) {
    int v = pixels[i]; // assuming grayscale or using R as approx luma
    hist64[v >> 2]++;
    sumLuma += v;
  }

  return PcdPipelineResult(pixels, w, h, hist64, sumLuma / (w * h));
}

Uint8List _applySpatialFilters(
  PcdPipelineInput input,
  Uint8List src,
  int w,
  int h,
) {
  Uint8List dst = Uint8List.fromList(src);

  List<double> kernel = [0, 0, 0, 0, 1, 0, 0, 0, 0];
  if (input.lowpass || input.blur > 0) {
    // Box blur / Lowpass
    kernel = [1 / 9, 1 / 9, 1 / 9, 1 / 9, 1 / 9, 1 / 9, 1 / 9, 1 / 9, 1 / 9];
  } else if (input.highpass) {
    // Highpass
    kernel = [-1, -1, -1, -1, 8, -1, -1, -1, -1];
  } else if (input.bandpass) {
    // Bandpass (Diff of Gaussians sketch)
    kernel = [-1, -1, -1, -1, 8, -1, -1, -1, -1];
  } else if (input.edge) {
    // Edge (Sobel approx)
    kernel = [-1, -1, -1, -1, 8, -1, -1, -1, -1];
  } else if (input.sharpen > 0) {
    // Sharpen
    double v = input.sharpen;
    kernel = [0, -v, 0, -v, 1 + 4 * v, -v, 0, -v, 0];
  } else {
    return dst;
  }

  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      int off = (y * w + x) * 4;
      double r = 0, g = 0, b = 0;

      for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
          int koff = ((y + ky) * w + (x + kx)) * 4;
          double kv = kernel[(ky + 1) * 3 + (kx + 1)];
          r += src[koff] * kv;
          g += src[koff + 1] * kv;
          b += src[koff + 2] * kv;
        }
      }

      if (input.edge || input.highpass || input.bandpass) {
        r = r.abs();
        g = g.abs();
        b = b.abs();
      }

      dst[off] = r.round().clamp(0, 255);
      dst[off + 1] = g.round().clamp(0, 255);
      dst[off + 2] = b.round().clamp(0, 255);
    }
  }

  return dst;
}
