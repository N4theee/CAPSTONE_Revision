import 'package:flutter/material.dart';

/// Keeps scrollables bounded while limiting reading width on large displays.
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({super.key, required this.child, this.maxWidth = 1000});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: child,
        ),
      ),
    ),
  );
}

class AdaptiveHeading extends StatelessWidget {
  const AdaptiveHeading({super.key, required this.title, this.action});
  final Widget title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          if (action != null) ...[
            const SizedBox(width: 16),
            Flexible(child: action!),
          ],
        ],
      );
    },
  );
}

class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

/// Natural-height cards, with column count determined by actual content width.
class ResponsiveCourseGrid extends StatelessWidget {
  const ResponsiveCourseGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
    this.physics,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: physics,
    padding: padding,
    child: LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
        final columns = ((box.maxWidth + 16) / (260 * scale + 16))
            .floor()
            .clamp(1, 4);
        final width = (box.maxWidth - 16 * (columns - 1)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (var i = 0; i < itemCount; i++)
              SizedBox(width: width, child: itemBuilder(context, i)),
          ],
        );
      },
    ),
  );
}

class SubjectAction {
  const SubjectAction(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// The same actions stay visible on phones and in a sidebar on wider displays.
class SubjectLayout extends StatelessWidget {
  const SubjectLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.child,
    required this.onRefresh,
  });
  final String title;
  final String subtitle;
  final List<SubjectAction> actions;
  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide =
          box.maxWidth >= 1100 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.5;
      final navigation = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Class actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final action in actions)
            ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              onTap: action.onTap,
            ),
        ],
      );
      final content = RefreshIndicator(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 20),
              if (!wide) ...[
                LayoutBuilder(
                  builder: (context, limits) {
                    final columns =
                        limits.maxWidth >= 600 &&
                            MediaQuery.textScalerOf(context).scale(1) <= 1.3
                        ? 2
                        : 1;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final action in actions)
                          SizedBox(
                            width:
                                (limits.maxWidth - 12 * (columns - 1)) /
                                columns,
                            child: OutlinedButton.icon(
                              onPressed: action.onTap,
                              icon: Icon(action.icon),
                              label: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(action.label),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
              child,
            ],
          ),
        ),
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('Class dashboard'),
          actions: [
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) ...[
                SizedBox(width: 248, child: navigation),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: ResponsivePage(maxWidth: 1100, child: content)),
            ],
          ),
        ),
      );
    },
  );
}

class DetailCard extends StatelessWidget {
  const DetailCard({
    super.key,
    required this.title,
    required this.details,
    this.badge,
  });
  final String title;
  final List<String> details;
  final Widget? badge;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdaptiveHeading(
            title: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            action: badge,
          ),
          const SizedBox(height: 12),
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                detail,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    ),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
