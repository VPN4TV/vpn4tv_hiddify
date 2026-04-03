import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EmptyActiveProfileHomeBody extends HookConsumerWidget {
  const EmptyActiveProfileHomeBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Text(t.pages.profiles.add),
      ),
    );
  }
}
