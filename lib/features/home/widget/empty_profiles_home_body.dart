import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/features/add_config/add_config_page.dart';
import 'package:hiddify/providers/device_info_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EmptyProfilesHomeBody extends HookConsumerWidget {
  const EmptyProfilesHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isAndroidTvAsync = ref.watch(isAndroidTvProvider);

    return SliverFillRemaining(
      hasScrollBody: false,
      child: isAndroidTvAsync.when(
        data: (isAndroidTv) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(t.pages.profiles.add),
            const SizedBox(height: 16),
            if (!isAndroidTv)
              OutlinedButton.icon(
                onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                icon: const Icon(Icons.add),
                label: Text(t.pages.profiles.add),
                autofocus: true,
              ),
            if (!isAndroidTv) const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddConfigPage())),
              icon: const Icon(Icons.add),
              label: Text(t.intro.addProfileViaTelegram),
              autofocus: isAndroidTv,
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const Center(child: Text('An error occurred')),
      ),
    );
  }
}
