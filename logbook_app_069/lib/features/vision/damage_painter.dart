import 'package:flutter/material.dart';

class DetectionResult {
  final Rect box; // Koordinat kotak (normalisasi 0.0 - 1.0)
  final String label; // Tipe kerusakan (D40, D20, dll)
  final double score; // Persentase keyakinan AI

  DetectionResult({
    required this.box,
    required this.label,
    required this.score,
  });
}

class DamagePainter extends CustomPainter {
  final List<DetectionResult> results;

  DamagePainter(this.results);

  @override
  void paint(Canvas canvas, Size size) {
    for (var res in results) {
      Color damageColor = Colors.amber; // Kerusakan ringan (D00, D10, D20)
      if (res.label.contains("D40") || res.label.contains("D50")) {
        damageColor = Colors.redAccent; // Kerusakan berat (Pothole, Manhole)
      }

      final paint = Paint()
        ..color = damageColor
        ..strokeWidth =
            3.5 // Ditebalkan sedikit untuk visibilitas
        ..style = PaintingStyle.stroke; // Garis pinggir saja

      double left = res.box.left * size.width;
      double top = res.box.top * size.height;
      double width = res.box.width * size.width;
      double height = res.box.height * size.height;

      final rect = Rect.fromLTWH(left, top, width, height);

      canvas.drawRect(rect, paint);

      final percentageText = res.score > 0
          ? " - ${(res.score * 100).toStringAsFixed(0)}%"
          : "";
      final labelText = "${res.label}$percentageText";

      const fontSize = 14.0;
      const padX = 10.0;
      const padY = 6.0;
      const gap = 6.0;
      final textStyle = const TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            offset: Offset(1.0, 1.0),
            blurRadius: 4.0,
            color: Colors.black87,
          ),
        ],
      );

      final textSpan = TextSpan(text: labelText, style: textStyle);

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      final textW = textPainter.width;
      final textH = textPainter.height;
      final pillW = textW + padX * 2;
      final pillH = textH + padY * 2;

      double pillX = left;
      double pillY = top - pillH - gap;
      if (pillY < 0) {
        pillY = top + height + gap;
      }

      pillX = pillX.clamp(0.0, (size.width - pillW).clamp(0.0, size.width));
      pillY = pillY.clamp(0.0, (size.height - pillH).clamp(0.0, size.height));

      final pillRect = Rect.fromLTWH(pillX, pillY, pillW, pillH);
      final pillPaint = Paint()
        ..color = damageColor.withOpacity(0.85)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(999)),
        pillPaint,
      );

      textPainter.paint(canvas, Offset(pillX + padX, pillY + padY));
    }
  }

  @override
  bool shouldRepaint(covariant DamagePainter oldDelegate) {
    return oldDelegate.results != results;
  }
}
