import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/router.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/providers/device_info_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EmptyProfilesHomeBody extends HookConsumerWidget {
  const EmptyProfilesHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final isAndroidTvAsync = ref.watch(isAndroidTvProvider);

    return SliverFillRemaining(
      hasScrollBody: false,
      child: isAndroidTvAsync.when(
        data: (isAndroidTv) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(t.home.emptyProfilesMsg),
            const SizedBox(height: 16),
            if (!isAndroidTv)
              OutlinedButton.icon(
                onPressed: () => const AddProfileRoute().push(context),
                icon: const Icon(Icons.add),
                label: Text(t.profile.add.buttonText),
                autofocus: true,
              ),
            if (!isAndroidTv) const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => const AddConfigRoute().push(context),
              icon: const Icon(Icons.add),
              label: Text(t.home.addProfileViaTelegram),
              autofocus: isAndroidTv,
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(t.general.errorOccurred)),
      ),
    );
  }
}
