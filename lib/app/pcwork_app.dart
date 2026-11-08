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
import '../screens/repair_protocol_screen.dart';
import '../screens/repair_evidence_screen.dart';
import '../screens/repair_documents_screen.dart';
import '../screens/repair_worklog_screen.dart';
import '../screens/staff_dashboard_screen.dart';
import '../screens/contact_hub_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/shop_screen.dart';
import '../screens/notification_history_screen.dart';

class PCWorkApp extends StatefulWidget {
  const PCWorkApp({super.key});
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
  int tab = 0;
  bool _settingsOpen = false;
  final Set<int> _visitedTabs = <int>{0};
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
  bool _syncingOfflineQueue = false;
  int _pendingSyncCount = 0;
  bool _marketingOptIn = false;
  bool _marketingPreferenceLoaded = false;
  String? _pushStatusMessage;
  bool _pushRegistering = false;
  bool _pushDialogShowing = false;
  final Set<String> _marketingCampaignsHandled = <String>{};
  bool _refreshingOnTabExit = false;
  Map<String, dynamic>? _appUpdateInfo;
  static const int _currentBuildNumber = 77;
  static const MethodChannel _updaterChannel = MethodChannel('com.pcworkbg.pcwork_mobile/updater');
  bool _installingUpdate = false;
  List<Map<String, dynamic>> _notificationHistory = <Map<String, dynamic>>[];
  int? _pendingShopOrderId;
  bool _openShopOrdersOnEntry = false;
  int get _unreadNotificationCount => _notificationHistory.where((item) => item['read'] != true).length;

