import 'package:flutter/material.dart';

import 'settings_options.dart';

String settingsText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

void showSettingsSaveError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        settingsText(
          context,
          '无法保存配置，请重试。',
          'Could not save preferences. Try again.',
        ),
      ),
    ),
  );
}

final class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.title,
    required this.groups,
    this.embedded = false,
    super.key,
  });

  final String title;
  final List<SettingsGroup> groups;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: embedded,
      child: LayoutBuilder(
        builder: (context, box) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          final maxColumns = largeText || box.maxWidth < 650
              ? 1
              : box.maxWidth < 960
              ? 2
              : 3;
          final compact = maxColumns == 1;
          final columns = groups.length.clamp(1, maxColumns);
          final width = compact ? 640.0 : double.infinity;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              12,
              18,
              32 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (embedded) ...[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                    ],
                    LayoutBuilder(
                      builder: (context, available) => Wrap(
                        spacing: 16,
                        runSpacing: compact ? 24 : 16,
                        children: [
                          for (final group in groups)
                            SizedBox(
                              width:
                                  (available.maxWidth - (columns - 1) * 16) /
                                  columns,
                              child: _SettingsGroupCard(
                                group,
                                compact: compact,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (embedded) return content;
    return Scaffold(
      appBar: AppBar(title: Text(title), surfaceTintColor: Colors.transparent),
      body: content,
    );
  }
}

final class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard(this.group, {required this.compact});

  final SettingsGroup group;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final icon = IconTheme.merge(
      data: IconThemeData(
        size: compact ? 18 : 23,
        color: compact ? colors.onPrimaryContainer : colors.primary,
      ),
      child: group.leading ?? Icon(group.icon),
    );
    final title = Row(
      children: [
        if (compact)
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: icon,
          )
        else
          icon,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            group.title(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    final panel = Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 16 : 13),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(compact ? 4 : 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[title, const SizedBox(height: 13)],
            for (final entry in group.entries)
              Builder(key: ValueKey(entry.id), builder: entry.builder),
          ],
        ),
      ),
    );
    if (!compact) return panel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [title, const SizedBox(height: 10), panel],
    );
  }
}
