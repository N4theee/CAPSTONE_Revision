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
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleSize =
            (constraints.maxWidth / 11).clamp(10.5, 13.0).toDouble();
        final subSize =
            (constraints.maxWidth / 13).clamp(10.0, 12.0).toDouble();
        final padH = (constraints.maxWidth * 0.08).clamp(10.0, 14.0);
        final padV = (constraints.maxHeight * 0.06).clamp(10.0, 16.0);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border:
                    Border.all(color: cardTopBorder.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Container(
                        color: cardTop,
                        padding: EdgeInsets.symmetric(
                            horizontal: padH, vertical: padV),
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textScaler: scaler,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: titleSize,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: padV * 0.35),
                            Text(
                              sectionLine,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textScaler: scaler,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: subSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      color: footerBar,
                      padding: EdgeInsets.symmetric(
                        horizontal: padH.clamp(10.0, 12.0),
                        vertical: (padV * 0.65).clamp(8.0, 11.0),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              footerLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: scaler,
                              style: TextStyle(
                                color: footerText,
                                fontSize: subSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: chevron, size: 20 + padH * 0.1),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
