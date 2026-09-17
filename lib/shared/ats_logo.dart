import 'package:flutter/material.dart';

class ATSLogo extends StatelessWidget {
  final double size;
  final bool showText;

  const ATSLogo({
    super.key, 
    this.size = 48.0, 
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    const Color goldPrimary = Color(0xFFE2B93B);
    const Color goldLight = Color(0xFFF3E5AB);
    const Color obsidianDark = Color(0xFF0D0D11);
    const Color cardSurface = Color(0xFF16161F);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // --- Geometric App Icon Container ---
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: cardSurface,
            borderRadius: BorderRadius.circular(size * 0.28),
            border: Border.all(
              color: goldPrimary.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: goldPrimary.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: SizedBox(
              width: size * 0.65,
              height: size * 0.65,
              child: CustomPaint(
                painter: _ATSGeometricLogoPainter(
                  goldPrimary: goldPrimary,
                  goldLight: goldLight,
                  obsidianDark: obsidianDark,
                ),
              ),
            ),
          ),
        ),

        // --- Optional Corporate Typography ---
        if (showText) ...[
          SizedBox(width: size * 0.35),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ATS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ONEWORK',
                style: TextStyle(
                  color: goldPrimary,
                  fontSize: size * 0.17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.5,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ]
      ],
    );
  }
}

/// Custom painter that draws the interlocking geometric ribbon shards
class _ATSGeometricLogoPainter extends CustomPainter {
  final Color goldPrimary;
  final Color goldLight;
  final Color obsidianDark;

  const _ATSGeometricLogoPainter({
    required this.goldPrimary,
    required this.goldLight,
    required this.obsidianDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Top Slanted Ribbon (Light Gold)
    paint.color = goldLight;
    final topPath = Path()
      ..moveTo(size.width * 0.25, size.height * 0.12)
      ..lineTo(size.width * 0.90, size.height * 0.12)
      ..lineTo(size.width * 0.65, size.height * 0.42)
      ..lineTo(size.width * 0.0, size.height * 0.42)
      ..close();
    canvas.drawPath(topPath, paint);

    // Middle/Center Interlocking Shard (Primary Gold)
    paint.color = goldPrimary;
    final midPath = Path()
      ..moveTo(size.width * 0.35, size.height * 0.48)
      ..lineTo(size.width * 0.70, size.height * 0.48)
      ..lineTo(size.width * 0.45, size.height * 0.78)
      ..lineTo(size.width * 0.10, size.height * 0.78)
      ..close();
    canvas.drawPath(midPath, paint);

    // Bottom Dark Shard for 3D depth effect
    paint.color = obsidianDark;
    final bottomPath = Path()
      ..moveTo(size.width * 0.45, size.height * 0.78)
      ..lineTo(size.width * 0.70, size.height * 0.48)
      ..lineTo(size.width * 0.90, size.height * 0.72)
      ..lineTo(size.width * 0.65, size.height * 1.0)
      ..close();
    canvas.drawPath(bottomPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}