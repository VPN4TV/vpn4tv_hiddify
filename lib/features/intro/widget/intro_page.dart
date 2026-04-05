import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/connection/vpn_connection_manager.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/providers/device_info_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

class IntroPage extends HookConsumerWidget {
  IntroPage({super.key});

  final String _uuid = Uuid().v4();

  String generate10DigitCode() {
    final rand = Random();
    return List.generate(10, (_) => rand.nextInt(10)).join();
  }

  String format10DigitCode(String code) {
    if (code.length != 10) {
      return code;
    }
    return '${code[0]} ${code.substring(1, 4)} ${code.substring(4, 7)} ${code.substring(7)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final isAndroidTv = ref.watch(isAndroidTvProvider).valueOrNull ?? false;

    final isStarting = useState(false);
    final vpnConfigs = useState<List<dynamic>>([]);
    final userInfo = useState<String?>(null);
    final connectionManagerUuid = useState<VpnConnectionManager?>(null);
    final connectionManagerCode = useState<VpnConnectionManager?>(null);
    final isVpnAdded = useState(false);
    final code10Digit = useState<String>(generate10DigitCode());
    final combinedStatus = useState<String>(t.intro.waitingForQrScan);

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
      if (codeStatus != uuidStatus) {
        combinedStatus.value = '$uuidStatus\n$codeStatus';
      } else {
        combinedStatus.value = uuidStatus;
      }
    }

    Future<void> processConfigs(List<dynamic> configs) async {
      for (final config in configs) {
        if (config is Map<String, dynamic> && config['type'] == 'subscription') {
          await ref.read(addProfileNotifierProvider.notifier).addClipboard(config['url'] as String);
        } else if (config is String) {
          await ref.read(addProfileNotifierProvider.notifier).addClipboard(config);
        } else {
          print('Unsupported config format: $config');
        }
      }
      isVpnAdded.value = true;
      updateCombinedStatus();
    }

    useEffect(() {
      Future<void> initializeSettings() async {
        await ref.read(ConfigOptions.region.notifier).update(Region.ru);
      }

      initializeSettings();
      return null;
    }, []);

