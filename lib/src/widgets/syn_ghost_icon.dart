import 'package:flutter/material.dart';

class SynGhostIcon extends StatelessWidget {
  const SynGhostIcon({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final double s = size ?? iconTheme.size ?? 24.0;
    final Color c =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(painter: _SynGhostPainter(c)),
    );
  }
}

class _SynGhostPainter extends CustomPainter {
  const _SynGhostPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 500, size.height / 500);
    canvas.translate(-181, -87);

    final path = Path()
      ..moveTo(211, 556)
      ..lineTo(211, 339)
      ..arcToPoint(const Offset(651, 339), radius: const Radius.circular(220))
      ..lineTo(651, 556)
      ..arcToPoint(
        const Offset(504.3, 556),
        radius: const Radius.circular(74.4),
        clockwise: false,
      )
      ..arcToPoint(
        const Offset(357.7, 556),
        radius: const Radius.circular(74.4),
        clockwise: false,
      )
      ..arcToPoint(
        const Offset(211, 556),
        radius: const Radius.circular(74.4),
        clockwise: false,
      )
      ..close();

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.drawPath(path, stroke);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(const Offset(344, 334), 24, fill);
    canvas.drawCircle(const Offset(518, 334), 24, fill);
  }

  @override
  bool shouldRepaint(covariant _SynGhostPainter oldDelegate) =>
      oldDelegate.color != color;
}
