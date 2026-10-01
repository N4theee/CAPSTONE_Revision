import 'package:flutter/material.dart';

/// Script initials used only as decoration on the two signed-in dashboards.
class ProxamityMark extends StatelessWidget {
  const ProxamityMark({super.key, this.width = 160, this.color});

  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Text(
          '𝓟𝓡𝓧',
          style: TextStyle(
            fontFamily: 'ProxamityScript',
            fontSize: 100,
            color: color ?? Colors.white,
          ),
        ),
      ),
    ),
  );
}
