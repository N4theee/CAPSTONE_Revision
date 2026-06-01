import 'package:flutter/material.dart';

/// Shared text, date formatting, and MCQ choice styling for exam screens only.
class ExamUi {
  ExamUi._();

  static const List<String> choiceLetters = ['A', 'B', 'C', 'D'];

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Local device time, e.g. `June 2, 2026 - 3:45 PM`.
  static String formatExamDateTime(DateTime? dateTime) {
    if (dateTime == null) return '—';
    final local = dateTime.toLocal();
    if (local.year < 2000) return '—';

    final month = _monthNames[local.month - 1];
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    return '$month ${local.day}, ${local.year} - $hour12:$minute $amPm';
  }

  static TextStyle? titleMedium(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          );

  static TextStyle? body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          );

  static TextStyle? bodySecondary(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: 0.65,
                ),
          );

  static TextStyle? labelOnCard(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: 0.75,
                ),
          );

  /// Letter + choice text with readable contrast on dark cards.
  static Widget mcqChoiceTile({
    required BuildContext context,
    required String letter,
    required String choiceText,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    final selectedBg = scheme.primary.withValues(alpha: 0.22);
    final unselectedBg = scheme.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.35 : 1.0,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? selectedBg : unselectedBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? scheme.primary : theme.dividerColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: selected
                    ? scheme.primary
                    : onSurface.withValues(alpha: 0.14),
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? scheme.onPrimary : onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  choiceText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSurface,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    height: 1.35,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 20, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  static String choiceLetterForOrder(int choiceOrder) {
    final index = (choiceOrder - 1).clamp(0, choiceLetters.length - 1);
    return choiceLetters[index];
  }
}
