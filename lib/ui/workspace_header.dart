import 'package:flutter/material.dart';

import 'app_theme.dart';

class WorkspaceHeader extends StatelessWidget implements PreferredSizeWidget {
  const WorkspaceHeader({
    super.key,
    required this.title,
    required this.wide,
    required this.navigation,
    required this.onPickProject,
  });

  final String title;
  final bool wide;
  final Widget navigation;
  final VoidCallback? onPickProject;

  @override
  Size get preferredSize => Size.fromHeight(wide ? 78 : 60);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1132),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const _BrandMark(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: wide ? 22 : 19,
                          fontWeight: FontWeight.w700,
                          color: forestInk,
                        ),
                      ),
                    ),
                  ),
                  if (wide) ...[
                    SizedBox(width: 356, child: navigation),
                    const Spacer(),
                  ],
                  Tooltip(
                    excludeFromSemantics: true,
                    message: 'اختيار مشروع',
                    child: TextButton.icon(
                      key: const ValueKey('project_picker'),
                      onPressed: onPickProject,
                      style: TextButton.styleFrom(
                        foregroundColor: forestInk,
                        backgroundColor: const Color(0xFFF0F5EF),
                        minimumSize: const Size(48, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text(
                        'مشاريعي',
                        semanticsLabel: 'اختيار مشروع',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: forestInk,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Center(
      child: CustomPaint(size: Size(28, 28), painter: _BrandPainter()),
    ),
  );
}

// Isometric column and footing from the application's launcher mark.
class _BrandPainter extends CustomPainter {
  const _BrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.45
      ..color = const Color(0xFFE4F2E6);
    canvas.drawPath(
      Path()
        ..moveTo(4, 19)
        ..lineTo(11, 15)
        ..moveTo(21, 15)
        ..lineTo(28, 19)
        ..lineTo(16, 26)
        ..lineTo(4, 19)
        ..lineTo(4, 23)
        ..lineTo(16, 30)
        ..lineTo(28, 23)
        ..lineTo(28, 19)
        ..moveTo(16, 26)
        ..lineTo(16, 30)
        ..moveTo(11, 17)
        ..lineTo(11, 7)
        ..lineTo(16, 4)
        ..lineTo(21, 7)
        ..lineTo(21, 17)
        ..lineTo(16, 20)
        ..close()
        ..moveTo(11, 7)
        ..lineTo(16, 10)
        ..lineTo(21, 7)
        ..moveTo(16, 10)
        ..lineTo(16, 20),
      pen,
    );
  }

  @override
  bool shouldRepaint(_BrandPainter oldDelegate) => false;
}