  AuthService get auth => AuthService(baseUrl: apiUrl);
  PushNotificationService get push => PushNotificationService(baseUrl: apiUrl);
  ApiService get api => ApiService(baseUrl: apiUrl, userId: signedInUser?.id ?? 0);
  String tr(String bg, String en) => english ? en : bg;
  bool get isAdministrator => signedInUser?.roles.contains('administrator') ?? false;
  bool get canUseAdminChat => signedInUser?.roles.any((r) => ['administrator', 'shop_manager', 'pcwork_staff'].contains(r)) ?? false;
  bool get isStaffAccount => signedInUser?.roles.any((r) => ['administrator', 'pcwork_staff', 'shop_manager', 'editor'].contains(r)) ?? false;
  bool get showStaffPreview => isAdministrator && staffPreview && !clientPreview;
  bool get showClientPreview => isAdministrator && clientPreview;
  bool get canSeeStaffUi => (isStaffAccount && !showClientPreview) || showStaffPreview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  }

  Future<void> _restoreSession() async {
    try { final t = await auth.token; if (t != null) { final u = await auth.me(); if (mounted) setState(() { signedInUser = u; });
      unawaited(_loadMarketingPreference(t));
      unawaited(_enablePush(knownToken: t));
      _startOfflineSync(t); } } catch (_) { if (mounted) setState(() => signedInUser = null); }
  }

  Future<void> _checkForAppUpdate() async {
    try {
      final info = await api.getAppUpdateInfo();
      if (!mounted) return;
      final availableBuild = int.tryParse((info?['version_code'] ?? '').toString()) ?? 0;
      setState(() => _appUpdateInfo = availableBuild > _currentBuildNumber ? info : null);
    } catch (_) {
      // Update checks are optional and must never block app startup.
    }
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
            onPressed: url != null && url.scheme == 'https' && !_installingUpdate ? _downloadAndInstallUpdate : null,
            icon: const Icon(Icons.download_rounded),
            label: Text(_installingUpdate ? tr('Изтегляне и проверка…', 'Downloading and verifying…') : tr('Актуализирай сега', 'Update now')),
          )),
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
      unawaited(_syncOfflineQueue());
      // Re-check FCM registration when the app returns from system settings.
      if (signedInUser != null) unawaited(_retryPushRegistration());
    }
  }

  void _startOfflineSync(String token) {
    _offlineSyncTimer?.cancel();
    unawaited(_refreshPendingSyncCount(token));
    unawaited(_syncOfflineQueue());
    _offlineSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) => unawaited(_syncOfflineQueue()));
  }

  Future<void> _refreshPendingSyncCount(String token) async {
    final count = await api.pendingOperationCount(token);
    if (mounted) setState(() => _pendingSyncCount = count);
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
    } finally { _syncingOfflineQueue = false; }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineSyncTimer?.cancel();
    repairSearch.dispose();
    super.dispose();
  }


  Future<void> _loadNotificationHistory() async {
    final records = await PushNotificationService.loadNotificationHistory();
    if (mounted) setState(() => _notificationHistory = records);
  }

  Future<void> _openNotifications() async {
    final readRecords = _notificationHistory.map((item) => <String, dynamic>{...item, 'read': true}).toList();
    await PushNotificationService.saveNotificationHistory(readRecords);
    if (!mounted) return;
    setState(() => _notificationHistory = readRecords);
    await _navigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) => NotificationHistoryScreen(
        records: _notificationHistory,
        english: english,
        isDarkTheme: isDarkTheme,
        onChanged: (records) async {
          await PushNotificationService.saveNotificationHistory(records);
          if (mounted) setState(() => _notificationHistory = records);
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
    await PushNotificationService.removeNotificationById(notificationId);
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
        if (event != 'marketing_campaign' && hasKnownDestination && tab == destinationTab) {
          unawaited(PushNotificationService.removeNotificationById(notificationId).then((_) => _loadNotificationHistory()));
          if (destinationTab == 1) setState(() => repairsFuture = _loadRepairsFuture());
          return;
        }
        unawaited(_loadNotificationHistory());
        if ((data['event'] ?? '').toString() == 'marketing_campaign') {
          unawaited(PushNotificationService.removeNotificationById(notificationId).then((_) => _loadNotificationHistory()));
          unawaited(_showMarketingDialog(
            title: title,
            body: body,
            imageUrl: (data['image'] ?? '').toString(),
            targetUrl: (data['url'] ?? '').toString(),
            campaignId: (data['campaign_id'] ?? '').toString(),
          ));
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
        api.getRepairs(bearer),
      ]);
      if (!mounted) return;
      setState(() {
        signedInUser = results[0] as AuthUser;
        _marketingOptIn = results[1] as bool;
        _marketingPreferenceLoaded = true;
        repairsFuture = Future<List<Repair>>.value(results[2] as List<Repair>);
      });
    } catch (_) {
      // Refresh is opportunistic; never block navigation or discard current data.
    } finally {
      _refreshingOnTabExit = false;
    }
  }

  void _selectTab(int index) {
    if (index < 0 || index > 5) return;
    // Dismiss every transient route (dialogs, sheets and pushed overlays) before
    // switching the main section. Unsaved draft state is intentionally discarded.
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    final previousTab = tab;
    _settingsOpen = false;
    if (previousTab != index) unawaited(_refreshAfterLeavingTab());
    setState(() {
      tab = index;
      _visitedTabs.add(index);
      if (index == 1 && repairsFuture == null && signedInUser != null) {
        repairsFuture = _loadRepairsFuture();
      }
    });
  }

  // Custom six-item bar: the icon/label group is centered in a fixed-height
  // cell, so its top and bottom free space is mathematically equal.
  Widget _buildBottomNavigation(List<String> labels) {
    const icons = [
      Icons.grid_view_rounded,
      Icons.handyman_outlined,
      Icons.storefront_outlined,
      Icons.forum_outlined,
      Icons.calendar_month_outlined,
      Icons.person_outline_rounded,
    ];
    const selectedIcons = [
      Icons.grid_view_rounded,
      Icons.handyman_rounded,
      Icons.storefront_rounded,
      Icons.forum_rounded,
      Icons.calendar_month_rounded,
      Icons.person_rounded,
    ];
    final selectedColor = isDarkTheme ? cyan : const Color(0xFF087F83);
    const mutedColor = Color(0xFF8796AA);
    return SafeArea(
      top: false,
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          color: isDarkTheme ? const Color(0xFF0E1724) : Colors.white,
        ),
        child: Row(
          children: List<Widget>.generate(6, (index) {
            final selected = tab == index;
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: labels[index],
                child: InkWell(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  onTap: () => _selectTab(index),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 5),
                      decoration: BoxDecoration(
                        color: selected ? cyan.withValues(alpha: .17) : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(selected ? selectedIcons[index] : icons[index],
                            size: 34, color: selected ? selectedColor : mutedColor),
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(labels[index], maxLines: 1,
                                style: TextStyle(fontSize: 11.5, height: 1.1,
                                  decoration: TextDecoration.none,
                                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                                  color: selected ? selectedColor : mutedColor)),
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
    );
  }

  Widget _tabContent(int index) {
    switch (index) {
      case 0: return _home();
      case 1: return _repairs();
      case 2:
        return ShopScreen(
          api: api,
          tokenProvider: () => auth.token,
          profileProvider: () async => (await auth.me()),
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
      case 3: return ContactHubScreen(api: api, tokenProvider: () => auth.token, sessionKey: signedInUser?.id ?? 0, english: english, isDarkTheme: isDarkTheme, isActive: tab == 3, isAdministrator: canUseAdminChat);
      case 4: return _booking();
      case 5: return _profile();
      default: return const SizedBox.shrink();
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
      theme: ThemeData(
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        fontFamily: 'NotoSans',
        brightness: isDarkTheme ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cyan,
          brightness: isDarkTheme ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: isDarkTheme ? cyan : const Color(0xFF087F83),
          secondary: const Color(0xFF7952C7),
          surface: isDarkTheme ? const Color(0xFF151F2E) : Colors.white,
        ),
        scaffoldBackgroundColor: isDarkTheme ? const Color(0xFF0A101A) : const Color(0xFFF3F6FA),
        cardColor: isDarkTheme ? const Color(0xFF151F2E) : Colors.white,
        appBarTheme: AppBarTheme(
          backgroundColor: isDarkTheme ? const Color(0xFF0A101A) : Colors.white, foregroundColor: isDarkTheme ? Colors.white : const Color(0xFF172033),
          surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: isDarkTheme ? const Color(0xFF151F2E) : Colors.white, elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xFF26364A))),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: isDarkTheme ? const Color(0xFF111B29) : const Color(0xFFF7F9FC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2A3A50))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2A3A50))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: cyan, width: 1.5)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: isDarkTheme ? const Color(0xFF0E1724) : Colors.white, indicatorColor: cyan.withValues(alpha: .16),
          elevation: 0, labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11, fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? (isDarkTheme ? cyan : const Color(0xFF087F83)) : const Color(0xFF8796AA),
          )),
        ),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
          backgroundColor: cyan, foregroundColor: const Color(0xFF061319),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        )),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 40, padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: const Color(0xFF111B29), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF21D4D8).withValues(alpha: .28))), child: Image.asset('assets/images/LogoPCwork.webp', width: 36, height: 36, fit: BoxFit.contain)),
            const SizedBox(width: 10), const Text('PCWork', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
            const SizedBox(width: 9), Container(width: 5, height: 5, decoration: const BoxDecoration(color: cyan, shape: BoxShape.circle)),
            const SizedBox(width: 8), Flexible(child: Text(labels[tab], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFF93A4B8), fontWeight: FontWeight.w500))),
          ]),
          actions: [
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
    );
  }

  Widget _home() => ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 28), children: [
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDarkTheme ? null : Colors.white,
        gradient: isDarkTheme ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF123B4A), Color(0xFF17283D), Color(0xFF24233E)]) : null,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: isDarkTheme ? const Color(0xFF2B7180).withValues(alpha: .55) : const Color(0xFF26364A).withValues(alpha: .45)),
        boxShadow: [BoxShadow(color: (isDarkTheme ? cyan : const Color(0xFF26364A)).withValues(alpha: .08), blurRadius: 24, spreadRadius: -9, offset: const Offset(0, 9))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 52, height: 52, padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(16)), child: Image.asset('assets/images/LogoPCwork.webp', fit: BoxFit.contain)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PCWORK SERVICE', style: TextStyle(color: isDarkTheme ? cyan.withValues(alpha: .95) : const Color(0xFF087F83), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
            Text(tr('Технологиите. В сигурни ръце.', 'Technology. In safe hands.'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: isDarkTheme ? Colors.white : const Color(0xFF172033))),
          ])),
          Icon(Icons.auto_awesome_rounded, color: isDarkTheme ? const Color(0xFFB49BFF) : const Color(0xFF7952C7), size: 23),
        ]),
        const SizedBox(height: 23),
        Text(tr('Сервиз от ново поколение.', 'Next-generation device care.'), style: TextStyle(fontSize: 25, height: 1.16, fontWeight: FontWeight.w800, letterSpacing: -.5, color: isDarkTheme ? Colors.white : const Color(0xFF172033))),
        const SizedBox(height: 9),
        Text(tr('Компютри • Лаптопи • PlayStation', 'Computers • Laptops • PlayStation'), style: TextStyle(color: isDarkTheme ? const Color(0xFFC3D1E0) : const Color(0xFF68778B), fontSize: 13)),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _selectTab(4), icon: const Icon(Icons.calendar_month_rounded), label: Text(tr('Запази час за сервиз', 'Book a service appointment')))),
      ]),
    ),
    if (_appUpdateInfo != null) ...[const SizedBox(height: 12), _appUpdateBanner()],
    const SizedBox(height: 22),
    if (signedInUser == null) _homeSignInCard() else _homeAccountDashboard(),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _quickCard(Icons.qr_code_2_rounded, tr('Моите ремонти', 'My repairs'), () => _selectTab(1))),
      const SizedBox(width: 12),
      Expanded(child: _quickCard(Icons.chat_bubble_outline_rounded, tr('Чат', 'Chat'), () => _selectTab(3))),
    ]),
    const SizedBox(height: 20),
    Text(tr('Свържи се с нас', 'Contact us'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _contactCard(const Icon(Icons.call_rounded, color: Color(0xFF21D4D8), size: 21), tr('Обади се', 'Call us'), null, const Color(0xFF21D4D8), () => _launchContact(Uri(scheme: 'tel', path: '0886638848')))),
      const SizedBox(width: 10),
      Expanded(child: _contactCard(const Icon(Icons.chat_rounded, color: Color(0xFF8B70E8), size: 21), 'Viber', tr('Пиши ни', 'Message us'), const Color(0xFF8B70E8), () => _launchContact(Uri.parse('viber://chat?number=%2B359886638848')))),
    ]),
    Row(children: [
      Expanded(child: _contactCard(const Icon(Icons.facebook, color: Color(0xFF3988F7), size: 21), 'Messenger', tr('Пиши ни', 'Message us'), const Color(0xFF3988F7), () => _launchContact(Uri.parse('https://m.me/PcWorkService')))),
      const SizedBox(width: 10),
      Expanded(child: _contactCard(const FaIcon(FontAwesomeIcons.tiktok, color: Color(0xFFE05A8D), size: 21), 'TikTok', null, const Color(0xFFE05A8D), () => _launchContact(Uri.parse('https://www.tiktok.com/@css.ps4.ps5')))),
    ]),
    if (signedInUser != null && canSeeStaffUi) ...[
      const SizedBox(height: 21),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(tr('Състояние на услугите', 'Service status'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: const Color(0xFF21D4D8).withValues(alpha: .10), borderRadius: BorderRadius.circular(30)), child: Text(tr('LIVE', 'LIVE'), style: const TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))),
      ]),
      const SizedBox(height: 7),
      Card(child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: (apiReady ? Colors.greenAccent : Colors.orangeAccent).withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(apiReady ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: apiReady ? Colors.greenAccent : Colors.orangeAccent)),
        const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr('PCWork сървър', 'PCWork server'), style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 3), Text(apiMessage ?? tr('Проверка на връзката…', 'Checking connection…'), style: const TextStyle(color: Color(0xFF93A4B8), fontSize: 12))])),
        IconButton(onPressed: _checkApi, icon: const Icon(Icons.refresh_rounded, color: cyan)),
      ]))),
    ],
    const SizedBox(height: 16),
    Text(tr('Бърз достъп', 'Quick access'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    _infoTile(Icons.verified_user_outlined, tr('Общи условия GDPR', 'GDPR terms'), () => _openWebsite('https://pcwork-bg.com/gdpr/')),
    _infoTile(Icons.location_on_outlined, tr('Сервизни обекти', 'Service locations'), _showLocations),
  ]);

  Future<void> _launchContact(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _message(tr('Не успяхме да отворим приложението или връзката.', 'Could not open the app or link.'));
    } catch (e) {
      if (mounted) _message('${tr('Грешка при отваряне:', 'Could not open:')} $e');
    }
  }

  Widget _contactCard(Widget icon, String title, String? subtitle, Color accent, VoidCallback onTap) =>
      Card(child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 14),
          child: Row(children: [
            Container(width: 39, height: 39, decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: icon),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF93A4B8))),
              ],
            ])),
          ]),
        ),
      ));

  Widget _quickCard(IconData icon, String label, VoidCallback onTap) => Card(child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: cyan.withValues(alpha: .11), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: cyan, size: 23)), const SizedBox(width: 10), Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))), const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF71849A))]))));
  Widget _infoTile(IconData icon, String label, [VoidCallback? onTap]) => Card(child: ListTile(onTap: onTap, leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: cyan.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: cyan, size: 20)), title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF71849A))));

  Widget _repairs() {
    if (signedInUser == null) { return ListView(padding: const EdgeInsets.all(20), children: [
      Text(tr('Проследяване на ремонт', 'Repair tracking'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12), Text(tr('Влезте в профила си, за да видите ремонтите, историята и актуалния им статус.', 'Sign in to see your repairs, history and current status.')),
      const SizedBox(height: 16), FilledButton.icon(onPressed: authBusy ? null : () => _openAuthScreen(register: false), icon: const Icon(Icons.login), label: Text(tr('Вход / Регистрация', 'Sign in / Register'))),
    ]); }
    final future = repairsFuture ??= _loadRepairsFuture();
    return RefreshIndicator(onRefresh: () async { final f = _loadRepairsFuture(); setState(() => repairsFuture = f); await f; }, child: FutureBuilder<List<Repair>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ListView(padding: const EdgeInsets.all(24), children: [Text(tr('Неуспешно зареждане на ремонтите:', 'Could not load repairs:')), const SizedBox(height: 8), Text('${snapshot.error}'), const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()), icon: const Icon(Icons.refresh), label: Text(tr('Опитай отново', 'Try again')))]);
        final rows = List<Repair>.from(snapshot.data ?? [])..sort((a, b) => _repairDate(b.createdAt).compareTo(_repairDate(a.createdAt)));
        final query = repairSearch.text.trim().toLowerCase();
        final filtered = rows.where((r) => (repairStatusFilter == 'all' || r.status == repairStatusFilter) && (query.isEmpty || [r.number,r.device,r.model,r.serial,r.location].any((v) => v.toLowerCase().contains(query)))).toList();
        final active = rows.where((r) => !['completed','cancelled'].contains(r.status)).length;
        final ready = rows.where((r) => r.status == 'ready').length;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(tr('Моите ремонти', 'My repairs'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (!canSeeStaffUi) ...[
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _showCustomerRepairRequest, icon: const Icon(Icons.add_circle_outline), label: Text(tr('Нова заявка за ремонт','New repair request')))),
            const SizedBox(height: 10),
          ],
          if (_pendingSyncCount > 0) Card(color: const Color(0xFF3A2B16), child: ListTile(leading: const Icon(Icons.cloud_upload_outlined, color: Colors.orangeAccent), title: Text(tr('Чакащи синхронизации: $_pendingSyncCount', 'Pending sync: $_pendingSyncCount')), subtitle: Text(tr('Ще бъдат изпратени автоматично при възстановяване на интернет.', 'They will sync automatically when internet is restored.')), trailing: IconButton(onPressed: _syncOfflineQueue, icon: const Icon(Icons.sync)))),
          if ((snapshot.data ?? []).any((r) => r.fromCache)) Card(color: const Color(0xFF17283D), child: ListTile(leading: const Icon(Icons.cloud_off, color: cyan), title: Text(tr('Офлайн копие', 'Offline copy')), subtitle: Text(tr('Показват се последно запазените ремонти. Данните може да не са актуални.', 'Showing the last saved repairs. Data may be out of date.')))),
          Row(children: [Expanded(child: _repairMetric(tr('Всички','Total'), rows.length)), Expanded(child: _repairMetric(tr('Активни','Active'), active)), Expanded(child: _repairMetric(tr('Готови','Ready'), ready))]),
          const SizedBox(height: 12),
          TextField(controller: repairSearch, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Търси номер, устройство или модел','Search number, device or model'), border: const OutlineInputBorder(), suffixIcon: repairSearch.text.isEmpty ? null : IconButton(onPressed: () { repairSearch.clear(); setState(() {}); }, icon: const Icon(Icons.close)))),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(initialValue: repairStatusFilter, decoration: InputDecoration(labelText: tr('Филтър по статус','Filter by status'), border: const OutlineInputBorder()), items: [DropdownMenuItem(value:'all', child:Text(tr('Всички статуси','All statuses'))), ...['requested','received','diagnostics','waiting_approval','in_repair','ready','completed','cancelled'].map((v)=>DropdownMenuItem(value:v,child:Text(_statusLabel(v))))], onChanged:(v)=>setState(()=>repairStatusFilter=v ?? 'all')),
          const SizedBox(height: 12),
          if (filtered.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(rows.isEmpty ? tr('Все още няма ремонти, свързани с профила ви.','There are no repairs linked to your account yet.') : tr('Няма ремонти, отговарящи на търсенето.','No repairs match your search.'), textAlign: TextAlign.center)),
          ...filtered.map((r) => Card(child: ListTile(leading: CircleAvatar(child: Icon(r.status == 'ready' ? Icons.check_circle_outline : Icons.build, color: cyan)), title: Text(r.number.isEmpty ? 'Ремонт #${r.id}' : r.number), subtitle: Text([r.device, r.model, _statusLabel(r.status), if (r.pendingSync) tr('Чака синхронизация', 'Pending sync')].where((v) => v.isNotEmpty).join(' · ')), trailing: const Icon(Icons.chevron_right), onTap: () => _showRepairDetails(r))))
        ]);
      },
    ));
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
              final created = await api.createCustomerRepairRequest(token, {
                'location_code': selected!.code,
                'device_type': deviceType,
                'device_model': model.text.trim(),
                'problem_description': problem.text.trim(),
              }, clientRequestId: clientRequestId).timeout(const Duration(seconds: 34));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => repairsFuture = _loadRepairsFuture());
                _message('${tr('Заявката е приета. Номер:', 'Request accepted. Number:')} ${created['repair_number'] ?? ''}');
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

  Widget _repairMetric(String title, int value) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6), child: Column(children: [Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cyan)), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))])));

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

  void _showRepairDetails(Repair repair) async {
    final token = await auth.token;
    if (token == null || !mounted) return;
    showModalBottomSheet(context: _navigatorKey.currentState!.overlay!.context, isScrollControlled: true, builder: (ctx) => FutureBuilder<Repair>(future: api.getRepair(token, repair.id), builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
      if (snap.hasError) return SizedBox(height: 220, child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('${snap.error}'))));
      final r = snap.data;
      if (r == null) return SizedBox(height: 220, child: Center(child: Text(tr('Няма данни за този ремонт.', 'No repair details were returned.'))));
      final currentUser = signedInUser;
      final roles = currentUser?.roles ?? const <String>[];
      final isStaff = (roles.any((role) => ['administrator','pcwork_staff','shop_manager','editor'].contains(role)) && !showClientPreview) || showStaffPreview;
      return SizedBox(height: MediaQuery.of(ctx).size.height * .78, child: ListView(padding: const EdgeInsets.all(22), children: [Text(r.number.isEmpty ? 'PCW-${r.id}' : r.number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Wrap(spacing: 8, children: [Chip(label: Text(_statusLabel(r.status))), if (r.fromCache) Chip(avatar: const Icon(Icons.cloud_off, size: 16), label: Text(tr('Офлайн копие', 'Offline copy'))), if (isStaff) Chip(avatar: const Icon(Icons.flag_outlined, size: 16), label: Text(_priorityLabel(r.priority)))]), _detailRow(tr('Устройство','Device'), '${r.device} ${r.model}'), _detailRow(tr('Сервизен обект','Service location'), r.location), _detailRow(tr('Проблем','Reported issue'), r.problem), if (r.dueAt.isNotEmpty) _detailRow(tr('Краен срок','Due date'), _formatDate(r.dueAt)), if (isStaff && r.technicianName.isNotEmpty) _detailRow(tr('Отговорен техник','Assigned technician'), r.technicianName), if (isStaff && !['completed','cancelled'].contains(r.status)) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => _changeRepairStatus(r, ctx), icon: const Icon(Icons.sync_alt_rounded), label: Text(tr('Промени статуса на ремонта','Update repair status'))))), OutlinedButton.icon(onPressed: () => _shareRepair(r), icon: const Icon(Icons.share_outlined), label: Text(tr('Сподели информация за ремонта','Share repair information'))), OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: r.number.isEmpty ? 'PCW-${r.id}' : r.number)); if (ctx.mounted) _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tr('Номерът е копиран.','Repair number copied.')))); }, icon: const Icon(Icons.copy), label: Text(tr('Копирай номер','Copy repair number'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairProtocolScreen(repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, device: '${r.device} ${r.model}'.trim(), location: r.location, problem: r.problem, status: _statusLabel(r.status), createdAt: r.createdAt, baseUrl: apiUrl, token: token, repairId: r.id, canEmail: isStaff))); }, icon: const Icon(Icons.qr_code_2), label: Text(tr('Сервизен протокол · QR · PDF','Service protocol · QR · PDF'))),
        OutlinedButton.icon(onPressed: () async { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairEvidenceScreen(baseUrl: apiUrl, token: token, repairId: r.id, repairNumber: r.number, isStaff: isStaff))); }, icon: const Icon(Icons.photo_camera_back_outlined), label: Text(tr('Снимки и подписи','Photos & signatures'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairDocumentsScreen(baseUrl: apiUrl, token: token, repairId: r.id, repairNumber: r.number))); }, icon: const Icon(Icons.folder_open_outlined), label: Text(tr('Преглед на документите','View repair documents'))), OutlinedButton.icon(onPressed: () { Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RepairWorklogScreen(api: api, token: token, repairId: r.id, repairNumber: r.number.isEmpty ? 'PCW-${r.id}' : r.number, isStaff: isStaff))); }, icon: const Icon(Icons.receipt_long_outlined), label: Text(tr('Сервизен дневник · дейности, части и плащания','Service log · work, parts & payments'))), const Divider(height: 28), Text(tr('Етап на ремонта','Repair progress'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), _repairProgress(r.status), const Divider(height: 24), Text(tr('История на ремонта','Repair history'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), if (r.history.isEmpty) Text(tr('Няма записана история.','No history recorded yet.')), ...r.history.map((h) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.circle, size: 10, color: cyan), title: Text(_statusLabel(h.status)), subtitle: Text([if (isStaff && h.note.isNotEmpty) h.note, h.createdAt].where((x)=>x.isNotEmpty).join(' · '))))]));
    }));
  }

  Widget _repairProgress(String status) {
    const steps = ['requested','received','diagnostics','waiting_approval','in_repair','ready','completed'];
    final index = steps.indexOf(status);
    if (status == 'cancelled') return Chip(avatar: const Icon(Icons.cancel_outlined), label: Text(_statusLabel(status)));
    return Column(children: steps.asMap().entries.map((entry) {
      final active = index >= entry.key;
      return Row(children: [Icon(active ? Icons.check_circle : Icons.radio_button_unchecked, color: active ? cyan : Colors.white30, size: 19), const SizedBox(width: 10), Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(_statusLabel(entry.value), style: TextStyle(color: active ? (isDarkTheme ? Colors.white : Colors.black87) : (isDarkTheme ? Colors.white54 : Colors.black54), fontWeight: entry.key == index ? FontWeight.bold : FontWeight.normal)))), if (entry.key == index) Chip(label: Text(tr('Текущ етап','Current')))]);
    }).toList());
  }

  Widget _detailRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 125, child: Text(label, style: TextStyle(color: isDarkTheme ? Colors.white60 : Colors.black54))), Expanded(child: Text(value.isEmpty ? '—' : value))]));

  Widget _booking() => ListView(padding: const EdgeInsets.all(20), children: [
    Text(tr('Записване на час за сервиз', 'Book a service appointment'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
    Text(tr('Първо изберете сервизен обект. Ще видите всички 9 обекта от мрежата на PCWork. Обектите с предстоящо откриване са обозначени и не могат да бъдат избирани за посещение.', 'First choose a service location. All 9 PCWork locations are listed. Upcoming locations are marked and cannot yet be selected for visits.')),
    if (selectedLocation != null) ...[
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.location_on, color: cyan),
        title: Text(selectedLocation!.name),
        subtitle: Text(selectedLocation!.address),
        trailing: IconButton(
          tooltip: tr('Промени', 'Change'),
          onPressed: _showLocations,
          icon: const Icon(Icons.edit_location_alt_outlined),
        ),
      )),
    ],
    const SizedBox(height: 16), FilledButton.icon(onPressed: _showLocations, icon: const Icon(Icons.location_on_outlined), label: Text(tr('Избери сервизен обект', 'Choose a location'))),
    const SizedBox(height: 10), FilledButton.icon(onPressed: selectedLocation == null ? null : _openBookly, icon: const Icon(Icons.open_in_browser), label: Text(tr('Продължи към резервация', 'Continue to booking'))),
    if (selectedLocation == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('Изборът на обект е задължителен, за да продължите.', 'Selecting a location is required to continue.'), style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
    const SizedBox(height: 12), Text(tr('Резервацията се довършва в защитената Bookly форма на сайта.', 'The reservation is completed in the secure Bookly form on the website.')),
  ]);

  Widget _profile() => ListView(padding: const EdgeInsets.all(20), children: [
    CircleAvatar(radius: 38, child: Icon(signedInUser == null ? Icons.person_outline : Icons.verified_user, size: 40, color: cyan)),
    const SizedBox(height: 14),
    Text(signedInUser?.name ?? tr('Вашият PCWork профил', 'Your PCWork account'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text(signedInUser?.email ?? tr('Влезте или създайте профил, за да виждате ремонтите си.', 'Sign in or create an account to access your repairs.')),
    if (signedInUser != null && signedInUser!.phone.isNotEmpty) ...[const SizedBox(height: 5), Text(signedInUser!.phone, style: TextStyle(color: isDarkTheme ? Colors.white60 : const Color(0xFF68778B)))],
    if (signedInUser != null) ...[
      const SizedBox(height: 12), OutlinedButton.icon(onPressed: _editCustomerProfile, icon: const Icon(Icons.edit_outlined), label: Text(tr('Редактирай профила','Edit profile'))),
      const SizedBox(height: 12), Card(child: ListTile(leading: const Icon(Icons.badge_outlined, color: cyan), title: Text(tr('Тип профил', 'Account type')), subtitle: Text(signedInUser!.roles.any((r) => ['pcwork_customer','customer','subscriber'].contains(r)) ? tr('Потребител', 'Customer') : signedInUser!.roles.join(', ')))),
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
    if (signedInUser != null && canSeeStaffUi) ...[
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _openStaffDashboard, icon: const Icon(Icons.dashboard_outlined), label: Text(tr('Отвори служебното табло', 'Open staff dashboard'))),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _showIntakeForm, icon: const Icon(Icons.add_box_outlined), label: Text(tr('Приеми ново устройство', 'Register device intake'))),
      const SizedBox(height: 8),
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
    final closed = await showDialog<bool>(context: navigatorContext, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(
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
    if (closed == true && mounted && dirty) {
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

  Future<void> _openStaffDashboard() async {
    final token = await auth.token;
    if (token == null || !mounted) { _message(tr('Влезте със служебен профил.','Sign in with a staff account.')); return; }
    _navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => StaffDashboardScreen(api: api, token: token, english: english)));
  }

  void _showIntakeForm() async {
    final token = await auth.token;
    if (token == null) { _message(tr('Влезте със служебен профил.', 'Sign in with a staff account.')); return; }
    List<ServiceLocation> options;
    try { options = (await api.getLocations()).where((location) => location.canSelect).toList(); }
    catch (e) { _message('${tr('Неуспешно зареждане на обектите:', 'Could not load locations:')} $e'); return; }
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
    ServiceLocation? selected = options.isNotEmpty ? options.first : null;
    bool saving = false;
    await showModalBottomSheet<void>(context: _navigatorKey.currentState!.overlay!.context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      Widget field(TextEditingController c, String label, {int lines = 1, TextInputType? type}) => Padding(padding: const EdgeInsets.only(bottom: 11), child: TextField(controller: c, maxLines: lines, keyboardType: type, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())));
      return Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 18), child: SizedBox(height: MediaQuery.of(ctx).size.height * .82, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(tr('Прием на устройство', 'Device intake'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
        Text(tr('Създава се ремонт с уникален номер и начален статус „Приет“.', 'Creates a repair with a unique number and initial “Received” status.'), style: TextStyle(color: isDarkTheme ? Colors.white60 : Colors.black54)),
        const SizedBox(height: 12),
        Expanded(child: ListView(children: [
          DropdownButtonFormField<ServiceLocation>(initialValue: selected, isExpanded: true, decoration: InputDecoration(labelText: tr('Сервизен обект', 'Service location'), border: const OutlineInputBorder()), items: options.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(), onChanged: (v) => setSheet(() => selected = v)),
          const SizedBox(height: 12), field(customerEmail, 'Имейл на клиент*', type: TextInputType.emailAddress),
          field(customerName, 'Име на клиент'), field(customerPhone, 'Телефон', type: TextInputType.phone),
          const Divider(height: 24), field(deviceType, 'Тип устройство*'), field(model, 'Марка и модел*'), field(serial, 'Сериен номер'),
          field(problem, 'Описание на проблема*', lines: 3), field(condition, 'Външно състояние', lines: 3),
          field(accessories, 'Комплектовка / аксесоари', lines: 2), field(notes, 'Вътрешни бележки', lines: 2),
        ])),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: saving ? null : () async {
          if (selected == null || selected!.code.isEmpty || customerEmail.text.trim().isEmpty || deviceType.text.trim().isEmpty || model.text.trim().isEmpty || problem.text.trim().isEmpty) { _message(tr('Изберете обект с код и попълнете задължителните полета със звезда.', 'Choose a coded location and complete all required fields.')); return; }
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined, color: cyan),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    tr('Здравей, ${signedInUser?.name ?? ''}', 'Welcome, ${signedInUser?.name ?? ''}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => _selectTab(1),
                  child: Text(tr('Ремонти', 'Repairs')),
                ),
              ],
            ),
            if (future == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _selectTab(1), icon: const Icon(Icons.build_outlined), label: Text(tr('Зареди моите ремонти', 'Load my repairs')))),
              )
            else FutureBuilder<List<Repair>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: LinearProgressIndicator(minHeight: 3),
                  );
                }
                if (snapshot.hasError) {
                  return Row(
                    children: [
                      const Expanded(child: Text('Неуспешно зареждане на ремонтите.', style: TextStyle(color: Colors.white60, fontSize: 12))),
                      IconButton(
                        tooltip: tr('Опитай отново', 'Retry'),
                        onPressed: () => setState(() => repairsFuture = _loadRepairsFuture()),
                        icon: const Icon(Icons.refresh, color: cyan),
                      ),
                    ],
                  );
                }
                final rows = snapshot.data ?? const <Repair>[];
                final active = rows.where((r) => !['completed', 'cancelled'].contains(r.status)).length;
                final ready = rows.where((r) => r.status == 'ready').length;
                return Row(
                  children: [
                    Expanded(child: _repairMetric(tr('Всички', 'Total'), rows.length)),
                    Expanded(child: _repairMetric(tr('Активни', 'Active'), active)),
                    Expanded(child: _repairMetric(tr('Готови', 'Ready'), ready)),
                  ],
                );
              },
            ),
            if (canSeeStaffUi)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openStaffDashboard,
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(tr('Служебно табло', 'Staff dashboard')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBookly() async {
    try {
      final uri = await api.getBookingUrl();
      if (uri == null) { _message(tr('Bookly не е конфигуриран. Проверете настройките в WordPress → PCWork настройки → Bookly.', 'Bookly is not configured. Check WordPress → PCWork Settings → Bookly.')); return; }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) _message(tr('Страницата за резервации не може да бъде отворена.', 'Could not open the booking page.'));
    } catch (e) { _message('$e'); }
  }

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
                              height: 128,
                              width: double.infinity,
                              child: item.imageUrl.isNotEmpty
                                  ? Image.network(item.imageUrl, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => _locationImageFallback())
                                  : _locationImageFallback(),
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
