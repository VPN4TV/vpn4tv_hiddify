import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/vpn_connection_manager.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/providers/device_info_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

class AddConfigPage extends HookConsumerWidget {
  AddConfigPage({Key? key}) : super(key: key);

  final String _uuid = const Uuid().v4();

  String generate10DigitCode() {
    final rand = Random();
    return List.generate(10, (_) => rand.nextInt(10)).join();
  }

  String format10DigitCode(String code) {
    if (code.length != 10) {
      return code; // Возвращаем исходный код, если он не 10-значный
    }
    return '${code[0]} ${code.substring(1, 4)} ${code.substring(4, 7)} ${code.substring(7)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isAndroidTv = ref.watch(isAndroidTvProvider).valueOrNull ?? false;
    final vpnConfigs = useState<List<dynamic>>([]);
    final userInfo = useState<String?>(null);
    final connectionManagerUuid = useState<VpnConnectionManager?>(null);
    final connectionManagerCode = useState<VpnConnectionManager?>(null);
    final isVpnAdded = useState(false);
    final code10Digit = useState<String>(generate10DigitCode());
    final combinedStatus = useState<String>(t.intro.waitingForQrScan);

    // Force poll when app returns from background (after opening Telegram)
    useOnAppLifecycleStateChange((previous, current) {
      if (current == AppLifecycleState.resumed && !isVpnAdded.value) {
        connectionManagerUuid.value?.forcePoll();
        connectionManagerCode.value?.forcePoll();
      }
    });

    void updateCombinedStatus() {
      String uuidStatus = connectionManagerUuid.value == null
          ? t.intro.waitingForQrScan
          : isVpnAdded.value
              ? t.intro.vpnSetupComplete
              : userInfo.value != null
                  ? t.intro.userInfoReceived
                  : t.intro.waitingForQrScan;

      String codeStatus = connectionManagerCode.value == null
          ? t.intro.waitingForCodeInput
          : isVpnAdded.value
              ? t.intro.vpnSetupComplete
              : userInfo.value != null
                  ? t.intro.userInfoReceived
                  : t.intro.waitingForCodeInput;

      combinedStatus.value = '$uuidStatus\n$codeStatus';
    }

    Future<void> processConfigs(List<dynamic> configs) async {
      for (final config in configs) {
        if (config is Map<String, dynamic> && config['type'] == 'subscription') {
          await ref.read(addProfileNotifierProvider.notifier).addClipboard(config['url'] as String);
        } else if (config is String) {
          await ref.read(addProfileNotifierProvider.notifier).addClipboard(config);
        } else {
          print('Неподдерживаемый формат конфигурации: $config');
        }
      }
      isVpnAdded.value = true;
      updateCombinedStatus();
      Navigator.of(context).pop();
    }

    useEffect(() {
      connectionManagerUuid.value = VpnConnectionManager(
        uuid: _uuid,
        onMessage: (dynamic message) async {
          if (message['type'] == 'user_info') {
            userInfo.value = '${message['data']['first_name']} ${message['data']['last_name']}';
            updateCombinedStatus();
          } else if (message['type'] == 'vpn_config_processed') {
            final configs = message['config'] as List<dynamic>;
            vpnConfigs.value = configs;
            updateCombinedStatus();
            await processConfigs(configs);
          }
        },
        onError: (error) {
          print('Connection error UUID: $error');
          combinedStatus.value = '${t.intro.connectionError}: $error\n${combinedStatus.value.split('\n').last}';
        },
      );

      connectionManagerUuid.value!.connect();

      return () {
        connectionManagerUuid.value?.disconnect();
      };
    }, []);

    useEffect(() {
      connectionManagerCode.value = VpnConnectionManager(
        uuid: code10Digit.value,
        onMessage: (dynamic message) async {
          if (message['type'] == 'user_info') {
            userInfo.value = '${message['data']['first_name']} ${message['data']['last_name']}';
            updateCombinedStatus();
          } else if (message['type'] == 'vpn_config_processed') {
            final configs = message['config'] as List<dynamic>;
            vpnConfigs.value = configs;
            updateCombinedStatus();
            await processConfigs(configs);
          }
        },
        onError: (error) {
          print('Connection error Code: $error');
          combinedStatus.value = '${combinedStatus.value.split('\n').first}\n${t.intro.connectionError}: $error';
        },
      );

      connectionManagerCode.value!.connect();

      return () {
        connectionManagerCode.value?.disconnect();
      };
    }, [code10Digit.value]);

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.profiles.add),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                QrImageView(
                  data: 'https://t.me/VPN4TV_Bot?start=$_uuid',
                  version: QrVersions.auto,
                  size: 200.0,
                  foregroundColor: isDarkTheme ? Colors.white : Colors.black,
                ),
                const SizedBox(height: 20),
                Text(t.intro.scanQrCodePrompt),
                const SizedBox(height: 20),
                Text(t.intro.or, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 20),
                Text(
                  '${t.intro.enter10DigitCode}: ${format10DigitCode(code10Digit.value)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                if (!isAndroidTv)
                  ElevatedButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse('https://t.me/VPN4TV_Bot?start=$_uuid'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.send),
                    label: Text(t.intro.addProfileViaTelegram),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                if (isAndroidTv)
                  Text(t.intro.continueWithBot),
                const SizedBox(height: 20),
                Text(combinedStatus.value),
                if (userInfo.value != null) ...[
                  const SizedBox(height: 20),
                  Text(userInfo.value!),
                ],
                if (isVpnAdded.value) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.common.ok),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
