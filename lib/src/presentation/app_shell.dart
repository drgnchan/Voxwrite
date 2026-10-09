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
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          return Scaffold(
            appBar: AppBar(title: const _Brand()),
            body: _page,
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: NavigationBar(
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
            ),
          );
        }

        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 208,
                color: colors.surfaceContainerLow,
                padding: const EdgeInsets.fromLTRB(12, 32, 12, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: _Brand(),
                    ),
                    const SizedBox(height: 32),
                    for (final section in AppSection.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
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
    return Text(
      'VoxWrite',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
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
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    const radius = BorderRadius.all(Radius.circular(8));
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.surfaceContainerHigh : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
