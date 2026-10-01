import 'package:flutter/material.dart';

/// Shared breakpoints and helpers for small phones through tablets.
class AppBreakpoints {
  AppBreakpoints._();

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;

  static double height(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static EdgeInsets safePadding(BuildContext context) =>
      MediaQuery.paddingOf(context);

  /// Top dashboard: overflow risk — collapse icon row into a menu.
  static bool useCompactDashboardActions(BuildContext context) =>
      width(context) < 520;

  /// Course grid: 1 column on very narrow devices, 2 on phones, 3 on tablets.
  static int courseGridColumns(BuildContext context) {
    final w = width(context);
    if (w < 340) return 1;
    if (w < 720) return 2;
    return 3;
  }

  static double courseGridChildAspectRatio(BuildContext context, int cols) {
    final h = height(context);
    if (cols == 1) {
      if (h < 640) return 1.35;
      return 1.2;
    }
    if (cols == 2) {
      if (h < 640) return 0.88;
      return 0.78;
    }
    return 0.92;
  }

  static double sessionRadarHeight(BuildContext context, {double max = 260}) {
    final h = height(context);
    final scale = (h / 800).clamp(0.72, 1.0);
    return (max * scale).clamp(180.0, max);
  }

  static double horizontalPadding(BuildContext context) {
    final w = width(context);
    if (w < 360) return 14;
    if (w < 600) return 18;
    return 24;
  }

  /// Centered content column on large screens (history, detail panes).
  static double historyContentMaxWidth(double screenWidth) {
    if (screenWidth >= 1400) return 1040;
    if (screenWidth >= 1000) return 880;
    if (screenWidth >= 720) return 640;
    return screenWidth;
  }

  /// Session history cards: 1 on phones, 2 on tablets, 3 on wide desktop.
  static int historySessionGridColumns(double screenWidth) {
    if (screenWidth < 560) return 1;
    if (screenWidth < 960) return 2;
    return 3;
  }

  /// Fixed row height for history grid tiles (avoids aspect-ratio overflows).
  static double historySessionTileExtent(BuildContext context, int cols) {
    final raw = MediaQuery.textScalerOf(context).scale(1.0);
    final s = raw < 1 ? 1.0 : raw;
    switch (cols) {
      case 1:
        return 190 * s;
      case 2:
        return 210 * s;
      default:
        return 230 * s;
    }
  }

  /// Narrow filter / date strip stacks vertically.
  static bool historyUseCompactFilters(double contentWidth) =>
      contentWidth < 420;
}
