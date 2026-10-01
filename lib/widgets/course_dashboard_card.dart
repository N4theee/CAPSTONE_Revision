import 'package:flutter/material.dart';

/// Two-tone course tile used on teacher and student dashboards (same layout, different palettes).
class CourseDashboardCard extends StatelessWidget {
  const CourseDashboardCard({
    super.key,
    required this.title,
    required this.sectionLine,
    required this.footerLine,
    required this.onTap,
    required this.cardTop,
    required this.cardTopBorder,
    required this.footerBar,
    required this.footerText,
    required this.chevron,
  });

  final String title;
  final String sectionLine;
  final String footerLine;
  final VoidCallback onTap;
  final Color cardTop;
  final Color cardTopBorder;
  final Color footerBar;
  final Color footerText;
  final Color chevron;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title, $sectionLine, $footerLine',
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: cardTop,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardTopBorder),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    sectionLine,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
            Container(
              color: footerBar,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      footerLine,
                      style: TextStyle(color: footerText, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: chevron),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
