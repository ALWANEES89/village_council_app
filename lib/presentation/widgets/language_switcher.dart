import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../providers/locale_provider.dart';

class LanguageSwitcher extends ConsumerWidget {
  const LanguageSwitcher({
    super.key,
    this.compact = false,
    this.foregroundColor,
  });

  final bool compact;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Tooltip(
      message: AppLocalizations.of(context).language,
      child: TextButton.icon(
        onPressed: () => _showLanguages(context, ref),
        icon: const Icon(Icons.language, size: 20),
        label: Text(locale.languageCode.toUpperCase()),
        style: TextButton.styleFrom(
          foregroundColor:
              foregroundColor ?? Theme.of(context).colorScheme.onSurface,
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 8)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Future<void> _showLanguages(BuildContext context, WidgetRef ref) async {
    final strings = AppLocalizations.of(context);
    final current = ref.read(localeProvider).languageCode;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  strings.selectLanguage,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              ListTile(
                title: Text(strings.arabic),
                trailing: current == 'ar' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, 'ar'),
              ),
              ListTile(
                title: Text(strings.english),
                trailing: current == 'en' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, 'en'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await ref.read(localeProvider.notifier).setLocale(Locale(selected));
    }
  }
}
