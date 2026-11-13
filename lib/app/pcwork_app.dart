import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../design_system/pcwork_design_system.dart';
import '../screens/repair_protocol_screen.dart';
import '../screens/repair_evidence_screen.dart';
import '../screens/repair_documents_screen.dart';
import '../screens/repair_worklog_screen.dart';
import '../screens/repair_parts_screen.dart';
import '../screens/repair_checklist_screen.dart';
import '../screens/contact_hub_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/shop_screen.dart';
import '../screens/notification_history_screen.dart';
import '../screens/customer_center_screen.dart';
import '../screens/visitor_analytics_screen.dart';
import '../screens/cache_monitor_screen.dart';
import '../screens/device_monitor_screen.dart';
import '../screens/internal_service_assistant_screen.dart';
import '../screens/beach_game_screen.dart';
import '../screens/booking_screen.dart';
import '../screens/ai_assistant_chat_screen.dart';
import '../screens/sync_center_screen.dart';

class PCWorkApp extends StatefulWidget {
  const PCWorkApp({super.key, this.initialPreferences});

  final SharedPreferences? initialPreferences;

  @override
  State<PCWorkApp> createState() => _PCWorkAppState();
}

class _PCWorkAppState extends State<PCWorkApp> with WidgetsBindingObserver {
  static const cyan = Color(0xFF21D4D8);
  static const defaultApi = 'https://pcwork-bg.com';
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool english = false;
  String languageMode = 'auto';
  bool isDarkTheme = true;
  bool staffPreview = false;
  bool clientPreview = false;
  bool noRegPreview = false;
  int tab = 0;
  bool _settingsOpen = false;
  final Set<int> _visitedTabs = <int>{0};
  final List<int> _tabBackStack = <int>[];
  String apiUrl = defaultApi;
  bool apiReady = false;
  bool checkingApi = false;
  String? apiMessage;
  AuthUser? signedInUser;
  bool authBusy = false;
  Future<List<Repair>>? repairsFuture;
  final TextEditingController repairSearch = TextEditingController();
  String repairStatusFilter = 'all';
  ServiceLocation? selectedLocation;
  Timer? _offlineSyncTimer;
  Timer? _appUpdateCheckTimer;
  bool _syncingOfflineQueue = false;
  bool _autoSyncEnabled = true;
  int _pendingSyncCount = 0;
  bool _marketingOptIn = false;
  bool _marketingPreferenceLoaded = false;
  String? _pushStatusMessage;
  bool _pushRegistering = false;
  bool _pushDialogShowing = false;
  final Set<String> _marketingCampaignsHandled = <String>{};
  bool _refreshingOnTabExit = false;
  bool _returnToCustomerCenterOnBack = false;
  Map<String, dynamic>? _appUpdateInfo;
  // Keep this in sync with the build number in pubspec.yaml.
  static const int _currentBuildNumber = int.fromEnvironment('PCWORK_BUILD_NUMBER', defaultValue: 161);
  static const MethodChannel _updaterChannel = MethodChannel('com.pcworkbg.pcwork_mobile/updater');
  static const MethodChannel _phoneChannel = MethodChannel('com.pcworkbg.pcwork_mobile/phone');
  bool _installingUpdate = false;
  List<Map<String, dynamic>> _notificationHistory = <Map<String, dynamic>>[];
  int? _pendingShopOrderId;
  bool _openShopOrdersOnEntry = false;
  int get _unreadNotificationCount => _notificationHistory.where((item) => item['read'] != true).length;

