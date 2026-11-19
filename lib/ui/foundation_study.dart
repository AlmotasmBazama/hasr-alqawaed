import 'package:flutter/material.dart';

/// Axonometric section through an isolated footing, on a drafting grid.
class FoundationStudy extends StatelessWidget {
  const FoundationStudy({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: IgnorePointer(
      child: CustomPaint(painter: _FootingPainter(), size: Size(240, 150)),
    ),
  );
}

class _FootingPainter extends CustomPainter {
  const _FootingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = size.width / 240 < size.height / 150
        ? size.width / 240
        : size.height / 150;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(
      (size.width - 240 * scale) / 2,
      (size.height - 150 * scale) / 2,
    );
    canvas.scale(scale);
    const ink = Color(0xFFC6E7CF);
    const guide = Color(0xFF99BFA7);
    Offset point(double x, double y, double z) =>
        Offset(120 + (x - y) * .92, 106 + (x + y) * .39 - z);
    void line(Offset a, Offset b, Color color, [double width = 1]) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = color
          ..strokeWidth = width,
      );
    }

    void face(List<Offset> points, Color fill) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.35,
      );
    }

    void block(double r, double bottom, double top) {
      final back = point(-r, -r, top);
      final right = point(r, -r, top);
      final front = point(r, r, top);
      final left = point(-r, r, top);
      face([
        left,
        front,
        point(r, r, bottom),
        point(-r, r, bottom),
      ], const Color(0xFF315C4B));
      face([
        right,
        front,
        point(r, r, bottom),
        point(r, -r, bottom),
      ], const Color(0xFF214D40));
      face([back, right, front, left], const Color(0xFF46735E));
    }

    for (var i = -90.0; i <= 90; i += 10) {
      line(point(i, -78, 0), point(i, 78, 0), const Color(0x235CA387), .7);
      line(point(-78, i, 0), point(78, i, 0), const Color(0x235CA387), .7);
    }
    block(46, 0, 8);
    block(38, 8, 20);
    block(21, 20, 32);
    block(11, 32, 77);
    for (final x in [-7.0, 7.0]) {
      for (final y in [-7.0, 7.0]) {
        line(point(x, y, 77), point(x, y, 91), const Color(0xFFE3C48B), 1.8);
      }
    }
    for (final x in [-46.0, 46.0]) {
      line(point(x, 47, 0), point(x, 59, 0), guide, .8);
      final tick = point(x, 54, 0);
      line(tick - const Offset(2, -2), tick + const Offset(2, -2), ink);
    }
    line(point(-49, 54, 0), point(49, 54, 0), guide, .8);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FootingPainter oldDelegate) => false;
}
