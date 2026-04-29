import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../providers/app_text_provider.dart';
import '../providers/language_provider.dart';

class LanguagePickerButton extends ConsumerWidget {
  final Color? color;
  const LanguagePickerButton({super.key, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider).language;
    return IconButton(
      icon: Icon(Icons.language, color: color),
      tooltip: ref.watch(appTextProvider(('select_language', 'Select Language'))),
      onPressed: () => _showLanguagePicker(context, ref, language),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, String currentLanguage) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text(ref.watch(appTextProvider(('select_language', 'Select Language'))),
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          ...supportedLanguages.map((lang) => ListTile(
                title: Text(lang),
                trailing: lang == currentLanguage
                    ? const Icon(Icons.check, color: AppTheme.primaryColor)
                    : null,
                onTap: () {
                  ref.read(languageProvider.notifier).setLanguage(lang);
                  Navigator.pop(context);
                },
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