  AuthService get auth => AuthService(baseUrl: apiUrl);
  PushNotificationService get push => PushNotificationService(baseUrl: apiUrl);
  ApiService get api => ApiService(baseUrl: apiUrl, userId: noRegPreview ? 0 : (signedInUser?.id ?? 0), clientBuild: _currentBuildNumber);
  String tr(String bg, String en) => english ? en : bg;
  AuthUser? get visibleUser => noRegPreview ? null : signedInUser;
  bool get isAdministrator => signedInUser?.roles.contains('administrator') ?? false;
  bool get canUseAdminChat => !noRegPreview && (signedInUser?.roles.any((r) => ['administrator', 'shop_manager', 'pcwork_staff'].contains(r)) ?? false);
  bool get isStaffAccount => !noRegPreview && (signedInUser?.roles.any((r) => ['administrator', 'pcwork_staff', 'shop_manager', 'editor'].contains(r)) ?? false);
  bool get isCustomerAccount {
    if (noRegPreview) return false;
    const allowedCustomerRoles = {'pcwork_customer', 'customer', 'subscriber'};
    final roles = signedInUser?.roles ?? const <String>[];
    return roles.isNotEmpty && roles.every(allowedCustomerRoles.contains);
  }
  bool get showStaffPreview => isAdministrator && staffPreview && !clientPreview;
  bool get showClientPreview => isAdministrator && clientPreview;
  bool get canSeeStaffUi => !noRegPreview && ((isStaffAccount && !showClientPreview) || showStaffPreview);
  Future<String?> _uiToken() async => noRegPreview ? null : await auth.token;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Apply persisted theme/language before the first frame to avoid the
    // brief default-theme flash while asynchronous settings are being loaded.
    final prefs = widget.initialPreferences;
    if (prefs != null) {
      apiUrl = prefs.getString('pcwork_api_url') ?? defaultApi;
      final storedLanguageMode = prefs.getString('pcwork_language_mode');
      final fallbackLanguageMode = prefs.getBool('pcwork_english') == true ? 'en' : 'auto';
      languageMode = ['auto', 'bg', 'en'].contains(storedLanguageMode)
          ? storedLanguageMode!
          : fallbackLanguageMode;
      final systemEnglish = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase() == 'en';
      english = languageMode == 'auto' ? systemEnglish : languageMode == 'en';
      isDarkTheme = prefs.getBool('pcwork_dark_theme') ?? true;
      staffPreview = prefs.getBool('pcwork_staff_preview') ?? false;
      clientPreview = prefs.getBool('pcwork_client_preview') ?? false;
      noRegPreview = prefs.getBool('pcwork_no_reg_preview') ?? false;
      _autoSyncEnabled = prefs.getBool('pcwork_auto_sync_enabled') ?? true;
      final savedCode = prefs.getString('pcwork_selected_location') ?? '';
      selectedLocation = savedCode.isEmpty
          ? null
          : ServiceLocation(
              name: prefs.getString('pcwork_selected_location_name') ?? '',
              code: savedCode,
              address: prefs.getString('pcwork_selected_location_address') ?? '',
              imageUrl: prefs.getString('pcwork_selected_location_image') ?? '',
              imageCaption: prefs.getString('pcwork_selected_location_image_caption') ?? '',
              hours: prefs.getString('pcwork_selected_location_hours') ?? '',
              mapsUrl: prefs.getString('pcwork_selected_location_maps') ?? '',
            );
    }
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSettings();
    await _loadNotificationHistory();
    if (!mounted) return;
    // Do not make the server health check a startup dependency.
    // Restore the account immediately; the status check runs independently.
    unawaited(_checkApi(silent: true));
    // Ask the operating system directly on first launch/update. Android keeps
    // an existing grant across app updates; in that case no second dialog is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _requestSystemNotifications();
      if (mounted) unawaited(_restoreSession());
    });
    unawaited(_checkForAppUpdate());
    _appUpdateCheckTimer?.cancel();
    _appUpdateCheckTimer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(_checkForAppUpdate()));
  }

  Future<void> _restoreSession() async {
    try { final t = await auth.token; if (t != null) { final u = await auth.me(); if (mounted) setState(() { signedInUser = u; repairsFuture = _loadRepairsFuture(); });
      unawaited(_loadMarketingPreference(t));
      unawaited(_enablePush(knownToken: t));
      _startOfflineSync(t); } } catch (_) { if (mounted) setState(() => signedInUser = null); }
  }

  Future<void> _checkForAppUpdate() async {
    try {
      final info = await api.getAppUpdateInfo();
      if (!mounted) return;
      final availableBuild = int.tryParse((info?['version_code'] ?? '').toString()) ?? 0;
      final update = availableBuild > _currentBuildNumber ? info : null;
      setState(() => _appUpdateInfo = update);
    } catch (_) {
      // Update checks are optional and must never block app startup.
    }
  }

  Future<void> _openVisitorAnalytics() async {
    final token = await auth.token;
    if (!mounted) return;
    if (token == null || token.isEmpty || !isAdministrator) {
      _message(tr('Достъпът е разрешен само за администратори.', 'Administrator access only.'));
      return;
    }
    await _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => VisitorAnalyticsScreen(api: api, token: token, english: english),
    ));
  }

  Future<void> _openCacheMonitor() async {
    final token = await auth.token;
    if (!mounted) return;
    if (token == null || token.isEmpty || !isAdministrator) {
      _message(tr('Достъпът е разрешен само за администратори.', 'Administrator access only.'));
      return;
    }
    await _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => CacheMonitorScreen(api: api, token: token, english: english),
    ));
  }

  Future<void> _downloadAndInstallUpdate() async {
    final info = _appUpdateInfo;
    if (info == null || _installingUpdate) return;
    setState(() => _installingUpdate = true);
    try {
      final path = await api.downloadAndVerifyUpdate(info);
      await _updaterChannel.invokeMethod<bool>('installApk', {'path': path});
    } on PlatformException catch (e) {
      _message(e.message ?? tr('Android не успя да стартира инсталацията.', 'Android could not start the installer.'));
    } catch (e) {
      _message('${tr('Актуализацията не бе инсталирана:', 'Update could not be installed:')} $e');
    } finally {
      if (mounted) setState(() => _installingUpdate = false);
    }
  }

  Widget _appUpdateBanner() {
    final info = _appUpdateInfo;
    if (info == null) return const SizedBox.shrink();
    final version = (info['version'] ?? '').toString();
    final notes = (info['release_notes'] ?? '').toString().trim();
    final url = Uri.tryParse((info['apk_url'] ?? '').toString());
    final checksum = (info['sha256'] ?? '').toString().toLowerCase();
    final canInstall = RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum);
    return Card(
      color: isDarkTheme ? const Color(0xFF163342) : const Color(0xFFE5F7F7),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.system_update_alt_rounded, color: cyan), const SizedBox(width: 9), Expanded(child: Text(tr('Налична е нова версия', 'A new version is available'), style: const TextStyle(fontWeight: FontWeight.w800)))]),
          if (version.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('PCWork Mobile $version')),
          if (notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 7), child: Text(notes, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDarkTheme ? Colors.white70 : Colors.black54))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: url != null && url.scheme == 'https' && canInstall && !_installingUpdate ? _downloadAndInstallUpdate : null,
            icon: const Icon(Icons.download_rounded),
            label: Text(_installingUpdate ? tr('Изтегляне и проверка…', 'Downloading and verifying…') : tr('Актуализирай сега', 'Update now')),
          )),
          if (url == null || url.scheme != 'https') Padding(padding: const EdgeInsets.only(top: 7), child: Text(tr('Известието е налично, но липсва HTTPS адрес към APK файла в WordPress.', 'Update is detected, but the HTTPS APK URL is missing in WordPress.'))),
          if (!canInstall) Padding(padding: const EdgeInsets.only(top: 7), child: Text(tr('Изтеглянето е блокирано: липсва валидна SHA-256 сума в настройките на WordPress.', 'Download is blocked: a valid SHA-256 checksum is missing from WordPress settings.'), style: const TextStyle(fontSize: 11, color: Colors.orange))),
          Text(tr('Инсталирането се потвърждава от Android. Не се извършва тиха инсталация.', 'Android will ask you to confirm installation. Silent installation is not performed.'), style: TextStyle(fontSize: 11, color: isDarkTheme ? Colors.white54 : Colors.black54)),
        ]),
      ),
    );
  }

  Future<void> _loadMarketingPreference(String bearer) async {
    try {
      final enabled = await push.getMarketingConsent(bearer);
      if (mounted) setState(() { _marketingOptIn = enabled; _marketingPreferenceLoaded = true; });
    } catch (_) { if (mounted) setState(() => _marketingPreferenceLoaded = true); }
  }

  Future<void> _setMarketingPreference(bool enabled) async {
    final bearer = await auth.token;
    if (bearer == null || bearer.isEmpty) return;
    final previous = _marketingOptIn;
    setState(() => _marketingOptIn = enabled);
    try {
      await push.setMarketingConsent(bearer, enabled);
      _message(enabled
          ? tr('Съгласието за промоционални известия е записано.', 'Marketing notification consent saved.')
          : tr('Отписахте се от промоционални известия.', 'You unsubscribed from marketing notifications.'));
    } catch (e) {
      if (mounted) setState(() => _marketingOptIn = previous);
      _message('${tr('Неуспешно записване:', 'Could not save:')} $e');
    }
  }


  Future<void> _checkNotificationStatus({bool showMessage = false}) async {
    final bearer = await auth.token;
    if (bearer == null || bearer.isEmpty) {
      if (mounted) setState(() => _pushStatusMessage = tr('Влезте в профила си, за да проверите регистрацията на устройството.', 'Sign in to check device registration.'));
      return;
    }
    try {
      final status = await push.getDiagnostics(bearer);
      final permission = (status['permission'] ?? 'unknown').toString();
      final registered = status['device_registered'] == true;
      final configured = status['firebase_configured'] == true;
      final pushEnabled = status['push_enabled'] == true;
      final marketing = status['marketing_opt_in'] == true;
      final message = tr(
        'Android: ${permission == 'granted' ? 'Разрешено' : permission == 'denied' ? 'Забранено' : 'Неизвестно'} · Firebase: ${configured ? 'Конфигуриран' : 'Непроверен/изключен'} · Push: ${pushEnabled ? 'Включен' : 'Изключен'} · Устройство: ${registered ? 'Регистрирано' : 'Нерегистрирано'} · Промоции: ${marketing ? 'Включени' : 'Изключени'}',
        'Android: ${permission == 'granted' ? 'Allowed' : permission == 'denied' ? 'Denied' : 'Unknown'} · Firebase: ${configured ? 'Configured' : 'Not configured/disabled'} · Push: ${pushEnabled ? 'Enabled' : 'Disabled'} · Device: ${registered ? 'Registered' : 'Not registered'} · Promotions: ${marketing ? 'On' : 'Off'}');
      if (mounted) setState(() => _pushStatusMessage = message);
      if (showMessage) _message(message);
    } catch (e) {
      if (mounted) setState(() => _pushStatusMessage = '${tr('Проверката не успя:', 'Status check failed:')} $e');
      if (showMessage) _message('${tr('Проверката не успя:', 'Status check failed:')} $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final storedLanguageMode = prefs.getString('pcwork_language_mode');
    final fallbackLanguageMode = prefs.getBool('pcwork_english') == true ? 'en' : 'auto';
    final resolvedLanguageMode = ['auto', 'bg', 'en'].contains(storedLanguageMode) ? storedLanguageMode! : fallbackLanguageMode;
    setState(() {
      apiUrl = prefs.getString('pcwork_api_url') ?? defaultApi;
      languageMode = resolvedLanguageMode;
      final systemEnglish = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase() == 'en';
      english = languageMode == 'auto' ? systemEnglish : languageMode == 'en';
      isDarkTheme = prefs.getBool('pcwork_dark_theme') ?? true;
      staffPreview = prefs.getBool('pcwork_staff_preview') ?? false;
      clientPreview = prefs.getBool('pcwork_client_preview') ?? false;
      noRegPreview = prefs.getBool('pcwork_no_reg_preview') ?? false;
      _autoSyncEnabled = prefs.getBool('pcwork_auto_sync_enabled') ?? true;
      final savedCode = prefs.getString('pcwork_selected_location') ?? '';
      selectedLocation = savedCode.isEmpty ? null : ServiceLocation(
        name: prefs.getString('pcwork_selected_location_name') ?? '',
        code: savedCode,
        address: prefs.getString('pcwork_selected_location_address') ?? '',
        imageUrl: prefs.getString('pcwork_selected_location_image') ?? '',
        imageCaption: prefs.getString('pcwork_selected_location_image_caption') ?? '',
        hours: prefs.getString('pcwork_selected_location_hours') ?? '',
        mapsUrl: prefs.getString('pcwork_selected_location_maps') ?? '',
      );
    });
  }

  Future<void> _savePreference(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
  }

  Future<void> _saveLocationPreference(ServiceLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pcwork_selected_location', location.code);
    await prefs.setString('pcwork_selected_location_name', location.name);
    await prefs.setString('pcwork_selected_location_address', location.address);
    await prefs.setString('pcwork_selected_location_image', location.imageUrl);
    await prefs.setString('pcwork_selected_location_image_caption', location.imageCaption);
    await prefs.setString('pcwork_selected_location_hours', location.hours);
    await prefs.setString('pcwork_selected_location_maps', location.mapsUrl);
  }

  Future<void> _saveApiUrl(String value) async {
    final cleaned = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null || uri.host.isEmpty || uri.scheme != 'https') {
      throw Exception(tr('Въведете валиден адрес, започващ с https://', 'Enter a valid https:// URL.'));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pcwork_api_url', cleaned);
    setState(() { apiUrl = cleaned; apiReady = false; });
  }

  Future<void> _checkApi({bool silent = false}) async {
    setState(() { checkingApi = true; if (!silent) apiMessage = null; });
    try {
      await api.checkHealth();
      if (!mounted) return;
      setState(() { apiReady = true; apiMessage = tr('Връзката с PCWork сървъра е успешна.', 'Connected to the PCWork server.'); });
    } catch (e) {
      if (!mounted) return;
      setState(() { apiReady = false; apiMessage = tr('Няма връзка със сървъра: $e', 'Server connection failed: $e'); });
    } finally { if (mounted) setState(() => checkingApi = false); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadNotificationHistory());
      if (_autoSyncEnabled) unawaited(_syncOfflineQueue());
      // Refresh the public release manifest when the app returns to foreground.
      unawaited(_checkForAppUpdate());
      // Re-check FCM registration when the app returns from system settings.
      if (signedInUser != null) unawaited(_retryPushRegistration());
    }
  }

  void _startOfflineSync(String token) {
    _offlineSyncTimer?.cancel();
    unawaited(_refreshPendingSyncCount(token));
    if (!_autoSyncEnabled) return;
    unawaited(_syncOfflineQueue());
    _offlineSyncTimer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(_syncOfflineQueue()));
  }

  Future<void> _setAutoSyncEnabled(bool enabled) async {
    if (!mounted) return;
    setState(() => _autoSyncEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pcwork_auto_sync_enabled', enabled);
    _offlineSyncTimer?.cancel();
    if (enabled) {
      final token = await auth.token;
      if (token != null && token.isNotEmpty) _startOfflineSync(token);
    }
  }

  Future<void> _refreshPendingSyncCount(String token) async {
    try {
      final count = await api.pendingOperationCount(token);
      if (mounted) setState(() => _pendingSyncCount = count);
    } catch (_) {
      // A local secure-storage read failure must not crash background startup.
    }
  }

  Future<void> _syncOfflineQueue() async {
    if (_syncingOfflineQueue) return;
    final token = await auth.token;
    if (token == null || token.isEmpty) return;
    _syncingOfflineQueue = true;
    try {
      final sent = await api.syncPendingOperations(token);
      final count = await api.pendingOperationCount(token);
      if (!mounted) return;
      setState(() { _pendingSyncCount = count; if (sent > 0) repairsFuture = _loadRepairsFuture(); });
      if (sent > 0 && count == 0) _message(tr('Офлайн операциите са синхронизирани.', 'Offline operations have been synchronized.'));
    } catch (_) {
      // Failed requests remain in the queue and are retried on the next cycle.
    } finally { _syncingOfflineQueue = false; }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineSyncTimer?.cancel();
    _appUpdateCheckTimer?.cancel();
    repairSearch.dispose();
    super.dispose();
  }


  Future<void> _loadNotificationHistory() async {
    var records = await PushNotificationService.loadNotificationHistory();
    if (mounted) setState(() => _notificationHistory = records);
    if (signedInUser != null && !noRegPreview) {
      try {
        final bearer = await auth.token;
        if (bearer != null && bearer.isNotEmpty) {
          records = await push.syncNotificationHistory(bearer);
          if (mounted) setState(() => _notificationHistory = records);
        }
      } catch (_) {
        // The local inbox remains available when the server is temporarily offline.
      }
    }
  }

  Future<void> _openNotifications() async {
    final readRecords = _notificationHistory.map((item) => <String, dynamic>{...item, 'read': true}).toList();
    await PushNotificationService.saveNotificationHistory(readRecords);
    if (!mounted) return;
    setState(() => _notificationHistory = readRecords);
    if (signedInUser != null) {
      final bearer = await auth.token;
      if (bearer != null && bearer.isNotEmpty) unawaited(push.syncNotificationHistory(bearer));
    }
    await _navigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => NotificationHistoryScreen(
        records: _notificationHistory,
        english: english,
        isDarkTheme: isDarkTheme,
        onChanged: (records) async {
          final retainedIds = records.map((item) => (item['id'] ?? '').toString()).toSet();
          final deletedIds = _notificationHistory
              .map((item) => (item['id'] ?? '').toString())
              .where((id) => id.isNotEmpty && !retainedIds.contains(id))
              .toList();
          await PushNotificationService.saveNotificationHistory(records);
          if (mounted) setState(() => _notificationHistory = records);
          if (signedInUser != null) {
            final bearer = await auth.token;
            if (bearer != null && bearer.isNotEmpty) {
              unawaited(push.syncNotificationHistory(bearer, deletedIds: deletedIds));
            }
          }
        },
        onOpen: _openNotificationRecord,
      ),
    ));
    await _loadNotificationHistory();
  }

  int _notificationDestinationTab(Map<String, dynamic> data) {
    final screen = (data['screen'] ?? '').toString().toLowerCase();
    final event = (data['event'] ?? '').toString().toLowerCase();
    if (screen.contains('chat') || event == 'chat_message' || event.contains('chat')) return 3;
    if (screen.contains('repair') || event.contains('repair')) return 1;
    if (screen.contains('order') || screen.contains('product') || screen.contains('service') || screen.contains('advert') || screen == 'shop' || screen == 'listings' || event == 'woocommerce_new_order' || event.contains('order')) return 2;
    if (screen.contains('booking') || event.contains('booking') || event.contains('appointment')) return 4;
    if (screen.contains('profile') || event.contains('profile')) return 5;
    if (screen == 'home' || screen == 'dashboard') return 0;
    return 0;
  }

  Future<void> _openNotificationRecord(Map<String, dynamic> record) async {
    final rawData = record['data'];
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};
    data.addAll({
      'screen': record['screen'] ?? data['screen'],
      'event': record['event'] ?? data['event'],
      'repair_id': record['repair_id'] ?? data['repair_id'] ?? data['repairId'],
      'order_id': record['order_id'] ?? data['order_id'] ?? data['orderId'],
      'campaign_id': record['campaign_id'] ?? data['campaign_id'],
      'url': record['url'] ?? data['url'],
    });
    final event = (data['event'] ?? '').toString().toLowerCase();
    final title = (record['title'] ?? tr('Известие от PCWork', 'PCWork notification')).toString();
    final body = (record['body'] ?? '').toString();
    final targetUrl = (data['url'] ?? '').toString();
    final notificationId = (record['id'] ?? data['_notification_id'] ?? '').toString();
    final repairId = int.tryParse((data['repair_id'] ?? data['repairId'] ?? '').toString());
    final orderId = int.tryParse((data['order_id'] ?? data['orderId'] ?? '').toString());

    // Remove the notification from the in-app active list once its destination
    // is opened, instead of leaving a stale unread/active card behind.
    await PushNotificationService.markNotificationRead(notificationId);
    await _loadNotificationHistory();
    if (!mounted) return;

    if (orderId != null && orderId > 0) {
      _pendingShopOrderId = orderId;
      _openShopOrdersOnEntry = false;
    } else if (event == 'woocommerce_new_order' || event.contains('order')) {
      _pendingShopOrderId = null;
      _openShopOrdersOnEntry = true;
    }

    final destinationTab = _notificationDestinationTab(data);
    _selectTab(destinationTab);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    if (repairId != null && repairId > 0 && signedInUser != null) {
      try {
        final repairs = await (repairsFuture ??= _loadRepairsFuture());
        final matchingRepairs = repairs.where((item) => item.id == repairId).toList();
        final repair = matchingRepairs.isEmpty ? null : matchingRepairs.first;
        if (repair != null && mounted) {
          _showRepairDetails(repair);
          return;
        }
      } catch (_) {
        // Keep the user on the Repairs tab if the list is temporarily unavailable.
      }
    }

    if (event == 'marketing_campaign') {
      final uri = Uri.tryParse(targetUrl.trim());
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await _showMarketingDialog(
          title: title,
          body: body,
          imageUrl: (record['image'] ?? data['image'] ?? '').toString(),
          targetUrl: targetUrl,
          campaignId: (data['campaign_id'] ?? '').toString(),
        );
      }
      return;
    }

    final isKnownDestination = (data['screen'] ?? '').toString().isNotEmpty ||
        event == 'chat_message' || event.contains('repair') || event.contains('order') ||
        event.contains('booking') || event.contains('appointment') || event.contains('profile');
    if (!isKnownDestination) await _showPushDialog(title: title, body: body, targetUrl: targetUrl);
  }

  Future<void> _requestSystemNotifications() async {
    // Ask Android for POST_NOTIFICATIONS at first launch, even before login
    // and independently of Firebase token registration.
    await push.requestPermission();
  }

  Future<void> _retryPushRegistration() async {
    final bearer = await auth.token;
    if (bearer != null && bearer.isNotEmpty) await _enablePush(knownToken: bearer);
    unawaited(_checkNotificationStatus());
  }

  Future<void> _enablePush({String? knownToken}) async {
    if (_pushRegistering) return;
    _pushRegistering = true;
    try {
      final bearer = knownToken ?? await auth.token;
      if (!mounted) return;
      if (bearer == null || bearer.isEmpty) {
        await push.requestPermission();
        return;
      }
      final registered = await push.register(bearer, onForeground: (title, body, data) {
        if (!mounted) return;
        final destinationTab = _notificationDestinationTab(data);
        final event = (data['event'] ?? '').toString().toLowerCase();
        final screen = (data['screen'] ?? '').toString().toLowerCase();
        final hasKnownDestination = screen.isNotEmpty || event == 'chat_message' || event.contains('repair') || event.contains('order') || event.contains('booking') || event.contains('appointment') || event.contains('profile');
        final notificationId = (data['_notification_id'] ?? '').toString();
        final status = (data['status'] ?? '').toString().toLowerCase();
        final transactionalPush = event == 'order_accepted' ||
            event == 'customer_repair_requested' ||
            (event == 'repair_status_changed' && status == 'requested');
        if (event != 'marketing_campaign' && hasKnownDestination && tab == destinationTab && !transactionalPush) {
          unawaited(PushNotificationService.markNotificationRead(notificationId).then((_) => _loadNotificationHistory()));
          if (destinationTab == 1) setState(() => repairsFuture = _loadRepairsFuture());
          return;
        }
        unawaited(_loadNotificationHistory());
        if ((data['event'] ?? '').toString() == 'marketing_campaign') {
          unawaited(PushNotificationService.markNotificationRead(notificationId).then((_) => _loadNotificationHistory()));
          unawaited(_showMarketingDialog(
            title: title,
            body: body,
            imageUrl: (data['image'] ?? '').toString(),
            targetUrl: (data['url'] ?? '').toString(),
            campaignId: (data['campaign_id'] ?? '').toString(),
          ));
        } else if (transactionalPush) {
          unawaited(PushNotificationService.showLocalNotification(title, body, data));
          if (mounted && destinationTab == 1) setState(() => repairsFuture = _loadRepairsFuture());
        } else {
          final record = <String, dynamic>{
            'id': notificationId,
            'title': title,
            'body': body,
            'url': (data['url'] ?? '').toString(),
            'event': (data['event'] ?? '').toString(),
            'screen': (data['screen'] ?? '').toString(),
            'repair_id': (data['repair_id'] ?? data['repairId'] ?? '').toString(),
            'order_id': (data['order_id'] ?? data['orderId'] ?? '').toString(),
            'campaign_id': (data['campaign_id'] ?? '').toString(),
            'image': (data['image'] ?? '').toString(),
            'data': Map<String, dynamic>.from(data),
          };
          unawaited(_showPushDialog(title: title, body: body, onOpen: () => _openNotificationRecord(record)));
        }
        if (mounted && destinationTab == 1) setState(() => repairsFuture = _loadRepairsFuture());
      }, onOpened: (data) async {
        if (!mounted) return;
        final record = <String, dynamic>{
          'id': (data['_notification_id'] ?? '').toString(),
          'title': (data['_notification_title'] ?? data['title'] ?? tr('Известие от PCWork', 'PCWork notification')).toString(),
          'body': (data['_notification_body'] ?? data['body'] ?? data['message'] ?? '').toString(),
          'url': (data['url'] ?? '').toString(),
          'event': (data['event'] ?? '').toString(),
          'screen': (data['screen'] ?? '').toString(),
          'repair_id': (data['repair_id'] ?? data['repairId'] ?? '').toString(),
          'order_id': (data['order_id'] ?? data['orderId'] ?? '').toString(),
          'campaign_id': (data['campaign_id'] ?? '').toString(),
          'image': (data['image'] ?? '').toString(),
          'data': Map<String, dynamic>.from(data),
        };
        await _loadNotificationHistory();
        await _openNotificationRecord(record);
      });
      unawaited(_loadNotificationHistory());
      if (mounted) {
        setState(() => _pushStatusMessage = registered
            ? tr('Устройството е регистрирано за push известия.', 'Device registered for push notifications.')
            : tr('Push регистрацията не е потвърдена. Провери системното разрешение и Firebase настройките.', 'Push registration was not confirmed. Check system permission and Firebase settings.'));
      }
    } finally {
      _pushRegistering = false;
    }
  }


  Future<void> _showPushDialog({
    required String title,
    required String body,
    String targetUrl = '',
    Future<void> Function()? onOpen,
  }) async {
    if (!mounted || _pushDialogShowing) return;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _pushDialogShowing = true;
    final uri = Uri.tryParse(targetUrl.trim());
    final validTarget = uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: isDarkTheme ? const Color(0xFF111D2B) : Colors.white,
          titlePadding: const EdgeInsets.fromLTRB(22, 18, 8, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
          title: Row(children: [
            const Icon(Icons.notifications_active_outlined, color: cyan),
            const SizedBox(width: 10),
            Expanded(child: Text(title.trim().isEmpty ? tr('Известие от PCWork', 'PCWork notification') : title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: tr('Затвори', 'Close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (body.trim().isNotEmpty) Text(body, style: const TextStyle(fontSize: 15, height: 1.45)),
            if (validTarget || onOpen != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (onOpen != null) { await onOpen(); }
                  else if (uri != null) { await launchUrl(uri, mode: LaunchMode.externalApplication); }
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(tr('Отвори', 'Open')),
              ),
            ],
          ]),
        ),
      );
    } finally {
      _pushDialogShowing = false;
    }
  }

  Future<void> _showMarketingDialog({
    required String title,
    required String body,
    required String imageUrl,
    required String targetUrl,
    required String campaignId,
  }) async {
    if (!mounted) return;
    final stableId = campaignId.trim().isNotEmpty
        ? campaignId.trim()
        : '${title.trim()}|${body.trim()}|${imageUrl.trim()}'.hashCode.toString();
    if (!_marketingCampaignsHandled.add(stableId)) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList('pcwork_seen_marketing_campaigns') ?? <String>[];
    if (seen.contains(stableId)) return;
    seen.add(stableId);
    await prefs.setStringList(
      'pcwork_seen_marketing_campaigns',
      seen.length > 50 ? seen.sublist(seen.length - 50) : seen,
    );
    if (!mounted || !context.mounted) return;
    final image = Uri.tryParse(imageUrl.trim());
    final parsedDestination = Uri.tryParse(targetUrl.trim());
    final validImage = image != null && image.scheme == 'https' && image.host.isNotEmpty;
    final destination = parsedDestination != null && parsedDestination.scheme == 'https' && parsedDestination.host.isNotEmpty
        ? parsedDestination
        : Uri.parse('https://pcwork-bg.com/');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: isDarkTheme ? const Color(0xFF111D2B) : Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.of(dialogContext).size.height * .82),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Stack(children: [
                  if (validImage)
                    SizedBox(
                      width: double.infinity,
                      height: 190,
                      child: Image.network(
                        image.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _marketingImageFallback(),
                      ),
                    )
                  else
                    _marketingImageFallback(),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: Colors.black.withValues(alpha: .58),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: tr('Затвори', 'Close'),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(title.isEmpty ? tr('Специално предложение от PCWork', 'Special offer from PCWork') : title,
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2, color: isDarkTheme ? Colors.white : const Color(0xFF172033))),
                    if (body.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(body, style: TextStyle(fontSize: 15, height: 1.5, color: isDarkTheme ? const Color(0xFFD2DCE8) : const Color(0xFF4B596B))),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await launchUrl(destination, mode: LaunchMode.externalApplication);
                          },
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text(tr('Виж предложението', 'View offer')),
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _marketingImageFallback() => Container(
    height: 190,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF102B3A), Color(0xFF4B3C85)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    alignment: Alignment.center,
    child: const Icon(Icons.campaign_rounded, size: 64, color: Color(0xFF21D4D8)),
  );

  Future<void> _refreshAfterLeavingTab() async {
    if (_refreshingOnTabExit || signedInUser == null) return;
    _refreshingOnTabExit = true;
    try {
      final bearer = await auth.token;
      if (bearer == null || bearer.isEmpty) return;
      final results = await Future.wait<dynamic>([
        auth.me(),
        push.getMarketingConsent(bearer),
      ]);
      if (!mounted) return;
      setState(() {
        signedInUser = results[0] as AuthUser;
        _marketingOptIn = results[1] as bool;
        _marketingPreferenceLoaded = true;
      });
    } catch (_) {
      // Refresh is opportunistic; never block navigation or discard current data.
    } finally {
      _refreshingOnTabExit = false;
    }
  }

  void _handleSystemBack() {
    final navigator = _navigatorKey.currentState;
    if (navigator?.canPop() == true) {
      navigator!.pop();
      return;
    }
    if (_returnToCustomerCenterOnBack && signedInUser != null) {
      _returnToCustomerCenterOnBack = false;
      unawaited(_openCustomerCenter());
      return;
    }
    if (_tabBackStack.isNotEmpty) {
      final previousTab = _tabBackStack.removeLast();
      if (previousTab != tab) {
        final oldTab = tab;
        if (oldTab == 5) unawaited(_refreshAfterLeavingTab());
        setState(() {
          tab = previousTab;
          _visitedTabs.add(previousTab);
          _settingsOpen = false;
          if (previousTab == 1 && repairsFuture == null && signedInUser != null) {
            repairsFuture = _loadRepairsFuture();
          }
        });
      }
      return;
    }
    if (tab != 0) {
      final oldTab = tab;
      if (oldTab == 5) unawaited(_refreshAfterLeavingTab());
      setState(() {
        tab = 0;
        _visitedTabs.add(0);
        _settingsOpen = false;
      });
      return;
    }
    unawaited(_confirmExit());
  }

  void _selectTab(int index, {bool recordHistory = true}) {
    if (index < 0 || index > 5) return;
    // Dismiss every transient route (dialogs, sheets and pushed overlays) before
    // switching the main section. Unsaved draft state is intentionally discarded.
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    final previousTab = tab;
    if (recordHistory && previousTab != index) {
      _tabBackStack.remove(index);
      _tabBackStack.add(previousTab);
      if (_tabBackStack.length > 30) _tabBackStack.removeAt(0);
    }
    _settingsOpen = false;
    // Refresh account preferences only after leaving Profile. Fetching the
    // repairs list on every tab change duplicated the Repairs request and
    // could overload the shared WordPress hosting during navigation.
    if (previousTab == 5 && previousTab != index) {
      unawaited(_refreshAfterLeavingTab());
    }
    setState(() {
      tab = index;
      _visitedTabs.add(index);
      if (index == 1 && repairsFuture == null && visibleUser != null) {
        repairsFuture = _loadRepairsFuture();
      }
    });
  }

  // Six-item floating glass navigation, matching the PCWork 2030 home design.
  Widget _buildBottomNavigation(List<String> labels) {
    const icons = [
      Icons.home_outlined,
      Icons.handyman_outlined,
      Icons.description_outlined,
      Icons.forum_outlined,
      Icons.calendar_month_outlined,
      Icons.person_outline_rounded,
    ];
    const selectedIcons = [
      Icons.home_rounded,
      Icons.handyman_rounded,
      Icons.description_rounded,
      Icons.forum_rounded,
      Icons.calendar_month_rounded,
      Icons.person_rounded,
    ];
    const muted = Color(0xFF91A9D8);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 2, 8, 7),
        height: 78,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF20A1B3B), Color(0xF4071028), Color(0xF21A1244)],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFF168BFF).withValues(alpha: .62)),
          boxShadow: [
            BoxShadow(color: const Color(0xFF087DFF).withValues(alpha: .18), blurRadius: 24, spreadRadius: -5, offset: const Offset(0, -3)),
            BoxShadow(color: Colors.black.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 7)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Row(
            children: List<Widget>.generate(6, (index) {
              final selected = tab == index;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: labels[index],
                  child: Tooltip(
                    message: labels[index],
                    child: InkWell(
                      borderRadius: BorderRadius.circular(23),
                      onTap: () => _selectTab(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: selected ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF09C9F5), Color(0xFF087BFF), Color(0xFF6048FF)],
                          ) : null,
                          color: selected ? null : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          border: selected ? Border.all(color: const Color(0xFF5CEBFF), width: 1) : null,
                          boxShadow: selected ? [
                            BoxShadow(color: const Color(0xFF10CFFF).withValues(alpha: .42), blurRadius: 17, spreadRadius: -3),
                          ] : const [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Icon(selected ? selectedIcons[index] : icons[index], size: selected ? 29 : 27, color: selected ? Colors.white : muted),
                            const SizedBox(height: 3),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(labels[index], maxLines: 1, style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.05,
                                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                                  color: selected ? Colors.white : muted,
                                  decoration: TextDecoration.none,
                                  decorationColor: Colors.transparent,
                                )),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _tabContent(int index) {
    switch (index) {
      case 0: return _home();
      case 1: return _repairs();
      case 2:
        return ShopScreen(
          api: api,
          tokenProvider: _uiToken,
          profileProvider: () async => visibleUser ?? (noRegPreview ? null : await auth.me()),
          english: english,
          notificationOrderId: _pendingShopOrderId,
          openOrdersOnEntry: _openShopOrdersOnEntry,
          onNotificationHandled: () {
            if (!mounted) return;
            setState(() {
              _pendingShopOrderId = null;
              _openShopOrdersOnEntry = false;
            });
          },
        );
      case 3: return ContactHubScreen(api: api, tokenProvider: _uiToken, sessionKey: signedInUser?.id ?? 0, english: english, isDarkTheme: isDarkTheme, isActive: tab == 3, isAdministrator: canUseAdminChat, canUploadFiles: true);
      case 4: return _booking();
      case 5: return _profile();
      default: return const SizedBox.shrink();
    }
  }

  Future<void> _confirmExit() async {
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Изход от приложението?', 'Exit the app?')),
        content: Text(tr('Наистина ли искате да затворите PCWork?', 'Do you really want to close PCWork?')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr('Остани', 'Stay'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(tr('Изход', 'Exit'))),
        ],
      ),
    );
    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = [tr('Начало', 'Home'), tr('Ремонти', 'Repairs'), tr('Обяви', 'Listings'), tr('Чат', 'Chat'), tr('Записване', 'Booking'), tr('Профил', 'Profile')];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      navigatorKey: _navigatorKey,
      title: 'PCWork',
      // Keep the six-item main navigation outside the route Navigator.
      // Pushed pages, dialogs and bottom sheets are therefore constrained
      // to the area above the navigation and can never cover it.
      builder: (context, child) => Column(
        children: [
          // Clip the route overlay to the content viewport. Dialogs, pushed
          // pages and modal sheets cannot paint over the persistent tab bar.
          Expanded(child: ClipRect(child: child ?? const SizedBox.shrink())),
          _buildBottomNavigation(labels),
        ],
      ),
      theme: PCWorkTheme.build(dark: isDarkTheme),
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleSystemBack();
        },
        child: Scaffold(
        appBar: AppBar(
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkTheme
                    ? const [Color(0xFF101D2D), Color(0xFF0A101A)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF2F7FA)],
              ),
            ),
          ),
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 42, height: 42, child: Image.asset('assets/images/LogoPCwork.webp', fit: BoxFit.contain)),
            const SizedBox(width: 7),
            const Text('PCWork', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
            const SizedBox(width: 9), Container(width: 5, height: 5, decoration: const BoxDecoration(color: cyan, shape: BoxShape.circle)),
            const SizedBox(width: 8), Flexible(child: Text(labels[tab], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF93A4B8), fontWeight: FontWeight.w500))),
          ]),
          actions: [
            IconButton(
              tooltip: tr('Често задавани въпроси', 'Frequently asked questions'),
              onPressed: () => _openWebsite('https://pcwork-bg.com/faq/'),
              icon: const Icon(Icons.help_outline_rounded),
            ),
            IconButton(
              tooltip: tr('Известия', 'Notifications'),
              onPressed: _openNotifications,
              icon: Stack(clipBehavior: Clip.none, children: [
                const Icon(Icons.notifications_none_rounded),
                if (_unreadNotificationCount > 0)
                  Positioned(right: -7, top: -5, child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle),
                    child: Text(_unreadNotificationCount > 99 ? '99+' : '$_unreadNotificationCount',
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  )),
              ]),
            ),
            IconButton(tooltip: tr('Настройки', 'Settings'), onPressed: _showSettings, icon: const Icon(Icons.tune_rounded)),
          ],
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDarkTheme
                ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0D1826), Color(0xFF0A101A), Color(0xFF0B111B)])
                : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF7F9FC), Color(0xFFEEF2F7)]),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: IndexedStack(index: tab, children: List<Widget>.generate(6, (index) => _visitedTabs.contains(index) ? _tabContent(index) : const SizedBox.shrink()))),

            ],
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _openCustomerCenter() async {
    final user = signedInUser;
    if (user == null) {
      _selectTab(5);
      return;
    }
    final bearer = await auth.token;
    if (bearer == null || bearer.isEmpty || !mounted) return;
    await _navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => CustomerCenterScreen(
      api: api,
      token: bearer,
      user: user,
      english: english,
      onRepairs: () { _navigatorKey.currentState?.pop(); _returnToCustomerCenterOnBack = true; _selectTab(1); },
      onOrders: () { _navigatorKey.currentState?.pop(); _returnToCustomerCenterOnBack = true; setState(() { _pendingShopOrderId = null; _openShopOrdersOnEntry = true; }); _selectTab(2); },
      onChat: () { _navigatorKey.currentState?.pop(); _returnToCustomerCenterOnBack = true; _selectTab(3); },
      onBooking: () { _navigatorKey.currentState?.pop(); _returnToCustomerCenterOnBack = true; _selectTab(4); },
      onNotifications: () { _navigatorKey.currentState?.pop(); _returnToCustomerCenterOnBack = true; _openNotifications(); },
      onProfile: () { _navigatorKey.currentState?.pop(); _returnToCustomerCenterOnBack = true; _selectTab(5); },
    )));
  }

  Widget _customerCenterHomeCard() => Card(
    clipBehavior: Clip.antiAlias,
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: _openCustomerCenter,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF075B63), Color(0xFF123B4A), Color(0xFF202B45)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cyan.withValues(alpha: .55)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(15)),
              child: const Icon(Icons.space_dashboard_rounded, color: Colors.white, size: 27),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('ТВОЯТ КЛИЕНТСКИ ЦЕНТЪР', 'YOUR CUSTOMER CENTER'), style: const TextStyle(color: Color(0xFF8DF3F0), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
              const SizedBox(height: 4),
              Text(tr('Ремонти, поръчки и профил на едно място', 'Repairs, orders and profile in one place'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ])),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 23),
          ]),
        ),
      ),
    ),
  );

  Widget _home() => ListView(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
    children: [
      _homeHero(),
      if (_appUpdateInfo != null) ...[
        const SizedBox(height: 12),
        _appUpdateBanner(),
      ],
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: Text(
              tr('Услуги на PCWork', 'PCWork services'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -.3),
            ),
          ),
          TextButton(
            onPressed: () => _openWebsite('https://pcwork-bg.com/category/uslugi/'),
            child: Text(tr('Всички услуги', 'All services')),
          ),
        ],
      ),
      const SizedBox(height: 7),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 11,
        mainAxisSpacing: 11,
        childAspectRatio: 1.38,
        children: [
          _homeServiceCard(
            image: 'assets/images/repair_laptop.webp',
            title: tr('Ремонти', 'Repairs'),
            subtitle: tr('Компютри, лаптопи, PlayStation', 'Computers, laptops, PlayStation'),
            icon: Icons.build_rounded,
            accent: const Color(0xFF25C9FF),
            onTap: () => _selectTab(1),
          ),
          _homeServiceCard(
            image: 'assets/images/repair_diagnostics.webp',
            title: tr('Диагностика', 'Diagnostics'),
            subtitle: tr('Тестване на устройства', 'Device testing'),
            icon: Icons.search_rounded,
            accent: const Color(0xFF31D8FF),
            onTap: () => _openWebsite('https://pcwork-bg.com/produkt/diagnostika/'),
          ),
          _homeServiceCard(
            image: 'assets/images/repair_warranty.webp',
            title: tr('Удължена гаранция', 'Extended warranty'),
            subtitle: tr('Спокойствие за повече време', 'Peace of mind for longer'),
            icon: Icons.verified_user_rounded,
            accent: const Color(0xFF28D8F4),
            onTap: () => _openWebsite('https://pcwork-bg.com/produkt/garancziya-remont/'),
          ),
          _homeServiceCard(
            image: 'assets/images/repair_console.webp',
            title: 'PS4 / PS5',
            subtitle: tr('Профилактика и ремонт', 'Maintenance and repair'),
            icon: Icons.sports_esports_rounded,
            accent: const Color(0xFF9A67FF),
            onTap: () => _openWebsite('https://pcwork-bg.com/produkt/profilaktika-na-sony-playstation-4-i-5/'),
          ),
          _homeServiceCard(
            image: 'assets/images/pcwork_ai_mascot.webp',
            title: 'PCWork AI',
            subtitle: tr('Твоят AI асистент', 'Your AI assistant'),
            icon: Icons.auto_awesome_rounded,
            accent: const Color(0xFF28D8F4),
            onTap: _openAiAssistant,
          ),
          _homeServiceCard(
            image: 'assets/images/marketplace_listings.png',
            title: tr('Обяви', 'Marketplace'),
            subtitle: tr('Купи, продай, открий повече', 'Buy, sell and discover'),
            icon: Icons.campaign_rounded,
            accent: const Color(0xFF9A67FF),
            onTap: () => _selectTab(2),
          ),
        ],
      ),
      const SizedBox(height: 13),
      _homeBookingBanner(),
      const SizedBox(height: 20),
      if (visibleUser == null) _homeSignInCard() else ...[
        _customerCenterHomeCard(),
        const SizedBox(height: 12),
        _homeAccountDashboard(),
      ],
      const SizedBox(height: 20),
      _homeSectionHeader(tr('Свържи се с нас', 'Contact us'), Icons.headset_mic_rounded),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _contactCard(const Icon(Icons.call_rounded, color: Color(0xFF21D4D8), size: 21), tr('Обади се', 'Call us'), null, const Color(0xFF21D4D8), () => _launchContact(Uri(scheme: 'tel', path: '0886638848')))),
        const SizedBox(width: 10),
        Expanded(child: _contactCard(const Icon(Icons.chat_rounded, color: Color(0xFF8B70E8), size: 21), 'Viber', tr('Пиши ни', 'Message us'), const Color(0xFF8B70E8), () => _launchContact(Uri.parse('viber://chat?number=%2B359886638848')))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _contactCard(const Icon(Icons.facebook, color: Color(0xFF3988F7), size: 21), 'Messenger', tr('Пиши ни', 'Message us'), const Color(0xFF3988F7), () => _launchContact(Uri.parse('https://m.me/PcWorkService')))),
        const SizedBox(width: 10),
        Expanded(child: _contactCard(const FaIcon(FontAwesomeIcons.tiktok, color: Color(0xFFE05A8D), size: 21), 'TikTok', null, const Color(0xFFE05A8D), () => _launchContact(Uri.parse('https://www.tiktok.com/@css.ps4.ps5')))),
      ]),
      const SizedBox(height: 10),
      if (visibleUser != null)
        Row(children: [
          Expanded(child: _contactCard(const Icon(Icons.chat_bubble_outline_rounded, color: cyan, size: 21), tr('Чат с PCWork', 'Chat with PCWork'), tr('Отвори директния чат със сервизния екип', 'Open the direct chat with our service team'), cyan, () => _selectTab(3))),
          const SizedBox(width: 10),
          Expanded(child: _contactCard(const Icon(Icons.star_rate_rounded, color: Color(0xFFFFC857), size: 22), tr('Оцени приложението', 'Rate the app'), tr('Сподели впечатленията си с PCWork', 'Share your feedback with PCWork'), const Color(0xFFFFC857), () => _showRatingDialog(type: 'app'))),
        ])
      else
        SizedBox(width: double.infinity, child: _contactCard(const Icon(Icons.chat_bubble_outline_rounded, color: cyan, size: 21), tr('Чат с PCWork', 'Chat with PCWork'), tr('Отвори директния чат със сервизния екип', 'Open the direct chat with our service team'), cyan, () => _selectTab(3))),
      const SizedBox(height: 16),
      _homeSectionHeader(tr('Бърз достъп', 'Quick access'), Icons.bolt_rounded),
      const SizedBox(height: 6),
      Wrap(spacing: 9, runSpacing: 9, children: [
        if (isCustomerAccount || noRegPreview) _homeQuickAccessCard(Icons.sports_volleyball_rounded, tr('Плажно приключение', 'Beach Adventure'), _openBeachGame),
        _homeQuickAccessCard(Icons.location_on_outlined, tr('Сервизни обекти', 'Service locations'), _showLocations),
        if (isCustomerAccount) _homeQuickAccessCard(Icons.privacy_tip_outlined, tr('Общи условия и GDPR', 'Terms & GDPR'), () => _openWebsite('https://pcwork-bg.com/gdpr/')),
        _homeQuickAccessCard(Icons.monitor_heart_outlined, tr('PCWork Device Monitor', 'PCWork Device Monitor'), _openDeviceMonitor),
      ]),
    ],
  );

  Widget _homeHero() => Container(
    height: 292,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(27),
      border: Border.all(color: const Color(0xFF20BFFF).withValues(alpha: .62)),
      boxShadow: [BoxShadow(color: const Color(0xFF087DFF).withValues(alpha: .20), blurRadius: 26, spreadRadius: -7, offset: const Offset(0, 10))],
      image: const DecorationImage(image: AssetImage('assets/images/repairs_hero.webp'), fit: BoxFit.cover, alignment: Alignment.centerRight),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xF5051026), Color(0xD9051026), Color(0x44051026)])))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 16, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('PCWork Mobile', 'PCWork Mobile'), style: const TextStyle(color: Color(0xFF24D6F3), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
            const SizedBox(height: 12),
            SizedBox(
              width: 205,
              child: Text(tr('Добре дошли в PCWork!', 'Welcome to PCWork!'), style: const TextStyle(fontSize: 27, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -.7, color: Colors.white)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 190,
              child: Text(tr('Твоят доверен партньор за бърз и професионален сервиз.', 'Your trusted partner for fast, professional service.'), style: const TextStyle(color: Color(0xFFD6E8FF), fontSize: 13, height: 1.35, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            SizedBox(
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF08C8F4), Color(0xFF187BFF), Color(0xFF8B42FF)]), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: const Color(0xFF12BDFB).withValues(alpha: .35), blurRadius: 18)]),
                child: FilledButton.icon(
                  onPressed: _startHomeRequest,
                  style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 17), shape: const StadiumBorder()),
                  icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                  label: Text(tr('Нова заявка', 'New request'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    ),
  );

  Widget _homeServiceCard({
    required String? image,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) => Material(
    color: const Color(0xFF0B1A35),
    borderRadius: BorderRadius.circular(23),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: accent.withValues(alpha: .75), width: 1.1),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: .17), blurRadius: 17, spreadRadius: -6)],
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (image != null)
            Image.asset(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF10294B)))
          else
            DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent.withValues(alpha: .35), const Color(0xFF07142D), const Color(0xFF24114C)])), child: Center(child: Icon(icon, size: 88, color: accent.withValues(alpha: .55)))),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22030B1D), Color(0x55030B1D), Color(0xF0030B1D)]))),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xCC06142B), border: Border.all(color: accent, width: 1.4), boxShadow: [BoxShadow(color: accent.withValues(alpha: .30), blurRadius: 12)]),
              child: Icon(icon, color: accent, size: 23),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.12, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD7E8FF), fontSize: 10.5, height: 1.2, fontWeight: FontWeight.w600, shadows: [Shadow(color: Colors.black, blurRadius: 8)])),
            ]),
          ),
          Positioned(
            right: 9,
            bottom: 9,
            child: Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xAA07152E), border: Border.all(color: accent.withValues(alpha: .8))), child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22)),
          ),
        ]),
      ),
    ),
  );

  Widget _homeBookingBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF07365B), Color(0xFF10234B), Color(0xFF24124D)]),
      border: Border.all(color: const Color(0xFF25BFFF).withValues(alpha: .75)),
      boxShadow: [BoxShadow(color: const Color(0xFF197DFF).withValues(alpha: .17), blurRadius: 20, spreadRadius: -6)],
    ),
    child: Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF25C9FF).withValues(alpha: .7)), borderRadius: BorderRadius.circular(14)),
          child: Image.asset(
            'assets/images/pcwork_booking_hero.webp',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF10294B),
              child: Center(child: Icon(Icons.calendar_month_rounded, color: Color(0xFF25C9FF), size: 32)),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Резервирай час', 'Book an appointment'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(tr('Бързо и лесно', 'Quick and easy'), style: const TextStyle(color: Color(0xFFB8D8F8), fontSize: 12, fontWeight: FontWeight.w600))])),
      const SizedBox(width: 8),
      DecoratedBox(
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF08C8F4), Color(0xFF187BFF), Color(0xFF8B42FF)]), borderRadius: BorderRadius.circular(30)),
        child: FilledButton(
          onPressed: () => _selectTab(4),
          style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(tr('Запази час', 'Book now'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)), const SizedBox(width: 4), const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20)]),
        ),
      ),
    ]),
  );

  Future<void> _startHomeRequest() async {
    if (canSeeStaffUi) {
      _showIntakeForm();
      return;
    }
    if (visibleUser != null) {
      await _showCustomerRepairRequest();
      return;
    }
    await _openAuthScreen(register: false);
  }

  Future<void> _openAiAssistant() async {
    final token = await auth.token;
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      _message(tr('Влез в профила си, за да използваш PCWork AI.', 'Sign in to use PCWork AI.'));
      await _openAuthScreen(register: false);
      return;
    }
    await _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => AiAssistantChatScreen(api: api, token: token, english: english, staffMode: canSeeStaffUi),
    ));
  }

  Future<void> _openBeachGame() async {
    if (!(isCustomerAccount || noRegPreview)) return;
    await _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => BeachGameScreen(english: english),
    ));
  }

  Future<void> _launchContact(Uri uri) async {
    try {
      if (uri.scheme == 'tel') {
        await _phoneChannel.invokeMethod<bool>('openDialer', {'number': uri.path});
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _message(tr('Не успяхме да отворим приложението или връзката.', 'Could not open the app or link.'));
    } catch (e) {
      if (mounted) _message('${tr('Грешка при отваряне:', 'Could not open:')} $e');
    }
  }

  Widget _homeSectionHeader(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF12BFF4).withValues(alpha: .13),
          border: Border.all(color: const Color(0xFF20C8FF).withValues(alpha: .55)),
          boxShadow: [BoxShadow(color: const Color(0xFF168BFF).withValues(alpha: .14), blurRadius: 12)],
        ),
        child: Icon(icon, color: const Color(0xFF42D8FF), size: 18),
      ),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -.2)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF20C8FF).withValues(alpha: .55), Colors.transparent])))),
    ]),
  );

  Widget _homeQuickAccessCard(IconData icon, String title, VoidCallback onTap) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 37) / 2,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xD91A3458), Color(0xD90B1730), Color(0xD91A1640)]),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: PCWorkColors.electricBlue.withValues(alpha: .38)),
            boxShadow: [BoxShadow(color: PCWorkColors.electricBlue.withValues(alpha: .09), blurRadius: 15, spreadRadius: -6)],
          ),
          child: Row(children: [
            PCWorkGlowIcon(icon: icon, size: 38, iconSize: 19, color: PCWorkColors.cyan),
            const SizedBox(width: 9),
            Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PCWorkColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w800, height: 1.2))),
            const Icon(Icons.chevron_right_rounded, color: PCWorkColors.textMuted, size: 19),
          ]),
        ),
      ),
    ),
  );

  Widget _contactCard(Widget icon, String title, String? subtitle, Color accent, VoidCallback onTap) =>
      Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xD91A345B), Color(0xD90C1934), Color(0xD91B1741)]),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: accent.withValues(alpha: .58)),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: .12), blurRadius: 16, spreadRadius: -5)],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
              child: Row(children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [accent.withValues(alpha: .28), accent.withValues(alpha: .08)]),
                    border: Border.all(color: accent.withValues(alpha: .78)),
                    boxShadow: [BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 12)],
                  ),
                  alignment: Alignment.center,
                  child: icon,
                ),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, height: 1.15, color: Color(0xFFB8CBE8))),
                  ],
                ])),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF9DCBFF), size: 20),
              ]),
            ),
          ),
        ),
      );

  Widget _repairs() {
    if (visibleUser == null) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        _repairsHero(
          title: tr('Твоите ремонти', 'Your repairs'),
          subtitle: tr('Следи всяка стъпка от сервиза на едно място.', 'Follow every service step in one place.'),
          actionLabel: tr('Вход / Регистрация', 'Sign in / Register'),
          onAction: authBusy ? null : () => _openAuthScreen(register: false),
        ),
        const SizedBox(height: 16),
        const PCWorkGlassPanel(
          glow: true,
          child: Row(children: [
            PCWorkGlowIcon(icon: Icons.lock_outline_rounded, color: PCWorkColors.cyan),
            SizedBox(width: 13),
            Expanded(child: Text(
              'Влез в профила си, за да видиш ремонтите, историята и актуалния им статус.',
              style: TextStyle(color: PCWorkColors.textSecondary, height: 1.4),
            )),
          ]),
        ),
      ]);
    }

    final future = repairsFuture ??= _loadRepairsFuture();
    return RefreshIndicator(
      color: PCWorkColors.cyan,
      onRefresh: () async {
        final f = _loadRepairsFuture();
        setState(() => repairsFuture = f);
        await f;
      },
      child: FutureBuilder<List<Repair>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: PCWorkColors.cyan));
          }
          if (snapshot.hasError) {
            return ListView(padding: const EdgeInsets.all(24), children: [
              _repairsHero(
                title: tr('Сервизен център', 'Service center'),
                subtitle: tr('Не успяхме да заредим ремонтите.', 'We could not load your repairs.'),
              ),
              const SizedBox(height: 14),
              PCWorkGlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${snapshot.error}', style: const TextStyle(color: PCWorkColors.textSecondary)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr('Опитай отново', 'Try again')),
                ),
              ])),
            ]);
          }

          final rows = List<Repair>.from(snapshot.data ?? [])
            ..sort((a, b) => _repairDate(b.createdAt).compareTo(_repairDate(a.createdAt)));
          final query = repairSearch.text.trim().toLowerCase();
          final filtered = rows.where((r) =>
            (repairStatusFilter == 'all' || r.status == repairStatusFilter) &&
            (query.isEmpty || [r.number, r.device, r.model, r.serial, r.location]
              .any((v) => v.toLowerCase().contains(query)))
          ).toList();
          final active = rows.where((r) => !['completed', 'cancelled'].contains(r.status)).length;
          final ready = rows.where((r) => r.status == 'ready').length;

          return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 28), children: [
            _repairsHero(
              title: tr('Сервизен център', 'Service center'),
              subtitle: tr('Всички твои устройства и ремонти – с актуален статус и история.', 'All your devices and repairs, with current status and history.'),
              actionLabel: canSeeStaffUi ? tr('Приеми устройство', 'Device intake') : tr('Нова заявка', 'New request'),
              onAction: canSeeStaffUi ? _showIntakeForm : _showCustomerRepairRequest,
            ),
            const SizedBox(height: 15),
            Row(children: [
              Expanded(child: _repairMetricGlass(tr('Всички', 'All'), rows.length, Icons.devices_rounded, PCWorkColors.electricBlue)),
              const SizedBox(width: 8),
              Expanded(child: _repairMetricGlass(tr('Активни', 'Active'), active, Icons.settings_suggest_rounded, PCWorkColors.cyan)),
              const SizedBox(width: 8),
              Expanded(child: _repairMetricGlass(tr('Готови', 'Ready'), ready, Icons.check_circle_rounded, PCWorkColors.success)),
            ]),
            if (_pendingSyncCount > 0) ...[
              const SizedBox(height: 12),
              PCWorkGlassPanel(
                borderColor: PCWorkColors.warning.withValues(alpha: .55),
                child: Row(children: [
                  const PCWorkGlowIcon(icon: Icons.cloud_upload_outlined, color: PCWorkColors.warning),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Чакащи синхронизации: $_pendingSyncCount', 'Pending sync: $_pendingSyncCount'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(tr('Ще бъдат изпратени автоматично при възстановяване на интернет.', 'They will sync automatically when internet is restored.'), style: const TextStyle(color: PCWorkColors.textSecondary, fontSize: 12)),
                  ])),
                  IconButton(onPressed: _syncOfflineQueue, icon: const Icon(Icons.sync_rounded, color: PCWorkColors.cyan)),
                ]),
              ),
            ],
            if ((snapshot.data ?? []).any((r) => r.fromCache)) ...[
              const SizedBox(height: 10),
              const PCWorkGlassPanel(
                borderColor: Color(0x6648C9F5),
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, color: PCWorkColors.cyan),
                  SizedBox(width: 10),
                  Expanded(child: Text('Офлайн копие – показват се последно запазените данни.', style: TextStyle(color: PCWorkColors.textSecondary, fontSize: 12))),
                ]),
              ),
            ],
            const SizedBox(height: 17),
            Row(children: [
              Expanded(child: Text(tr('Моите ремонти', 'My repairs'), style: Theme.of(context).textTheme.titleLarge)),
              Text('${filtered.length} ${tr('резултата', 'results')}', style: const TextStyle(color: PCWorkColors.textMuted, fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            PCWorkGlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
              child: TextField(
                controller: repairSearch,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: PCWorkColors.textPrimary),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, color: PCWorkColors.cyan),
                  hintText: tr('Търси номер, устройство или модел', 'Search number, device or model'),
                  hintStyle: const TextStyle(color: PCWorkColors.textMuted, fontSize: 13),
                  border: InputBorder.none,
                  suffixIcon: repairSearch.text.isEmpty ? null : IconButton(
                    onPressed: () { repairSearch.clear(); setState(() {}); },
                    icon: const Icon(Icons.close_rounded, color: PCWorkColors.textMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 11),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _repairFilterChip('all', tr('Всички', 'All')),
                _repairFilterChip('requested', tr('Заявени', 'Requested')),
                _repairFilterChip('diagnostics', tr('Диагностика', 'Diagnostics')),
                _repairFilterChip('in_repair', tr('В ремонт', 'In repair')),
                _repairFilterChip('ready', tr('Готови', 'Ready')),
                _repairFilterChip('completed', tr('Приключени', 'Completed')),
              ]),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              PCWorkGlassPanel(
                padding: const EdgeInsets.all(22),
                child: Column(children: [
                  const PCWorkGlowIcon(icon: Icons.search_off_rounded, size: 58, iconSize: 28, color: PCWorkColors.textMuted),
                  const SizedBox(height: 10),
                  Text(
                    rows.isEmpty ? tr('Все още няма ремонти, свързани с профила ви.', 'There are no repairs linked to your account yet.') : tr('Няма ремонти, отговарящи на търсенето.', 'No repairs match your search.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: PCWorkColors.textSecondary),
                  ),
                ]),
              ),
            ...filtered.map(_repairGlassCard),
          ]);
        },
      ),
    );
  }

  Widget _repairsHero({required String title, required String subtitle, String? actionLabel, VoidCallback? onAction}) => Container(
    height: 196,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: PCWorkColors.electricBlue.withValues(alpha: .55)),
      boxShadow: [BoxShadow(color: PCWorkColors.electricBlue.withValues(alpha: .16), blurRadius: 24, spreadRadius: -7)],
      image: const DecorationImage(image: AssetImage('assets/images/repairs_hero.webp'), fit: BoxFit.cover, alignment: Alignment.centerRight),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xF5051026), Color(0xD9051026), Color(0x55101D38)])))),
        Padding(padding: const EdgeInsets.fromLTRB(17, 17, 15, 15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PCWORK SERVICE', style: TextStyle(color: PCWorkColors.cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
          const SizedBox(height: 8),
          SizedBox(width: 220, child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 23, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -.5))),
          const SizedBox(height: 7),
          SizedBox(width: 225, child: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD6E8FF), fontSize: 12, height: 1.35, fontWeight: FontWeight.w600))),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            SizedBox(height: 39, child: DecoratedBox(
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF08C8F4), Color(0xFF187BFF), Color(0xFF8B42FF)]), borderRadius: BorderRadius.circular(30)),
              child: FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(horizontal: 14), shape: const StadiumBorder()),
                icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                label: Text(actionLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            )),
        ])),
      ]),
    ),
  );

  Widget _repairMetricGlass(String title, int value, IconData icon, Color accent) => PCWorkGlassPanel(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
    borderColor: accent.withValues(alpha: .42),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: accent, size: 20),
      const SizedBox(height: 7),
      Text('$value', style: TextStyle(color: accent, fontSize: 23, fontWeight: FontWeight.w900, height: 1)),
      const SizedBox(height: 4),
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PCWorkColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _repairFilterChip(String value, String label) {
    final selected = repairStatusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => setState(() => repairStatusFilter = value),
        label: Text(label),
        labelStyle: TextStyle(color: selected ? Colors.white : PCWorkColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
        selectedColor: PCWorkColors.electricBlue,
        backgroundColor: const Color(0xFF10213D),
        side: BorderSide(color: selected ? PCWorkColors.cyan : const Color(0xFF294365)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _repairGlassCard(Repair repair) {
    final accent = _repairAccent(repair.status);
    final icon = repair.status == 'ready' || repair.status == 'completed'
        ? Icons.check_circle_outline_rounded
        : repair.status == 'diagnostics' ? Icons.manage_search_rounded : Icons.build_circle_outlined;
    final number = repair.number.isEmpty ? 'Ремонт #${repair.id}' : repair.number;
    final details = [repair.device, repair.model, if (repair.pendingSync) tr('Чака синхронизация', 'Pending sync')].where((v) => v.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(21),
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: () => _showRepairDetails(repair),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xD91A3458), Color(0xE90B1730), Color(0xD91A1640)]),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: accent.withValues(alpha: .48)),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: .10), blurRadius: 17, spreadRadius: -6)],
            ),
            child: Padding(padding: const EdgeInsets.all(13), child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: .13), border: Border.all(color: accent.withValues(alpha: .5))), child: Icon(icon, color: accent, size: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(number, style: const TextStyle(color: PCWorkColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
                if (details.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PCWorkColors.textSecondary, fontSize: 11, height: 1.3))),
                const SizedBox(height: 7),
                Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(20), border: Border.all(color: accent.withValues(alpha: .35))), child: Text(_statusLabel(repair.status), style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w800))),
              ])),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: accent, size: 25),
            ])),
          ),
        ),
      ),
    );
  }

  Color _repairAccent(String status) {
    switch (status) {
      case 'ready':
      case 'completed': return PCWorkColors.success;
      case 'diagnostics': return PCWorkColors.violet;
      case 'waiting_approval': return PCWorkColors.warning;
      case 'cancelled': return PCWorkColors.danger;
      default: return PCWorkColors.cyan;
    }
  }

  DateTime _repairDate(String value) => DateTime.tryParse(value)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

  String _formatDate(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d.$m.${date.year}';
  }

  String _priorityLabel(String value) {
    const bg = {'low': 'Нисък', 'normal': 'Нормален', 'high': 'Висок', 'urgent': 'Спешен'};
    const en = {'low': 'Low', 'normal': 'Normal', 'high': 'High', 'urgent': 'Urgent'};
    return (english ? en[value] : bg[value]) ?? value;
  }

  Future<void> _shareRepair(Repair repair) async {
    final number = repair.number.isEmpty ? 'PCW-${repair.id}' : repair.number;
    final text = [
      'PCWork – ${tr('Информация за ремонт', 'Repair information')}',
      '${tr('Номер', 'Number')}: $number',
      '${tr('Устройство', 'Device')}: ${repair.device} ${repair.model}'.trim(),
      '${tr('Статус', 'Status')}: ${_statusLabel(repair.status)}',
      if (repair.location.isNotEmpty) '${tr('Сервизен обект', 'Service location')}: ${repair.location}',
      if (repair.dueAt.isNotEmpty) '${tr('Краен срок', 'Due date')}: ${_formatDate(repair.dueAt)}',
      'https://pcwork-bg.com',
    ].join('\n');
    await Share.share(text, subject: 'PCWork $number');
  }

  Future<void> _showCustomerRepairRequest() async {
    final token = await auth.token;
    if (token == null) { _message(tr('Влезте в клиентския профил.','Sign in to your customer account.')); return; }
    // Start the request immediately, but show the form first so the user never
    // sees a dead button while the service-location API is loading.
    Future<List<ServiceLocation>> locationsFuture = api.getLocations();
    final clientRequestId = api.createClientRequestId();
    final model = TextEditingController();
    final problem = TextEditingController();
    final otherDevice = TextEditingController();
    ServiceLocation? selected;
    String? selectedDeviceType;
    String selectedRepairPayment = 'cash_on_site';
    String? deviceError;
    String? problemError;
    String? requestError;
    bool saving = false;
    final sheetHostContext = _navigatorKey.currentState?.overlay?.context;
    if (sheetHostContext == null || !sheetHostContext.mounted) return;
    await showModalBottomSheet<void>(
      context: sheetHostContext,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
        child: SizedBox(height: MediaQuery.of(ctx).size.height * .78, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(tr('Нова заявка за ремонт','New repair request'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(onPressed: saving ? null : () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
          Text(tr('Заявката ще бъде свързана с вашия профил. Екипът ни ще се свърже с вас за потвърждение.', 'The request will be linked to your account. Our team will contact you to confirm it.'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 12),
          Expanded(child: ListView(children: [
            FutureBuilder<List<ServiceLocation>>(
              future: locationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()));
                if (snapshot.hasError) return Column(children: [Text('${tr('Неуспешно зареждане на сервизните обекти:', 'Could not load service locations:')} ${snapshot.error}'), TextButton.icon(onPressed: () => setSheet(() => locationsFuture = api.getLocations()), icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново', 'Retry')))]);
                final locations = (snapshot.data ?? []).where((location) => location.canSelect && !location.isUpcoming && location.code.isNotEmpty).toList();
                if (locations.isEmpty) return Text(tr('В момента няма обекти, които приемат онлайн заявки.', 'No service locations are currently accepting online requests.'));
                selected ??= locations.first;
                return DropdownButtonFormField<ServiceLocation>(
                  initialValue: locations.any((location) => location.code == selected?.code) ? selected : locations.first,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Сервизен обект*','Service location*'), border: const OutlineInputBorder()),
                  items: locations.map((location) => DropdownMenuItem(value: location, child: Text(location.name))).toList(),
                  onChanged: saving ? null : (value) => setSheet(() { selected = value; requestError = null; }),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedDeviceType,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Тип устройство*','Device type*'), errorText: deviceError, border: const OutlineInputBorder()),
              items: const ['Лаптоп','Настолен компютър','PlayStation 5','PlayStation 4','Друго'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
              onChanged: saving ? null : (value) => setSheet(() { selectedDeviceType = value; deviceError = null; requestError = null; }),
            ),
            if (selectedDeviceType == 'Друго') ...[
              const SizedBox(height: 12),
              TextField(controller: otherDevice, enabled: !saving, onChanged: (_) { if (requestError != null) setSheet(() => requestError = null); }, decoration: InputDecoration(labelText: tr('Опишете устройството*','Specify the device*'), border: const OutlineInputBorder())),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedRepairPayment,
              decoration: InputDecoration(labelText: tr('Плащане при завършен ремонт*', 'Payment after repair*'), border: const OutlineInputBorder()),
              items: [DropdownMenuItem(value: 'cash_on_site', child: Text(tr('В брой на място в PCWork', 'Cash at PCWork location'))), DropdownMenuItem(value: 'cash_courier', child: Text(tr('В брой на куриера при доставка', 'Cash to courier on delivery')))],
              onChanged: saving ? null : (value) => setSheet(() => selectedRepairPayment = value ?? 'cash_on_site'),
            ),
            const SizedBox(height: 12),
            TextField(controller: model, enabled: !saving, onChanged: (_) { if (requestError != null) setSheet(() => requestError = null); }, decoration: InputDecoration(labelText: tr('Марка и модел*','Brand and model*'), border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: problem, enabled: !saving, minLines: 3, maxLines: 5, onChanged: (_) { if (problemError != null || requestError != null) setSheet(() { problemError = null; requestError = null; }); }, decoration: InputDecoration(labelText: tr('Описание на проблема*','Problem description*'), helperText: tr('Опишете симптомите и кога се появяват. Минимум 15 смислени символа.', 'Describe the symptoms and when they occur. At least 15 meaningful characters.'), errorText: problemError, border: const OutlineInputBorder())),
          ])),
          if (requestError != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: .10), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.redAccent.withValues(alpha: .45))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(requestError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saving ? null : () async {
            final meaningfulProblem = problem.text.trim().replaceAll(RegExp(r'\s+'), '');
            if (selectedDeviceType == null) { setSheet(() => deviceError = tr('Изберете тип устройство.', 'Choose a device type.')); return; }
            if (selectedDeviceType == 'Друго' && otherDevice.text.trim().isEmpty) { setSheet(() => deviceError = tr('Въведете какво е устройството.', 'Enter the device type.')); return; }
            if (selected == null) { setSheet(() => requestError = tr('Изберете сервизен обект.', 'Choose a service location.')); return; }
            if (model.text.trim().isEmpty) { setSheet(() => requestError = tr('Въведете марка и модел.', 'Enter brand and model.')); return; }
            if (meaningfulProblem.length < 15) { setSheet(() => problemError = tr('Моля, опишете проблема по-подробно (минимум 15 смислени символа).', 'Please describe the problem in more detail (at least 15 meaningful characters).')); return; }
            setSheet(() { saving = true; requestError = null; });
            try {
              final deviceType = selectedDeviceType == 'Друго' ? 'Друго: ${otherDevice.text.trim()}' : selectedDeviceType!;
              await api.createCustomerRepairRequest(token, {
                'location_code': selected!.code,
                'device_type': deviceType,
                'device_model': model.text.trim(),
                'problem_description': problem.text.trim(),
                'payment_method': selectedRepairPayment,
              }, clientRequestId: clientRequestId).timeout(const Duration(seconds: 34));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => repairsFuture = _loadRepairsFuture());
                // The server confirms accepted requests through a push notification and notification history.
              }
            } catch (error) {
              if (ctx.mounted) {
                setSheet(() {
                  saving = false;
                  requestError = '${tr('Заявката не беше приета. Данните са запазени във формата. Причина:', 'The request was not accepted. Your entries remain in the form. Reason:')} $error';
                });
              }
            } finally {
              // Never leave the submit button spinning if a request fails or times out.
              if (ctx.mounted && saving) setSheet(() => saving = false);
            }
          }, icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send), label: Text(saving ? tr('Изпращане…','Sending…') : tr('Изпрати заявка','Submit request')))),
        ])),
      )),
    );
    model.dispose(); problem.dispose(); otherDevice.dispose();
  }


  Future<List<Repair>> _loadRepairsFuture() async {
    final token = await auth.token;
    if (token == null) throw Exception(tr('Сесията е изтекла. Влезте отново.', 'Session expired. Please sign in again.'));
    return api.getRepairs(token);
  }

  String _statusLabel(String s) {
    const bg = {'requested':'Заявка получена','received':'Приет','diagnostics':'Диагностика','waiting_approval':'Очаква одобрение','in_repair':'В ремонт','ready':'Готов','completed':'Приключен','cancelled':'Отменен'};
    const en = {'requested':'Request received','received':'Received','diagnostics':'Diagnostics','waiting_approval':'Awaiting approval','in_repair':'In repair','ready':'Ready','completed':'Completed','cancelled':'Cancelled'};
    return (english ? en[s] : bg[s]) ?? s;
  }


  Future<void> _changeRepairStatus(Repair repair, BuildContext sheetContext) async {
    final noteController = TextEditingController();
    const statuses = ['requested', 'received', 'diagnostics', 'waiting_approval', 'in_repair', 'ready', 'completed', 'cancelled'];
    var selected = repair.status;
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(tr('Промяна на статуса', 'Update repair status')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: tr('Нов статус', 'New status')),
                items: statuses.map((status) => DropdownMenuItem(
                  value: status,
                  child: Text(_statusLabel(status)),
                )).toList(),
                onChanged: (value) {
                  if (value != null) refresh(() => selected = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: tr('Бележка към историята (по желание)', 'History note (optional)'),
                  hintText: tr('Напр. извършена диагностика…', 'E.g. diagnostics completed…'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('Запази', 'Save'))),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      noteController.dispose();
      return;
    }
    final token = await auth.token;
    if (token == null) {
      noteController.dispose();
      if (mounted) _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tr('Сесията е изтекла. Влезте отново.', 'Session expired. Please sign in again.'))));
      return;
    }
    try {
      final result = await api.updateRepairStatus(token, repair.id, selected, note: noteController.text.trim());
      noteController.dispose();
      if (!mounted || !sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      setState(() => repairsFuture = _loadRepairsFuture());
      if (result.pendingSync) {
        _refreshPendingSyncCount(token);
        _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tr('Няма интернет. Промяната е запазена и чака синхронизация.', 'Offline. The change is saved and waiting to sync.'))));
      } else {
        _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tr('Статусът на ремонта е обновен.', 'Repair status updated.'))));
      }
    } catch (e) {
      noteController.dispose();
      if (mounted) _messengerKey.currentState?.showSnackBar(SnackBar(content: Text('${tr('Неуспешна промяна:', 'Update failed:')} $e')));
    }
  }

  Future<void> _showRatingDialog({required String type, int repairId = 0}) async {
    final token = await auth.token;
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      _message(tr('Влезте в профила си, за да изпратите оценка.', 'Sign in to submit a rating.'));
      return;
    }
    Map<String, dynamic> config;
    try { config = await api.getRatingConfig(); }
    catch (e) { _message('${tr('Оценките временно не са достъпни:', 'Ratings are temporarily unavailable:')} $e'); return; }
    if (config['enabled'] != true) {
      _message(tr('Системата за оценки временно е изключена.', 'The rating system is currently disabled.'));
      return;
    }
    var stars = 5;
    final comment = TextEditingController();
    var saving = false;
    final submitted = await showDialog<bool>(
      context: _navigatorKey.currentContext!,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: Text(type == 'repair' ? tr('Оцени ремонта', 'Rate this repair') : tr('Оцени PCWork', 'Rate PCWork')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Колко звезди заслужава?', 'How many stars would you give?')),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (index) => IconButton(onPressed: saving ? null : () => setDialogState(() => stars = index + 1), icon: Icon(index < stars ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFFFC857), size: 32)))),
          TextField(controller: comment, enabled: !saving, maxLines: 3, maxLength: 500, decoration: InputDecoration(hintText: tr('Коментар (по желание)', 'Comment (optional)'), border: const OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ', 'Cancel'))),
          FilledButton(onPressed: saving ? null : () async {
            setDialogState(() => saving = true);
            try {
              await api.submitRating(token, type: type, stars: stars, repairId: repairId, comment: comment.text.trim());
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            } catch (e) {
              setDialogState(() => saving = false);
              _message('${tr('Неуспешно изпращане:', 'Could not submit rating:')} $e');
            }
          }, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('Изпрати', 'Submit'))),
        ],
      )),
    );
    comment.dispose();
    if (submitted == true && mounted) {
      _message(tr('Благодарим за оценката!', 'Thank you for your rating!'));
      final googleUrl = (config['google_review_url'] ?? '').toString().trim();
      if (type == 'repair' && googleUrl.isNotEmpty) {
        final uri = Uri.tryParse(googleUrl);
        if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
          final openGoogle = await showDialog<bool>(context: _navigatorKey.currentContext!, builder: (ctx) => AlertDialog(title: Text(tr('Оценка в Google', 'Google review')), content: Text(tr('Желаете ли да оставите и публичен отзив за сервиза в Google?', 'Would you also like to leave a public Google review for the service?')), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('По-късно', 'Later'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Отвори Google', 'Open Google')))]));
          if (openGoogle == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    }
  }

  Future<void> _editRepairEstimate(Repair repair, String token, BuildContext sheetContext, VoidCallback refresh) async {
    final description = TextEditingController();
    final total = TextEditingController();
    final days = TextEditingController(text: '3');
    final valid = TextEditingController(text: DateTime.now().add(const Duration(days: 7)).toIso8601String().substring(0, 10));
    String? error;
    final saved = await showDialog<bool>(context: sheetContext, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
      title: Text(tr('Оферта за ремонт', 'Repair estimate')),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: description, minLines: 3, maxLines: 5, decoration: InputDecoration(labelText: tr('Описание на ремонта и включените дейности*', 'Repair scope and included work*'), border: const OutlineInputBorder())),
        const SizedBox(height: 10), TextField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('Крайна цена (EUR)*', 'Total price (EUR)*'), border: const OutlineInputBorder())),
        const SizedBox(height: 10), TextField(controller: days, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Очакван срок (дни)', 'Estimated time (days)'), border: const OutlineInputBorder())),
        const SizedBox(height: 10), TextField(controller: valid, decoration: InputDecoration(labelText: tr('Офертата е валидна до (ГГГГ-ММ-ДД)', 'Offer valid until (YYYY-MM-DD)'), border: const OutlineInputBorder())),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Отказ', 'Cancel'))), FilledButton(onPressed: () {
        final amount = double.tryParse(total.text.trim().replaceAll(',', '.'));
        final dayCount = int.tryParse(days.text.trim().isEmpty ? '0' : days.text.trim());
        final validDate = DateTime.tryParse(valid.text.trim());
        if (description.text.trim().isEmpty || amount == null || amount <= 0 || dayCount == null || dayCount < 0 || dayCount > 365 || validDate == null || validDate.toIso8601String().substring(0, 10) != valid.text.trim() || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(valid.text.trim())) { setDialog(() => error = tr('Проверете описанието, сумата, срока и датата на валидност.', 'Check the description, amount, duration and validity date.')); return; }
        Navigator.pop(dialogContext, true);
      }, child: Text(tr('Изпрати офертата', 'Send estimate')))],
    )));
    if (saved == true && mounted) {
      try {
        await api.createRepairEstimate(token, repair.id, description: description.text.trim(), total: double.parse(total.text.trim().replaceAll(',', '.')), estimatedDays: int.parse(days.text.trim().isEmpty ? '0' : days.text.trim()), validUntil: valid.text.trim());
        refresh();
        _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tr('Офертата е изпратена към клиента.', 'Estimate sent to the customer.'))));
      } catch (e) { _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    }
    description.dispose(); total.dispose(); days.dispose(); valid.dispose();
  }

  Future<void> _decideRepairEstimate(Repair repair, String token, String decision, VoidCallback refresh) async {
    final accepted = decision == 'accepted';
    final confirmed = await showDialog<bool>(context: _navigatorKey.currentContext!, builder: (ctx) => AlertDialog(
      title: Text(accepted ? tr('Одобряване на офертата', 'Approve estimate') : tr('Отказ от офертата', 'Decline estimate')),
      content: Text(accepted ? tr('Потвърждавате ли, че одобрявате цената и описаните дейности? След одобрение ремонтът преминава към изпълнение.', 'Do you approve the quoted price and work? After approval, the repair moves to the work stage.') : tr('Сигурни ли сте, че отказвате офертата? Ремонтът ще бъде върнат за диагностика и евентуална нова оферта.', 'Are you sure you want to decline? The repair will return to diagnostics for possible revision.')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Назад', 'Back'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(accepted ? tr('Одобрявам', 'Approve') : tr('Отказвам', 'Decline')))],
    ));
    if (confirmed != true) return;
    try {
      await api.decideRepairEstimate(token, repair.id, decision: decision);
      refresh();
      _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(accepted ? tr('Офертата е одобрена. Ремонтът може да започне.', 'Estimate approved. The repair can proceed.') : tr('Офертата е отказана. Сервизът може да подготви нова.', 'Estimate declined. The service team can prepare a revision.'))));
    } catch (e) { _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
  }

  void _showRepairDetails(Repair repair) async {
    final token = await auth.token;
    if (token == null || !mounted) return;
    Future<Repair> detailFuture = api.getRepair(token, repair.id);
    Future<Map<String, dynamic>?> estimateFuture = api.getRepairEstimate(token, repair.id);
    final customerWorklogFuture = api.getRepairWorklog(token, repair.id);
    StateSetter? updateSheet;
    final trackingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || updateSheet == null) return;
      updateSheet!(() { detailFuture = api.getRepair(token, repair.id); estimateFuture = api.getRepairEstimate(token, repair.id); });
    });
    await showModalBottomSheet<void>(context: _navigatorKey.currentState!.overlay!.context, isScrollControlled: true, backgroundColor: PCWorkColors.midnight, barrierColor: Colors.black.withValues(alpha: .68), showDragHandle: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), builder: (ctx) => StatefulBuilder(builder: (sheetContext, setSheetState) {
      updateSheet = setSheetState;
      return Theme(data: PCWorkTheme.build(dark: true), child: FutureBuilder<Repair>(future: detailFuture, builder: (context, snap) {
      // Show the already-loaded repair immediately; fetch the history/details
      // in the background instead of blocking the whole sheet with a spinner.
      final r = snap.data ?? repair;
      final currentUser = signedInUser;
      final roles = currentUser?.roles ?? const <String>[];
      final isStaff = (roles.any((role) => ['administrator','pcwork_staff','shop_manager','editor'].contains(role)) && !showClientPreview) || showStaffPreview;
      return SizedBox(height: MediaQuery.of(ctx).size.height * .82, child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
        PCWorkGlassPanel(glow: true, borderColor: PCWorkColors.cyan.withValues(alpha: .42), padding: const EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const PCWorkGlowIcon(icon: Icons.memory_rounded, size: 43, iconSize: 22, color: PCWorkColors.cyan), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('PCWORK SERVICE', style: TextStyle(color: PCWorkColors.cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.7)), const SizedBox(height: 3), Text(r.number.isEmpty ? 'PCW-${r.id}' : r.number, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: PCWorkColors.textPrimary)), Text('${r.device} ${r.model}'.trim(), style: const TextStyle(fontSize: 12, color: PCWorkColors.textSecondary))])), const Icon(Icons.verified_rounded, color: PCWorkColors.success, size: 21)]),
          const SizedBox(height: 14), Wrap(spacing: 7, runSpacing: 7, children: [Chip(avatar: const Icon(Icons.circle, size: 9, color: PCWorkColors.cyan), label: Text(_statusLabel(r.status))), if (r.fromCache) Chip(avatar: const Icon(Icons.cloud_off, size: 16), label: Text(tr('Офлайн копие', 'Offline copy'))), if (isStaff) Chip(avatar: const Icon(Icons.flag_outlined, size: 16), label: Text(_priorityLabel(r.priority)))]),
          if (snap.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          if (snap.hasError) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('Показваме наличните данни; историята не можа да се обнови.', 'Showing available details; repair history could not be refreshed.'), style: const TextStyle(color: PCWorkColors.warning, fontSize: 12))),
        ])),
        const SizedBox(height: 16), _repairSectionHeading(tr('Информация за устройството', 'Device information'), Icons.devices_other_rounded),
        PCWorkGlassPanel(padding: const EdgeInsets.all(15), child: Column(children: [_detailRow(tr('Устройство','Device'), '${r.device} ${r.model}'), _detailRow(tr('Сервизен обект','Service location'), r.location), _detailRow(tr('Проблем','Reported issue'), r.problem), _detailRow(tr('Плащане','Payment'), '${r.paymentMethod == 'cash_courier' ? tr('В брой чрез куриер','Cash to courier') : tr('В брой на място','Cash on site')} · ${r.paymentStatus == 'paid' ? tr('Платено','Paid') : tr('Неплатено','Unpaid')}')])),
        if (r.status == 'diagnostics' || r.history.any((h) => h.status == 'diagnostics')) ...[
          const SizedBox(height: 15), _repairSectionHeading(tr('Диагностика', 'Diagnostics'), Icons.manage_search_rounded),
          PCWorkGlassPanel(borderColor: PCWorkColors.violet.withValues(alpha: .45), padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('Първоначално описание', 'Reported symptoms'), style: const TextStyle(color: PCWorkColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)), const SizedBox(height: 5), Text(r.problem.isEmpty ? tr('Няма допълнително описание.', 'No additional description provided.') : r.problem, style: const TextStyle(color: PCWorkColors.textPrimary, height: 1.4)), if (isStaff) ...r.history.where((h) => h.status == 'diagnostics' && h.note.trim().isNotEmpty).map((h) => Padding(padding: const EdgeInsets.only(top: 10), child: Container(width: double.infinity, padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: PCWorkColors.violet.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: Text(h.note, style: const TextStyle(color: PCWorkColors.textSecondary, fontSize: 12, height: 1.4)))))])),
        ], if (isStaff && r.paymentStatus != 'paid') Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: OutlinedButton.icon(onPressed: () async { try { await api.updateRepairPayment(token, r.id, paid: true); updateSheet?.call(() => detailFuture = api.getRepair(token, r.id)); if (ctx.mounted) _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tr('Плащането е отбелязано като получено.','Payment marked as received.')))); } catch (e) { if (ctx.mounted) _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); } }, icon: const Icon(Icons.payments_outlined), label: Text(tr('Отбележи плащането като получено','Mark payment as received')))), FutureBuilder<Map<String, dynamic>?>(future: estimateFuture, builder: (context, estimateSnap) {
        if (estimateSnap.connectionState == ConnectionState.waiting && estimateSnap.data == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(minHeight: 2));
        if (estimateSnap.hasError) return Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(tr('Офертата не е достъпна', 'Estimate unavailable')), trailing: IconButton(onPressed: () => updateSheet?.call(() => estimateFuture = api.getRepairEstimate(token, r.id)), icon: const Icon(Icons.refresh))));
        final estimate = estimateSnap.data;
        if (estimate == null) return isStaff && !['completed','cancelled','ready'].contains(r.status) ? Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: OutlinedButton.icon(onPressed: () => _editRepairEstimate(r, token, ctx, () => updateSheet?.call(() { estimateFuture = api.getRepairEstimate(token, r.id); detailFuture = api.getRepair(token, r.id); })), icon: const Icon(Icons.request_quote_outlined), label: Text(tr('Изготви оферта за клиента', 'Prepare customer estimate')))) : const SizedBox.shrink();
        final estimateStatus = (estimate['status'] ?? '').toString();
        final pending = estimateStatus == 'pending';
        final items = (estimate['line_items'] as List? ?? const []).whereType<Map>().toList();
        return Card(margin: const EdgeInsets.symmetric(vertical: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.request_quote_outlined, color: cyan), const SizedBox(width: 8), Expanded(child: Text(tr('Оферта за ремонт', 'Repair estimate'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), Chip(label: Text(estimateStatus == 'pending' ? tr('Чака решение', 'Awaiting decision') : estimateStatus == 'accepted' ? tr('Одобрена', 'Approved') : estimateStatus == 'declined' ? tr('Отказана', 'Declined') : estimateStatus == 'expired' ? tr('Изтекла', 'Expired') : tr('Заменена', 'Superseded')))]), const SizedBox(height: 8), Text((estimate['description'] ?? '').toString()), const SizedBox(height: 8), if (items.isNotEmpty) ...items.map((item) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• ${(item['description'] ?? '').toString()} · ${item['amount'] ?? 0} EUR'))), Text('${tr('Крайна цена', 'Total')}: ${(estimate['total'] ?? 0)} ${(estimate['currency'] ?? 'EUR')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), if ((estimate['estimated_days'] as num?)?.toInt() != null && (estimate['estimated_days'] as num).toInt() > 0) Text('${tr('Очакван срок', 'Estimated time')}: ${estimate['estimated_days']} ${tr('дни', 'days')}'), if ((estimate['valid_until'] ?? '').toString().isNotEmpty) Text('${tr('Валидна до', 'Valid until')}: ${estimate['valid_until']}'), if (pending && !isStaff) ...[const SizedBox(height: 10), Row(children: [Expanded(child: OutlinedButton(onPressed: () => _decideRepairEstimate(r, token, 'declined', () => updateSheet?.call(() { estimateFuture = api.getRepairEstimate(token, r.id); detailFuture = api.getRepair(token, r.id); })), child: Text(tr('Откажи', 'Decline')))), const SizedBox(width: 8), Expanded(child: FilledButton(onPressed: () => _decideRepairEstimate(r, token, 'accepted', () => updateSheet?.call(() { estimateFuture = api.getRepairEstimate(token, r.id); detailFuture = api.getRepair(token, r.id); })), child: Text(tr('Одобри офертата', 'Approve estimate'))))])], if (pending && isStaff) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _editRepairEstimate(r, token, ctx, () => updateSheet?.call(() { estimateFuture = api.getRepairEstimate(token, r.id); detailFuture = api.getRepair(token, r.id); })), icon: const Icon(Icons.edit_outlined), label: Text(tr('Изпрати нова версия', 'Send revised estimate')))), if (!pending && isStaff && !['completed','cancelled','ready'].contains(r.status)) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _editRepairEstimate(r, token, ctx, () => updateSheet?.call(() { estimateFuture = api.getRepairEstimate(token, r.id); detailFuture = api.getRepair(token, r.id); })), icon: const Icon(Icons.request_quote_outlined), label: Text(tr('Изпрати нова оферта', 'Send new estimate'))))])));
      }), if (r.dueAt.isNotEmpty) _detailRow(tr('Краен срок','Due date'), _formatDate(r.dueAt)), if (isStaff && r.technicianName.isNotEmpty) _detailRow(tr('Отговорен техник','Assigned technician'), r.technicianName), if (isStaff && !['completed','cancelled'].contains(r.status)) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _changeRepairStatus(r, ctx), icon: const Icon(Icons.sync_alt_rounded), label: Text(tr('Промени статуса на ремонта','Update repair status'))))), if (!isStaff && r.status == 'completed') OutlinedButton.icon(onPressed: () => _showRatingDialog(type: 'repair', repairId: r.id), icon: const Icon(Icons.star_rate_rounded, color: Color(0xFFFFC857)), label: Text(tr('Оцени ремонта','Rate this repair'))), OutlinedButton.icon(onPressed: () => _shareRepair(r), icon: const Icon(Icons.share_outlined), label: Text(tr('Сподели информация за ремонта','Share repair information'))), OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: r.number.isEmpty ? 'PCW-${r.id}' : r.number)); if (ctx.mounted) _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tr('Номерът е копиран.','Repair number copied.')))); }, icon: const Icon(Icons.copy), label: Text(tr('Копирай номер','Copy repair number'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairProtocolScreen(repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, device: '${r.device} ${r.model}'.trim(), location: r.location, problem: r.problem, status: _statusLabel(r.status), createdAt: r.createdAt, baseUrl: apiUrl, token: token, repairId: r.id, canEmail: isStaff))); }, icon: const Icon(Icons.qr_code_2), label: Text(tr('Сервизен протокол · QR · PDF','Service protocol · QR · PDF'))),
        OutlinedButton.icon(onPressed: () async { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairEvidenceScreen(baseUrl: apiUrl, token: token, repairId: r.id, repairNumber: r.number, isStaff: isStaff))); }, icon: const Icon(Icons.photo_camera_back_outlined), label: Text(tr('Снимки и подписи','Photos & signatures'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairDocumentsScreen(baseUrl: apiUrl, token: token, repairId: r.id, repairNumber: r.number))); }, icon: const Icon(Icons.folder_open_outlined), label: Text(tr('Преглед на документите','View repair documents'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairWorklogScreen(api: api, token: token, repairId: r.id, repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, isStaff: isStaff))); }, icon: const Icon(Icons.receipt_long_outlined), label: Text(tr('Сервизен дневник · дейности, части и плащания','Service log · work, parts & payments'))), if (isStaff) OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairPartsScreen(api: api, token: token, repairId: r.id, repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, english: english))); }, icon: const Icon(Icons.inventory_2_outlined), label: Text(tr('Резервни части по ремонта','Spare parts for this repair'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairChecklistScreen(api: api, token: token, repairId: r.id, repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, isStaff: isStaff))); }, icon: const Icon(Icons.fact_check_outlined), label: Text(tr('Контролен списък на ремонта','Repair quality checklist'))), if (!isStaff && r.warrantyCards.isNotEmpty) ...[const SizedBox(height: 12), Text(tr('Гаранции на ремонта','Repair warranties'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), ...r.warrantyCards.map((w) => Card(child: ListTile(leading: const Icon(Icons.verified_user_outlined, color: cyan), title: Text((w['title'] ?? tr('Гаранция','Warranty')).toString()), subtitle: Text(tr('Валидна до: ', 'Valid until: ') + (w['valid_until'] ?? '—').toString()), trailing: const Icon(Icons.shield_outlined))))], if (!isStaff) FutureBuilder<Map<String, dynamic>>(future: customerWorklogFuture, builder: (context, logSnap) { if (logSnap.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()); if (logSnap.hasError) return const SizedBox.shrink(); final entries = (logSnap.data?['entries'] as List? ?? const []).whereType<Map>().toList(); if (entries.isEmpty) return const SizedBox.shrink(); return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 12), Text(tr('Извършени дейности','Completed service work'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), ...entries.take(5).map((entry) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.build_circle_outlined, color: cyan), title: Text((entry['description'] ?? '').toString()), subtitle: Text([if ((entry['warranty_until'] ?? '').toString().isNotEmpty) tr('Гаранция до: ', 'Warranty until: ') + entry['warranty_until'].toString(), (entry['created_at'] ?? '').toString()].where((v) => v.isNotEmpty).join(' · '))))]); }), const SizedBox(height: 18), Row(children: [Expanded(child: _repairSectionHeading(tr('Етап на ремонта','Repair progress'), Icons.route_rounded)), const Icon(Icons.sensors_rounded, color: PCWorkColors.cyan, size: 16), const SizedBox(width: 5), const Text('LIVE · 30s', style: TextStyle(fontSize: 10, color: PCWorkColors.cyan, fontWeight: FontWeight.w900))]), PCWorkGlassPanel(padding: const EdgeInsets.fromLTRB(15, 13, 15, 13), child: _repairProgress(r.status)), const SizedBox(height: 18), _repairSectionHeading(tr('История на ремонта','Repair history'), Icons.history_rounded), if (r.history.isEmpty) PCWorkGlassPanel(child: Text(tr('Няма записана история.','No history recorded yet.'), style: const TextStyle(color: PCWorkColors.textSecondary))), if (r.history.isNotEmpty) PCWorkGlassPanel(padding: const EdgeInsets.fromLTRB(15, 12, 15, 12), child: Column(children: r.history.asMap().entries.map((entry) { final h = entry.value; final last = entry.key == r.history.length - 1; return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 24, child: Column(children: [Container(width: 11, height: 11, decoration: BoxDecoration(shape: BoxShape.circle, color: last ? PCWorkColors.cyan : PCWorkColors.electricBlue, boxShadow: [BoxShadow(color: PCWorkColors.cyan.withValues(alpha: .28), blurRadius: 8)])), if (!last) Container(width: 2, height: 47, color: PCWorkColors.electricBlue.withValues(alpha: .3))])), const SizedBox(width: 9), Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_statusLabel(h.status), style: const TextStyle(color: PCWorkColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)), if (isStaff && h.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(h.note, style: const TextStyle(color: PCWorkColors.textSecondary, fontSize: 11, height: 1.35))), if (h.createdAt.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(h.createdAt, style: const TextStyle(color: PCWorkColors.textMuted, fontSize: 10)))])))]); }).toList()))]));
    }));
    }));
    trackingTimer.cancel();
  }

  Widget _repairSectionHeading(String title, IconData icon) => Padding(padding: const EdgeInsets.only(bottom: 9), child: Row(children: [Icon(icon, color: PCWorkColors.cyan, size: 19), const SizedBox(width: 9), Text(title, style: const TextStyle(color: PCWorkColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -.2))]));

  Widget _repairProgress(String status) {
    const steps = ['requested','received','diagnostics','waiting_approval','in_repair','ready','completed'];
    final index = steps.indexOf(status);
    if (status == 'cancelled') return Chip(avatar: const Icon(Icons.cancel_outlined, color: PCWorkColors.danger), label: Text(_statusLabel(status)));
    return Column(children: steps.asMap().entries.map((entry) {
      final active = index >= entry.key;
      final current = entry.key == index;
      return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
        Container(width: 27, height: 27, decoration: BoxDecoration(shape: BoxShape.circle, color: active ? PCWorkColors.cyan.withValues(alpha: .16) : Colors.white.withValues(alpha: .035), border: Border.all(color: active ? PCWorkColors.cyan.withValues(alpha: .8) : Colors.white24)), child: Icon(active ? Icons.check_rounded : Icons.circle_outlined, color: active ? PCWorkColors.cyan : PCWorkColors.textMuted, size: 15)),
        const SizedBox(width: 11), Expanded(child: Text(_statusLabel(entry.value), style: TextStyle(color: active ? PCWorkColors.textPrimary : PCWorkColors.textMuted, fontWeight: current ? FontWeight.w900 : FontWeight.w600, fontSize: 12))),
        if (current) Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: PCWorkColors.cyan.withValues(alpha: .12), borderRadius: BorderRadius.circular(20), border: Border.all(color: PCWorkColors.cyan.withValues(alpha: .35))), child: Text(tr('ТЕКУЩ', 'CURRENT'), style: const TextStyle(color: PCWorkColors.cyan, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .5))),
      ]));
    }).toList());
  }

  Widget _detailRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 125, child: Text(label, style: const TextStyle(color: PCWorkColors.textMuted))), Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(color: PCWorkColors.textPrimary)))]));

  Widget _booking() => BookingScreen(
    api: api,
    tokenProvider: _uiToken,
    location: selectedLocation,
    onChooseLocation: _showLocations,
    english: english,
  );

  Future<void> _openSyncCenter() async {
    if (!isAdministrator || !mounted) return;
    final token = await auth.token;
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      _message(tr('Няма активна администраторска сесия.', 'No active administrator session.'));
      return;
    }
    await _navigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => SyncCenterScreen(
        api: api,
        token: token,
        english: english,
        autoSyncEnabled: _autoSyncEnabled,
        onAutoSyncChanged: _setAutoSyncEnabled,
        onOpenCacheMonitor: _openCacheMonitor,
      ),
    ));
  }



  Widget _profile() => ListView(padding: const EdgeInsets.all(20), children: [
    CircleAvatar(radius: 38, child: Icon(visibleUser == null ? Icons.person_outline : Icons.verified_user, size: 40, color: cyan)),
    const SizedBox(height: 14),
    Text(visibleUser?.name ?? tr('Вашият PCWork профил', 'Your PCWork account'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text(visibleUser?.email ?? tr('Влезте или създайте профил, за да виждате ремонтите си.', 'Sign in or create an account to access your repairs.')),
    if (visibleUser != null && visibleUser!.phone.isNotEmpty) ...[const SizedBox(height: 5), Text(visibleUser!.phone, style: TextStyle(color: isDarkTheme ? Colors.white60 : const Color(0xFF68778B)))],
    if (visibleUser != null) ...[
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: _editCustomerProfile, icon: const Icon(Icons.edit_outlined), label: Text(tr('Редактирай профила','Edit profile'))),
      const SizedBox(height: 12), Card(child: ListTile(leading: const Icon(Icons.badge_outlined, color: cyan), title: Text(tr('Тип профил', 'Account type')), subtitle: Text(visibleUser!.roles.any((r) => ['pcwork_customer','customer','subscriber'].contains(r)) ? tr('Потребител', 'Customer') : visibleUser!.roles.join(', ')))),
      if (isAdministrator) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _openVisitorAnalytics, icon: const Icon(Icons.analytics_outlined), label: Text(tr('Данни на посетителите', 'Visitor analytics'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _openSyncCenter, icon: const Icon(Icons.sync_alt_rounded), label: Text(tr('Център за синхронизация', 'Synchronization center'))),
      ],
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.notifications_active_outlined, color: cyan), const SizedBox(width: 10), Expanded(child: Text(tr('Известия от PCWork', 'PCWork notifications'), style: const TextStyle(fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 6),
        Text(tr('Известия за ремонтите и важни сервизни съобщения се управляват от разрешението на телефона.', 'Repair updates and important service messages are controlled by your phone notification permission.'), style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _openNotificationSettings, icon: const Icon(Icons.notifications), label: Text(tr('Настройки на известията', 'Notification settings'))),
        const SizedBox(height: 6),
        if (_pushStatusMessage != null) Padding(padding: const EdgeInsets.only(top:6), child: Text(_pushStatusMessage!, style: const TextStyle(fontSize:11))),
        const Divider(),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _marketingOptIn, onChanged: _marketingPreferenceLoaded ? _setMarketingPreference : null, title: Text(tr('Промоции и новини', 'Promotions and news')), subtitle: Text(tr('По желание. Съгласието е отделно от известията за ремонт и може да бъде оттеглено по всяко време.', 'Optional. This consent is separate from repair updates and can be withdrawn at any time.'))),
      ]))),
      OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: Text(tr('Изход', 'Sign out'))),
    ] else ...[
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: authBusy ? null : () => _openAuthScreen(register: false), icon: const Icon(Icons.login), label: Text(tr('Вход с имейл', 'Sign in with email'))),
      OutlinedButton.icon(onPressed: authBusy ? null : () => _openAuthScreen(register: true), icon: const Icon(Icons.person_add_alt_1), label: Text(tr('Създай профил', 'Create account'))),
      const SizedBox(height: 10),
      Text(tr('Входът е с еднократен код по имейл; за избрани профили администраторът може да разреши и вход с WordPress парола. Не използваме SMS или Viber.', 'Sign-in uses email one-time codes; an administrator may also enable WordPress password login for selected accounts. No SMS or Viber is used.'), style: TextStyle(color: isDarkTheme ? Colors.white60 : Colors.black54)),
    ],
    if (visibleUser != null && canSeeStaffUi) ...[
      const SizedBox(height: 16),
      Text(tr('Достъпът за запис се проверява допълнително от WordPress според служебните права и сервизния обект.', 'WordPress separately verifies staff permissions and location access.'), style: TextStyle(color: isDarkTheme ? Colors.white54 : Colors.black54, fontSize: 12)),
    ],
    const SizedBox(height: 18), OutlinedButton.icon(onPressed: _showSettings, icon: const Icon(Icons.settings), label: Text(tr('Настройки на приложението', 'App settings'))),
  ]);

  Future<void> _editCustomerProfile() async {
    if (!mounted) return;
    final user = signedInUser;
    if (user == null) {
      _message(tr('Влезте в профила си, за да редактирате данните.', 'Sign in to edit your profile.'));
      return;
    }
    final email = TextEditingController(text: user.email);
    final phone = TextEditingController(text: user.phone.isNotEmpty ? user.phone : (user.billing['phone'] ?? '').toString());
    final b = user.billing;
    final registrationNameParts = user.name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final first = TextEditingController(text: (b['first_name'] ?? (registrationNameParts.isNotEmpty ? registrationNameParts.first : '')).toString());
    final last = TextEditingController(text: (b['last_name'] ?? (registrationNameParts.length > 1 ? registrationNameParts.skip(1).join(' ') : '')).toString());
    final address = TextEditingController(text: (b['address_1'] ?? '').toString());
    final city = TextEditingController(text: (b['city'] ?? '').toString());
    String courier = (b['courier'] ?? '').toString().toLowerCase();
    if (!['econt', 'speedy', 'pigeon'].contains(courier)) courier = '';

    Timer? saveTimer;
    var dirty = false;
    var saving = false;
    var revision = 0;
    var saveMessage = tr('Промените се записват автоматично.', 'Changes are saved automatically.');
    var saveError = false;
    late void Function(void Function()) setDialogState;

    Future<bool> saveProfile() async {
      if (saving) return false;
      if (!dirty) return true;
      if (first.text.trim().isEmpty || last.text.trim().isEmpty || city.text.trim().isEmpty || address.text.trim().isEmpty || courier.isEmpty || phone.text.trim().length < 6 || phone.text.trim().length > 30 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) {
        setDialogState(() { saveMessage = tr('Всички полета са задължителни. Проверете име, фамилия, град/село, адрес, куриер, телефон и регистрационен имейл.', 'All fields are required. Check first name, last name, city, address, courier, phone, and registration email.'); saveError = true; });
        return false;
      }
      saving = true;
      dirty = false;
      final savingRevision = revision;
      var saveFailed = false;
      setDialogState(() { saveMessage = tr('Записване…', 'Saving…'); saveError = false; });
      try {
        final updated = await auth.updateProfile(
          name: [first.text.trim(), last.text.trim()].where((v) => v.isNotEmpty).join(' ').isNotEmpty ? [first.text.trim(), last.text.trim()].where((v) => v.isNotEmpty).join(' ') : user.name,
          phone: phone.text,
          billing: {
            'first_name': first.text, 'last_name': last.text,
            'address_1': address.text, 'city': city.text, 'country': 'BG',
            'phone': phone.text, 'courier': courier,
          },
          shipping: {
            'first_name': first.text, 'last_name': last.text,
            'address_1': address.text, 'city': city.text, 'country': 'BG', 'courier': courier,
          },
        );
        if (mounted) setState(() => signedInUser = updated);
        if (revision == savingRevision) {
          setDialogState(() { saveMessage = tr('Всички промени са записани.', 'All changes saved.'); saveError = false; });
        } else {
          dirty = true;
        }
      } catch (error) {
        dirty = true;
        saveFailed = true;
        setDialogState(() { saveMessage = '${tr('Грешка при запис: ', 'Save error: ')}$error'; saveError = true; });
      } finally {
        saving = false;
        if (dirty && revision != savingRevision && !saveFailed) {
          saveTimer?.cancel();
          saveTimer = Timer(const Duration(milliseconds: 500), () => saveProfile());
        }
      }
      return !dirty && !saveError;
    }

    void markChanged() {
      revision++;
      dirty = true;
      setDialogState(() { saveMessage = tr('Има незаписани промени…', 'Changes pending…'); saveError = false; });
      saveTimer?.cancel();
      saveTimer = Timer(const Duration(milliseconds: 900), () => saveProfile());
    }

    final navigatorContext = _navigatorKey.currentState?.overlay?.context;
    if (navigatorContext == null) return;
    final closed = await showDialog<bool>(context: navigatorContext, barrierDismissible: true, builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, updateDialog) {
        setDialogState = updateDialog;
        Widget field(TextEditingController controller, String label, {TextInputType? keyboardType, bool locked = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: TextField(controller: controller, readOnly: locked, keyboardType: keyboardType,
            onChanged: locked ? null : (_) => markChanged(),
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)),
        );
        return AlertDialog(
          title: Text(tr('Редакция на профила', 'Edit profile')),
          content: SizedBox(width: MediaQuery.of(ctx).size.width < 700 ? double.maxFinite : 620, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            field(first, tr('Име *', 'First name *')),
            field(last, tr('Фамилия *', 'Last name *')),
            field(city, tr('Град/село *', 'City/village *')),
            field(address, tr('Личен адрес или офис / Box на куриер *', 'Home address or courier office / Box *')),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: Text(tr('Избор на куриер *', 'Choose courier *'), style: const TextStyle(fontWeight: FontWeight.w600))),
            RadioGroup<String>(
              groupValue: courier,
              onChanged: (value) { courier = value ?? ''; markChanged(); updateDialog(() {}); },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ...[
                  ('econt', 'Econt'), ('speedy', 'Speedy'), ('pigeon', 'Pigeon'),
                ].map((option) => RadioListTile<String>(
                  dense: true, contentPadding: EdgeInsets.zero, value: option.$1,
                  title: Text(option.$2),
                )),
              ]),
            ),
            field(phone, tr('Телефон *', 'Phone *'), keyboardType: TextInputType.phone),
            field(email, tr('Email * (заключен)', 'Email * (locked)'), locked: true),
            Align(alignment: Alignment.centerLeft, child: Text(tr('Email се попълва автоматично от регистрацията и не може да се редактира.', 'Email is filled automatically from registration and cannot be edited.'), style: const TextStyle(fontSize: 11, color: Colors.grey))),
            const SizedBox(height: 8),
            Row(children: [Icon(saveError ? Icons.error_outline : Icons.cloud_done_outlined, size: 17, color: saveError ? Colors.redAccent : cyan), const SizedBox(width: 7), Expanded(child: Text(saveMessage, style: TextStyle(fontSize: 12, color: saveError ? Colors.redAccent : (isDarkTheme ? Colors.white60 : Colors.black54))))]),
          ]))),
          actions: [
            TextButton(onPressed: saving ? null : () async {
              saveTimer?.cancel();
              if (dirty) {
                final ok = await saveProfile();
                if (!ok || dirty || !dialogContext.mounted) return;
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            }, child: Text(tr('Готово', 'Done'))),
          ],
        );
      },
    ));
    saveTimer?.cancel();
    // The dialog may have been dismissed by tapping outside; prevent the
    // autosave status callback from calling setState on the disposed dialog.
    setDialogState = (_) {};
    if (closed != false && mounted && dirty) {
      await saveProfile();
    }
    for (final c in [phone, email, first, last, address, city]) { c.dispose(); }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (_) {
      try { await AppSettings.openAppSettings(); } catch (e) { _message('${tr('Неуспешно отваряне на настройките:','Could not open settings:')} $e'); }
    }
  }

  Future<void> _openDeviceMonitor() async {
    await _navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => DeviceMonitorScreen(english: english)));
  }

  Future<void> _openInternalServiceAssistant() async {
    final token = await auth.token;
    if (!mounted) return;
    if (token == null || token.isEmpty || !canSeeStaffUi) {
      _message(tr('Необходим е оторизиран служебен профил.', 'An authorized staff account is required.'));
      return;
    }
    await _navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => InternalServiceAssistantScreen(api: api, token: token, english: english)));
  }

  void _showIntakeForm() async {
    final token = await auth.token;
    if (token == null) { _message(tr('Влезте със служебен профил.', 'Sign in with a staff account.')); return; }
    List<ServiceLocation> options;
    try { options = (await api.getLocations()).where((location) => location.canSelect).toList(); }
    catch (e) { _message('${tr('Неуспешно зареждане на обектите:', 'Could not load locations:')} $e'); return; }
    if (!mounted) return;
    // Existing repair data is used only for local intake assistance; no new
    // customer lookup endpoint or additional personal-data storage is added.
    List<Repair> priorRepairs = const [];
    try { priorRepairs = await api.getRepairs(token); } catch (_) {}
    if (!mounted) return;
    final customerEmail = TextEditingController();
    final customerName = TextEditingController();
    final customerPhone = TextEditingController();
    final deviceType = TextEditingController(text: 'Лаптоп');
    final model = TextEditingController();
    final serial = TextEditingController();
    final problem = TextEditingController();
    final condition = TextEditingController();
    final accessories = TextEditingController();
    final notes = TextEditingController();
    const deviceTypes = ['Лаптоп', 'Настолен компютър', 'PlayStation 5', 'PlayStation 4', 'Xbox', 'Nintendo Switch', 'Монитор', 'Телефон', 'Таблет', 'Друго'];
    ServiceLocation? selected = options.isNotEmpty ? options.first : null;
    bool saving = false;
    bool customerDetailsApplied = false;
    await showModalBottomSheet<void>(context: _navigatorKey.currentState!.overlay!.context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      final normalizedPhone = customerPhone.text.replaceAll(RegExp(r'[^0-9+]'), '');
      final normalizedSerial = serial.text.trim().toLowerCase();
      final customerMatches = normalizedPhone.length >= 6
          ? priorRepairs.where((r) => r.phone.replaceAll(RegExp(r'[^0-9+]'), '') == normalizedPhone).toList()
          : (customerName.text.trim().length >= 4
              ? priorRepairs.where((r) => r.customer.trim().toLowerCase() == customerName.text.trim().toLowerCase()).toList()
              : <Repair>[]);
      final serialMatches = normalizedSerial.isEmpty ? <Repair>[] : priorRepairs.where((r) => r.serial.trim().toLowerCase() == normalizedSerial).toList();
      Widget field(TextEditingController c, String label, {int lines = 1, TextInputType? type, ValueChanged<String>? onChanged}) => Padding(padding: const EdgeInsets.only(bottom: 11), child: TextField(controller: c, maxLines: lines, keyboardType: type, onChanged: onChanged, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
      return Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 18), child: SizedBox(height: MediaQuery.of(ctx).size.height * .86, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(tr('Интелигентен прием на устройство', 'Smart device intake'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
        Text(tr('Проверка за предишни ремонти и възможни дублирани серийни номера.', 'Checks previous repairs and possible duplicate serial numbers.'), style: TextStyle(color: isDarkTheme ? Colors.white60 : Colors.black54)),
        const SizedBox(height: 12),
        Expanded(child: ListView(children: [
          DropdownButtonFormField<ServiceLocation>(initialValue: selected, isExpanded: true, decoration: InputDecoration(labelText: tr('Сервизен обект', 'Service location'), border: const OutlineInputBorder()), items: options.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(), onChanged: (v) => setSheet(() => selected = v)),
          const SizedBox(height: 12),
          field(customerEmail, 'Имейл на клиент*', type: TextInputType.emailAddress),
          field(customerName, 'Име на клиент', onChanged: (_) => setSheet(() { customerDetailsApplied = false; })),
          field(customerPhone, 'Телефон', type: TextInputType.phone, onChanged: (_) => setSheet(() { customerDetailsApplied = false; })),
          if (customerMatches.isNotEmpty) Card(color: Colors.teal.withValues(alpha: .10), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.history, color: Color(0xFF21D4D8)), const SizedBox(width: 8), Expanded(child: Text(tr('Намерена е предишна сервизна история', 'Previous service history found'), style: const TextStyle(fontWeight: FontWeight.w700)))]),
            const SizedBox(height: 6), Text(tr('${customerMatches.length} предишни ремонта за този клиент.', '${customerMatches.length} previous repairs for this customer.')),
            ...customerMatches.take(3).map((r) => Padding(padding: const EdgeInsets.only(top: 5), child: Text('• ${r.number} · ${r.device} ${r.model} · ${r.status}', style: const TextStyle(fontSize: 12)))),
            if (!customerDetailsApplied && customerName.text.trim().isEmpty && customerMatches.first.customer.isNotEmpty) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => setSheet(() { customerName.text = customerMatches.first.customer; customerDetailsApplied = true; }), icon: const Icon(Icons.person_add_alt_1), label: Text(tr('Попълни името', 'Fill customer name')))),
          ]))),
          const Divider(height: 24),
          DropdownButtonFormField<String>(initialValue: deviceTypes.contains(deviceType.text) ? deviceType.text : 'Друго', isExpanded: true, decoration: InputDecoration(labelText: tr('Тип устройство*', 'Device type*'), border: const OutlineInputBorder()), items: deviceTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setSheet(() => deviceType.text = v ?? 'Друго')),
          const SizedBox(height: 12), field(model, 'Марка и модел*'),
          field(serial, 'Сериен номер', onChanged: (_) => setSheet(() {})),
          if (serialMatches.isNotEmpty) Card(color: Colors.orange.withValues(alpha: .12), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 8), Expanded(child: Text('Внимание: сериен номерът вече съществува', style: TextStyle(fontWeight: FontWeight.w700)))]),
            ...serialMatches.take(3).map((r) => Text('• ${r.number} · ${r.customer} · ${r.status}', style: const TextStyle(fontSize: 12))),
          ]))),
          field(problem, 'Описание на проблема*', lines: 3), field(condition, 'Външно състояние', lines: 3),
          field(accessories, 'Комплектовка / аксесоари', lines: 2), field(notes, 'Вътрешни бележки', lines: 2),
        ])),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saving ? null : () async {
          if (selected == null || selected!.code.isEmpty || customerEmail.text.trim().isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(customerEmail.text.trim()) || deviceType.text.trim().isEmpty || model.text.trim().isEmpty || problem.text.trim().isEmpty) { _message(tr('Изберете обект с код и въведете валиден имейл, тип, модел и описание на проблема.', 'Choose a coded location and enter a valid email, device type, model and problem description.')); return; }
          if (serialMatches.isNotEmpty) {
            final proceed = await showDialog<bool>(context: ctx, builder: (dialogContext) => AlertDialog(title: Text(tr('Съвпадащ сериен номер', 'Matching serial number')), content: Text(tr('Този сериен номер присъства в ${serialMatches.length} предишни ремонта. Сигурни ли сте, че искате да продължите с нов прием?', 'This serial number appears in ${serialMatches.length} previous repairs. Are you sure you want to continue with a new intake?')), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Провери отново', 'Review'))), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(tr('Продължи', 'Continue')))]));
            if (proceed != true) return;
          }
          setSheet(() => saving = true);
          try {
            final created = await api.createRepair(token, {
              'customer_email': customerEmail.text.trim(), 'customer_name': customerName.text.trim(), 'customer_phone': customerPhone.text.trim(),
              'location_code': selected!.code, 'location_name': selected!.name,
              'device_type': deviceType.text.trim(), 'device_model': model.text.trim(), 'serial_number': serial.text.trim(),
              'problem_description': problem.text.trim(), 'external_condition': condition.text.trim(), 'accessories': accessories.text.trim(), 'intake_notes': notes.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            setState(() => repairsFuture = _loadRepairsFuture());
            if (created['queued'] == true) {
              _refreshPendingSyncCount(token);
              _message(tr('Няма интернет. Приемът е запазен на устройството и ще се изпрати автоматично при връзка.', 'Offline. Intake was saved on this device and will sync automatically when connected.'));
            } else {
              _message('${tr('Ремонтът е регистриран:', 'Repair created:')} ${created['repair_number'] ?? ''}');
            }
          } catch (e) { _message('${tr('Грешка при приемане:', 'Intake failed:')} $e'); setSheet(() => saving = false); }
        }, icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: Text(saving ? tr('Записване…', 'Saving…') : tr('Създай сервизен протокол', 'Create repair record')))),
      ])));
    }));
    for (final c in [customerEmail, customerName, customerPhone, deviceType, model, serial, problem, condition, accessories, notes]) { c.dispose(); }
  }

  Future<void> _logout() async {
    final bearer = await auth.token;
    if (bearer != null) {
      var remaining = await api.pendingOperationCount(bearer);
      if (remaining > 0) {
        await _syncOfflineQueue();
        remaining = await api.pendingOperationCount(bearer);
      }
      await push.unregister(bearer);
      if (remaining == 0) {
        await api.clearOfflineData(bearer);
      } else {
        _message(tr('Остават $remaining операции. Те са запазени защитено и ще се синхронизират при следващ вход със същия профил.', 'There are $remaining pending operations. They are stored securely and will sync the next time you sign in to this account.'));
      }
    }
    _offlineSyncTimer?.cancel();
    await auth.logout();
    if (mounted) setState(() { signedInUser = null; repairsFuture = null; _pendingSyncCount = 0; });
  }

  Future<void> _openAuthScreen({required bool register}) async {
    if (authBusy || !mounted) return;
    setState(() => authBusy = true);
    try {
      final user = await _navigatorKey.currentState!.push<AuthUser>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AuthScreen(
            baseUrl: apiUrl,
            english: english,
            initialRegister: register,
          ),
        ),
      );
      if (!mounted || user == null) return;
      final bearer = await auth.token;
      if (!mounted) return;
      setState(() {
        signedInUser = user;
        _marketingOptIn = false;
        _marketingPreferenceLoaded = false;
        repairsFuture = _loadRepairsFuture();
        tab = 5;
        _visitedTabs.add(5);
      });
      if (bearer != null && bearer.isNotEmpty) {
        unawaited(_loadMarketingPreference(bearer));
        unawaited(_enablePush(knownToken: bearer));
        _startOfflineSync(bearer);
      }
      _message(tr('Успешен вход в PCWork.', 'Successfully signed in to PCWork.'));
    } catch (error) {
      if (mounted) _message('${tr('Неуспешно отваряне на профила:', 'Could not open account:')} $error');
    } finally {
      if (mounted) setState(() => authBusy = false);
    }
  }

  Widget _homeSignInCard() => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: authBusy ? null : () => _openAuthScreen(register: false),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cyan.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.lock_open_rounded, color: cyan),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Влез в своя профил', 'Sign in to your account'),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(
                        tr('Проследявай ремонтите и поръчките си.', 'Track your repairs and orders.'),
                        style: TextStyle(color: isDarkTheme ? Colors.white60 : Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: cyan),
              ],
            ),
          ),
        ),
      );

  Widget _homeAccountDashboard() {
    final future = repairsFuture;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: cyan.withValues(alpha: .13), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.dashboard_customize_rounded, color: cyan)),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('ТВОЯТ PCWORK DASHBOARD', 'YOUR PCWORK DASHBOARD'), style: const TextStyle(color: cyan, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w900)),
                Text(tr('Здравей, ${visibleUser?.name ?? ''}', 'Welcome, ${visibleUser?.name ?? ''}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ])),
              IconButton(tooltip: tr('Обнови таблото', 'Refresh dashboard'), onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()), icon: const Icon(Icons.refresh_rounded, color: cyan)),
            ]),
            const SizedBox(height: 14),
            if (future == null)
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()), icon: const Icon(Icons.sync_rounded), label: Text(tr('Зареди информацията', 'Load dashboard data'))))
            else FutureBuilder<List<Repair>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator(minHeight: 3));
                if (snapshot.hasError) return Row(children: [Expanded(child: Text(tr('Информацията за ремонтите не е достъпна.', 'Repair information is unavailable.'), style: const TextStyle(fontSize: 12, color: Colors.orangeAccent))), IconButton(onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()), icon: const Icon(Icons.refresh, color: cyan))]);
                final rows = List<Repair>.from(snapshot.data ?? const <Repair>[])
                  ..sort((a, b) => _repairDate(b.updatedAt.isNotEmpty ? b.updatedAt : b.createdAt).compareTo(_repairDate(a.updatedAt.isNotEmpty ? a.updatedAt : a.createdAt)));
                final active = rows.where((r) => !['completed', 'cancelled'].contains(r.status)).length;
                final ready = rows.where((r) => r.status == 'ready').length;
                final latest = rows.isEmpty ? null : rows.first;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: _dashboardMetric(tr('Ремонти', 'Repairs'), rows.length, Icons.build_circle_outlined)), const SizedBox(width: 8), Expanded(child: _dashboardMetric(tr('Активни', 'Active'), active, Icons.autorenew_rounded)), const SizedBox(width: 8), Expanded(child: _dashboardMetric(tr('Готови', 'Ready'), ready, Icons.task_alt_rounded))]),
                  if (latest != null) ...[
                    const SizedBox(height: 15),
                    Text(tr('ПОСЛЕДЕН РЕМОНТ', 'LATEST REPAIR'), style: const TextStyle(fontSize: 10, letterSpacing: 1.1, color: Color(0xFF93A4B8), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 7),
                    Container(decoration: BoxDecoration(color: cyan.withValues(alpha: .07), borderRadius: BorderRadius.circular(16), border: Border.all(color: cyan.withValues(alpha: .18))), child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      leading: CircleAvatar(backgroundColor: cyan.withValues(alpha: .13), child: const Icon(Icons.precision_manufacturing_rounded, color: cyan)),
                      title: Text(latest.number.isEmpty ? 'PCW-${latest.id}' : latest.number, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${latest.device} ${latest.model}\n${_statusLabel(latest.status)}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showRepairDetails(latest),
                    )),
                  ] else Padding(padding: const EdgeInsets.only(top: 12), child: Text(tr('Все още нямате регистрирани ремонти.', 'You do not have any registered repairs yet.'), style: const TextStyle(fontSize: 12, color: Color(0xFF93A4B8)))),
                ]);
              },
            ),
            if (canSeeStaffUi) ...[
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _openInternalServiceAssistant, icon: const Icon(Icons.support_agent_rounded), label: Text(tr('Вътрешен сервизен асистент', 'Internal Service Assistant')))),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _dashboardMetric(String label, int value, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
    decoration: BoxDecoration(color: isDarkTheme ? const Color(0xFF172536) : const Color(0xFFF0F5F8), borderRadius: BorderRadius.circular(14)),
    child: Column(children: [Icon(icon, color: cyan, size: 19), const SizedBox(height: 5), Text('$value', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF93A4B8), fontWeight: FontWeight.w600))]),
  );


  Future<void> _openWebsite(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _message(tr('Невалиден адрес.', 'Invalid web address.'));
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _message(tr('Страницата не може да бъде отворена.', 'Could not open the page.'));
    } catch (e) {
      _message('$e');
    }
  }



  void _showLocations() {
    final future = api.getLocations();
    showModalBottomSheet(
      context: _navigatorKey.currentState!.overlay!.context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * .78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.location_city_rounded, color: cyan),
                const SizedBox(width: 9),
                Expanded(child: Text(tr('Избери сервизен обект', 'Choose a service location'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
              ]),
              Text(tr('Показани са всички позиции от страницата Контакти. Обектите с предстоящо откриване са обозначени отделно.',
                  'All entries from the PCWork contact page are shown. Upcoming locations are marked separately.'),
                  style: TextStyle(color: isDarkTheme ? Colors.white60 : Colors.black54, fontSize: 12)),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<ServiceLocation>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cloud_off, size: 36, color: Colors.orangeAccent),
                        const SizedBox(height: 8),
                        Text('${tr('Грешка при зареждане:', 'Could not load locations:')} ${snapshot.error}',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(onPressed: () { Navigator.pop(sheetContext); _showLocations(); },
                            icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново', 'Retry'))),
                      ]));
                    }
                    final rows = snapshot.data ?? [];
                    if (rows.isEmpty) {
                      return Center(child: Text(tr('Няма активни сервизни обекти. Провери WordPress плъгина.',
                          'No active service locations. Check the WordPress plugin.')));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (_, i) {
                        final item = rows[i];
                        final selected = selectedLocation?.code == item.code;
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: selected ? cyan : const Color(0xFF26364A), width: selected ? 1.5 : 1),
                          ),
                          child: Column(children: [
                            SizedBox(
                              height: 142,
                              width: double.infinity,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: item.imageUrl.isNotEmpty
                                    ? Image.network(
                                        item.imageUrl,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (_, __, ___) => _locationImageFallback(),
                                      )
                                    : _locationImageFallback(),
                              ),
                            ),
                            if (item.imageCaption.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 7, 14, 0),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(item.imageCaption,
                                      style: TextStyle(color: isDarkTheme ? Colors.white54 : Colors.black54, fontSize: 10)),
                                ),
                              ),
                            ListTile(
                              onTap: item.canSelect ? () async {
                                setState(() => selectedLocation = item);
                                await _saveLocationPreference(item);
                                if (sheetContext.mounted) Navigator.pop(sheetContext);
                                _message(tr('Избран обект: ${item.name}', 'Selected location: ${item.name}'));
                              } : null,
                              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text([
                                  item.address,
                                  if (item.availabilityLabel.isNotEmpty) item.availabilityLabel,
                                  if (item.phone.isNotEmpty) item.phone,
                                  if (item.hours.isNotEmpty) item.hours,
                                ].where((v) => v.isNotEmpty).join('\n')),
                              ),
                              trailing: item.isUpcoming ? const Icon(Icons.schedule_outlined, color: Colors.orangeAccent) : Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? cyan : (isDarkTheme ? Colors.white54 : Colors.black45)),
                            ),
                            if (item.canSelect)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
                                  onPressed: () async {
                                    setState(() => selectedLocation = item);
                                    await _saveLocationPreference(item);
                                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                                    _message(tr('Избран обект: ${item.name}', 'Selected location: ${item.name}'));
                                  },
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: Text(tr('Избери този обект', 'Select this location')),
                                )),
                              ),
                            if (item.mapsUrl.isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final uri = Uri.tryParse(item.mapsUrl);
                                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  },
                                  icon: const Icon(Icons.directions_outlined, size: 18),
                                  label: Text(tr('Маршрут', 'Directions')),
                                ),
                              ),
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationImageFallback() => Container(
    color: const Color(0xFF111B29),
    alignment: Alignment.center,
    child: const Icon(Icons.home_repair_service_rounded, size: 48, color: cyan),
  );

  void _showSettings() {
    if (_settingsOpen) return;
    _settingsOpen = true;
    final controller = TextEditingController(text: apiUrl);
    var draftStaffPreview = staffPreview;
    var draftClientPreview = clientPreview;
    var draftNoRegPreview = noRegPreview;
    var draftDarkTheme = isDarkTheme;
    var draftLanguageMode = languageMode;
    Timer? apiSaveTimer;
    bool savingApi = false;
    Future<void> saveTheme(bool value, void Function(void Function()) setSheetState) async {
      setSheetState(() => draftDarkTheme = value);
      if (mounted) setState(() => isDarkTheme = value);
      await _savePreference('pcwork_dark_theme', value);
    }
    Future<void> savePreview(bool value, void Function(void Function()) setSheetState) async {
      if (!isAdministrator) return;
      setSheetState(() { draftStaffPreview = value; if (value) draftClientPreview = false; });
      if (mounted) setState(() { staffPreview = value; if (value) clientPreview = false; });
      await _savePreference('pcwork_staff_preview', value);
      if (value) await _savePreference('pcwork_client_preview', false);
    }
    Future<void> saveApi(String value, BuildContext sheetContext) async {
      if (!isAdministrator || savingApi) return;
      final cleaned = value.trim().replaceFirst(RegExp(r'/+$'), '');
      final parsed = Uri.tryParse(cleaned);
      if (parsed == null || parsed.host.isEmpty || parsed.scheme != 'https') return;
      savingApi = true;
      try { await _saveApiUrl(cleaned); unawaited(_checkApi(silent: true)); if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(tr('API адресът е запазен.','API address saved.')))); }
      catch (e) { if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text('$e'))); }
      finally { savingApi = false; }
    }
    showModalBottomSheet<void>(
      context: _navigatorKey.currentContext!, isScrollControlled: true, useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(22, 18, 22, MediaQuery.of(sheetContext).viewInsets.bottom + 18),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.tune_rounded, color: cyan), const SizedBox(width: 9), Expanded(child: Text(tr('Настройки на приложението', 'Application settings'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close))]),
          const SizedBox(height: 12),
          if (isAdministrator) ...[
            TextField(controller: controller, keyboardType: TextInputType.url, autocorrect: false,
              onChanged: (value) { apiSaveTimer?.cancel(); apiSaveTimer = Timer(const Duration(milliseconds: 800), () => saveApi(value, sheetContext)); },
              onSubmitted: (value) { apiSaveTimer?.cancel(); saveApi(value, sheetContext); },
              decoration: const InputDecoration(labelText: 'WordPress API URL', hintText: 'https://pcwork-bg.com', prefixIcon: Icon(Icons.link), border: OutlineInputBorder())),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () { controller.text = defaultApi; apiSaveTimer?.cancel(); saveApi(defaultApi, sheetContext); }, icon: const Icon(Icons.restart_alt), label: Text(tr('Възстанови адреса по подразбиране', 'Restore default address')))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Преглед като служител', 'Preview as employee')), subtitle: Text(tr('Само визуализация. Не променя ролята или сървърните права.', 'Visual preview only. Does not change role or server permissions.')), value: draftStaffPreview, onChanged: (v) => savePreview(v, setSheetState)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Преглед като клиент', 'Preview as customer')), subtitle: Text(tr('Скрива служебните екрани само за визуална проверка.', 'Hides staff screens for visual review only.')), value: draftClientPreview, onChanged: (v) async { setSheetState(() { draftClientPreview = v; if (v) draftStaffPreview = false; }); if (mounted) setState(() { clientPreview = v; if (v) staffPreview = false; }); await _savePreference('pcwork_client_preview', v); if (v) await _savePreference('pcwork_staff_preview', false); }),
            SwitchListTile(contentPadding: EdgeInsets.zero, secondary: const Icon(Icons.visibility_off_outlined), title: const Text('No Reg'), subtitle: Text(tr('Преглед на приложението като нерегистриран потребител. Само визуален режим; не променя профила и сървърните права.', 'Preview the app as an unregistered user. Visual mode only; does not change the account or server permissions.')), value: draftNoRegPreview, onChanged: (v) async { setSheetState(() => draftNoRegPreview = v); if (mounted) setState(() { noRegPreview = v; if (v) { tab = 0; _visitedTabs.add(0); } }); await _savePreference('pcwork_no_reg_preview', v); }),
          ],
          SwitchListTile(contentPadding: EdgeInsets.zero, secondary: Icon(draftDarkTheme ? Icons.dark_mode_outlined : Icons.light_mode_outlined), title: Text(tr('Тъмна тема', 'Dark theme')), subtitle: Text(tr('Изключете за светла тема.', 'Turn off to use the light theme.')), value: draftDarkTheme, onChanged: (v) => saveTheme(v, setSheetState)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: draftLanguageMode,
            decoration: InputDecoration(labelText: tr('Език', 'Language'), prefixIcon: const Icon(Icons.translate_rounded)),
            items: [
              DropdownMenuItem(value: 'auto', child: Text(tr('Автоматично (системен език)', 'Automatic (system language)'))),
              DropdownMenuItem(value: 'bg', child: Text(tr('Български', 'Bulgarian'))),
              DropdownMenuItem(value: 'en', child: Text(tr('Английски', 'English'))),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setSheetState(() => draftLanguageMode = value);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('pcwork_language_mode', value);
              if (!mounted) return;
              setState(() {
                languageMode = value;
                english = value == 'auto'
                    ? WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase() == 'en'
                    : value == 'en';
              });
            },
          ),
          const SizedBox(height: 8),
          Text(tr('Промените се запазват автоматично.', 'Changes are saved automatically.'), style: TextStyle(color: isDarkTheme ? Colors.white60 : Colors.black54, fontSize: 12)),
        ])),
      )),
    ).whenComplete(() { apiSaveTimer?.cancel(); _settingsOpen = false; controller.dispose(); });
  }

  void _message(String value) { if (!mounted) return; _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(value))); }
}
