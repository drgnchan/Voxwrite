import 'package:flutter/material.dart';

import 'pages/dictionary_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';

enum AppSection { home, history, dictionary, settings }

extension on AppSection {
  String get label => switch (this) {
    AppSection.home => '首页',
    AppSection.history => '历史记录',
    AppSection.dictionary => '词典',
    AppSection.settings => '设置',
  };

  IconData get icon => switch (this) {
    AppSection.home => Icons.home_outlined,
    AppSection.history => Icons.history_rounded,
    AppSection.dictionary => Icons.menu_book_outlined,
    AppSection.settings => Icons.settings_outlined,
  };
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.home;

  Widget get _page => switch (_section) {
    AppSection.home => const HomePage(),
    AppSection.history => const HistoryPage(),
    AppSection.dictionary => const DictionaryPage(),
    AppSection.settings => const SettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          return Scaffold(
            appBar: AppBar(title: const _Brand()),
            body: _page,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _section.index,
              onDestinationSelected: (index) {
                setState(() => _section = AppSection.values[index]);
              },
              destinations: [
                for (final section in AppSection.values)
                  NavigationDestination(
                    icon: Icon(section.icon),
                    label: section.label,
                  ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              Container(
                width: 236,
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: _Brand(),
                    ),
                    const SizedBox(height: 28),
                    for (final section in AppSection.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _NavButton(
                          selected: section == _section,
                          icon: section.icon,
                          label: section.label,
                          onPressed: () => setState(() => _section = section),
                        ),
                      ),
                    const Spacer(),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _page),
            ],
          ),
        );
      },
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'VoxWrite',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Align(alignment: Alignment.centerLeft, child: Text(label)),
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: selected
            ? colors.secondaryContainer
            : Colors.transparent,
        foregroundColor: selected
            ? colors.onSecondaryContainer
            : colors.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