    // Force poll when app returns from background (e.g. after opening Telegram)
    useOnAppLifecycleStateChange((previous, current) {
      if (current == AppLifecycleState.resumed && !isVpnAdded.value) {
        connectionManagerUuid.value?.forcePoll();
        connectionManagerCode.value?.forcePoll();
      }
    });

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
          combinedStatus.value = '${t.intro.connectionError}\n${combinedStatus.value.split('\n').last}';
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
          combinedStatus.value = '${combinedStatus.value.split('\n').first}\n${t.intro.connectionError}';
        },
      );

      connectionManagerCode.value!.connect();

      return () {
        connectionManagerCode.value?.disconnect();
      };
    }, [code10Digit.value]);

    useEffect(() {
      if (isVpnAdded.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!isStarting.value) {
            isStarting.value = true;
            ref.read(Preferences.introCompleted.notifier).update(true);
          }
        });
      }
    }, [isVpnAdded.value]);

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.common.appTitle),
        actions: [
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'terms') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WebViewPage(
                      url: Constants.termsAndConditionsUrl,
                      title: t.pages.about.termsAndConditions,
                    ),
                  ),
                );
              } else if (value == 'privacy') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WebViewPage(
                      url: Constants.privacyPolicyUrl,
                      title: t.pages.about.privacyPolicy,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'terms',
                child: Text(t.pages.about.termsAndConditions),
              ),
              PopupMenuItem<String>(
                value: 'privacy',
                child: Text(t.pages.about.privacyPolicy),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: SafeArea(
        child: FocusTraversalGroup(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Center(
                    child: QrImageView(
                      data: 'https://t.me/VPN4TV_Bot?start=$_uuid',
                      version: QrVersions.auto,
                      size: 200.0,
                      foregroundColor: isDarkTheme ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      '${t.intro.enter10DigitCode}: ${format10DigitCode(code10Digit.value)}',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!isAndroidTv)
                    Center(
                      child: ElevatedButton.icon(
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
                    ),
                  if (isAndroidTv)
                    Center(
                      child: Text(
                        t.intro.continueWithBot,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      combinedStatus.value,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (userInfo.value != null) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        userInfo.value!,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    child: Column(
                      children: [
                        if (isVpnAdded.value && !isStarting.value)
                          ElevatedButton(
                            onPressed: () {
                              isStarting.value = true;
                              ref.read(Preferences.introCompleted.notifier).update(true);
                            },
                            child: Text(
                              t.intro.start,
                              textAlign: TextAlign.center,
                            ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size(double.infinity, 48),
                            ),
                          ),
                        if (isVpnAdded.value && !isStarting.value) const SizedBox(height: 16),
                        if (!isStarting.value)
                          TextButton(
                            onPressed: () {
                              isStarting.value = true;
                              ref.read(Preferences.introCompleted.notifier).update(true);
                            },
                            child: Text(
                              t.intro.addProfileLater,
                              textAlign: TextAlign.center,
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: Size(double.infinity, 48),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WebViewPage extends HookWidget {
  final String url;
  final String title;

  const WebViewPage({Key? key, required this.url, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = useState<WebViewController?>(null);

    useEffect(() {
      controller.value = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {},
            onPageStarted: (String url) {},
            onPageFinished: (String url) {},
            onWebResourceError: (WebResourceError error) {
              print('WebView error: ${error.description}');
            },
            onNavigationRequest: (NavigationRequest request) {
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));

      return null;
    }, []);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: controller.value != null ? WebViewWidget(controller: controller.value!) : const Center(child: CircularProgressIndicator()),
    );
  }
}

class RegionDetector {
  /// Returns: 'IR' | 'AF' | 'CN' | 'TR' | 'RU' | 'BR' | 'US'
  static String detect() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset.inMinutes;
    final tz = now.timeZoneName.toLowerCase().trim();

    if (offset == 210) return 'IR';

    if (offset == 270) {
      final (_, country) = _parseLocale();
      return country == 'IR' ? 'IR' : 'AF';
    }

    final fromName = _fromTzName(tz, offset);
    if (fromName != null) return fromName;

    final candidates = _candidatesForOffset(offset);
    if (candidates.isEmpty) return 'US';

    return _resolveByLocale(candidates);
  }

  static String? _fromTzName(String tz, int offset) {
    if (tz.contains('/')) {
      final city = tz.split('/').last.replaceAll(' ', '_');
      final r = _ianaCities[city];
      if (r != null) return r;
    }

    if (tz == 'irst' || tz == 'irdt' || tz.contains('iran')) return 'IR';

    if (tz == 'aft' || tz.contains('afghanistan')) return 'AF';

    if (tz == 'trt' || tz.contains('turkey') || tz.contains('istanbul')) {
      return 'TR';
    }

    if (tz.contains('china') || tz.contains('beijing')) return 'CN';
    if (tz == 'cst' && offset == 480) return 'CN';

    if (_matchesRussiaTz(tz)) return 'RU';

    if (_matchesBrazilTz(tz)) return 'BR';

    return null;
  }

  static bool _matchesRussiaTz(String tz) {
    if (tz.contains('russia') || tz.contains('moscow')) return true;

    const abbrs = {'msk', 'yekt', 'omst', 'krat', 'irkt', 'yakt', 'vlat', 'magt', 'pett', 'sakt', 'sret'};
    if (abbrs.contains(tz)) return true;

    const winKeys = [
      'ekaterinburg',
      'kaliningrad',
      'yakutsk',
      'vladivostok',
      'magadan',
      'sakhalin',
      'kamchatka',
      'astrakhan',
      'saratov',
      'volgograd',
      'altai',
      'tomsk',
      'transbaikal',
      'n. central asia',
      'north asia',
    ];
    return winKeys.any(tz.contains);
  }

  static bool _matchesBrazilTz(String tz) {
    if (tz == 'brt' || tz == 'brst') return true;
    if (tz.contains('brazil') || tz.contains('brasilia')) return true;

    const winKeys = ['e. south america', 'central brazilian', 'tocantins', 'bahia'];
    return winKeys.any(tz.contains);
  }

  static Set<String> _candidatesForOffset(int offset) {
    final c = <String>{};

    if (offset == 180) c.add('TR');

    if (offset == 480) c.add('CN');

    if (_ruOffsets.contains(offset)) c.add('RU');

    if (_brOffsets.contains(offset)) c.add('BR');

    return c;
  }

  static const _ruOffsets = {120, 180, 240, 300, 360, 420, 480, 540, 600, 660, 720};

  static const _brOffsets = {-120, -180, -240, -300};

  static String _resolveByLocale(Set<String> candidates) {
    final (lang, country) = _parseLocale();

    if (country != null && candidates.contains(country)) {
      return country;
    }

    final regionFromLang = _langToRegion[lang];
    if (regionFromLang != null && candidates.contains(regionFromLang)) {
      return regionFromLang;
    }

    return 'US';
  }

  static (String, String?) _parseLocale() {
    try {
      final parts = Platform.localeName.split(RegExp(r'[_\-.]'));
      final lang = parts.first.toLowerCase();

      String? country;
      for (final p in parts.skip(1)) {
        if (p.length == 2) {
          country = p.toUpperCase();
          break;
        }
      }

      return (lang, country);
    } catch (_) {
      return ('en', null);
    }
  }

  static const _langToRegion = <String, String>{'fa': 'IR', 'ps': 'AF', 'tr': 'TR', 'zh': 'CN', 'ru': 'RU', 'pt': 'BR'};

  static const _ianaCities = <String, String>{
    'tehran': 'IR',
    'kabul': 'AF',
    'istanbul': 'TR',
    'shanghai': 'CN',
    'chongqing': 'CN',
    'urumqi': 'CN',
    'harbin': 'CN',
    'moscow': 'RU',
    'kaliningrad': 'RU',
    'samara': 'RU',
    'yekaterinburg': 'RU',
    'omsk': 'RU',
    'novosibirsk': 'RU',
    'barnaul': 'RU',
    'tomsk': 'RU',
    'krasnoyarsk': 'RU',
    'irkutsk': 'RU',
    'chita': 'RU',
    'yakutsk': 'RU',
    'vladivostok': 'RU',
    'magadan': 'RU',
    'sakhalin': 'RU',
    'kamchatka': 'RU',
    'anadyr': 'RU',
    'volgograd': 'RU',
    'saratov': 'RU',
    'astrakhan': 'RU',
    'sao_paulo': 'BR',
    'fortaleza': 'BR',
    'recife': 'BR',
    'manaus': 'BR',
    'belem': 'BR',
    'cuiaba': 'BR',
    'bahia': 'BR',
    'rio_branco': 'BR',
    'noronha': 'BR',
    'porto_velho': 'BR',
    'campo_grande': 'BR',
  };
}
