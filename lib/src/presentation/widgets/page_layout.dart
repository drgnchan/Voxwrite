import 'package:flutter/material.dart';

/// Centers page content in a readable column with responsive gutters.
class PageFrame extends StatelessWidget {
  const PageFrame({required this.child, this.scrollable = false, super.key});

  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final padding = EdgeInsets.symmetric(
          horizontal: compact ? 20 : 48,
          vertical: compact ? 20 : 40,
        );
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        );
        if (scrollable) {
          return SingleChildScrollView(
            padding: padding,
            child: Center(child: content),
          );
        }
        return Padding(
          padding: padding,
          child: Align(alignment: Alignment.topCenter, child: content),
        );
      },
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.description,
    this.action,
    super.key,
  });

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            ?action,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
