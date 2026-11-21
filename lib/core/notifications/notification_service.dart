import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/providers/active_chat_provider.dart';
import '../network/api_client.dart';
import '../router/app_router.dart';
import '../router/route_names.dart';
import '../socket/socket_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Background FCM received: ${message.messageId}');
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(
    ref.watch(apiClientProvider),
    rootNavigatorKey,
    ref.watch(socketServiceProvider),
    ref,
  );
  ref.onDispose(service.dispose);
  return service;
});

class NotificationService {
  static const String _androidChannelId = 'klinciti_high_priority';
  static const Duration _dedupeWindow = Duration(seconds: 60);

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  final ApiClient _apiClient;
  final GlobalKey<NavigatorState> _navigatorKey;
  final SocketService _socketService;
  final Ref _ref;

  // Time-windowed deduplication map keyed by shared backend `notificationId`
  final Map<String, DateTime> _recentNotificationIds = {};

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;

  bool _isInitialized = false;
  bool _isLocalPluginReady = false;

  NotificationService(
    this._apiClient,
    this._navigatorKey,
    this._socketService,
    this._ref,
  );

  void dispose() {
    _socketService.stopListening('notification', _handleSocketMessage);
    _tokenRefreshSub?.cancel();
    _onMessageSub?.cancel();
    _onMessageOpenedSub?.cancel();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 1. Initialize local notifications plugin first so Socket notifications always work
    await _initLocalNotifications();

    // 2. Listen to Socket.io notifications regardless of FCM permission state
    _socketService.listen('notification', _handleSocketMessage);

    // 3. Request OS push permission
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Prevent iOS from showing a duplicate native banner alongside flutter_local_notifications
      if (!kIsWeb && Platform.isIOS) {
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
      }

      // Clean up legacy mistaken worker topic subscription if present on existing installs
      unawaited(
        _fcm.unsubscribeFromTopic('kilinciti_workers_topic').catchError((_) {}),
      );

      final token = await _fcm.getToken();
      if (token != null) {
        await _registerDeviceToken(token);
      }

      _tokenRefreshSub = _fcm.onTokenRefresh.listen(
        (newToken) => unawaited(_registerDeviceToken(newToken)),
      );

      _onMessageSub = FirebaseMessaging.onMessage.listen(
        _handleFcmForegroundMessage,
      );

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen(
        (msg) => _routeFromData(msg.data),
      );

      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _routeFromData(initialMessage.data),
        );
      }
    }
  }

  Future<void> _initLocalNotifications() async {
    if (_isLocalPluginReady) return;

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _androidChannelId,
      'Важные уведомления',
      description: 'Уведомления о заказах, оплатах и сообщениях',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    await _localPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await _localPlugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onSelectNotification,
    );

    _isLocalPluginReady = true;
  }

  // ==============================================================
  // AUTH BRIDGES
  // ==============================================================

  /// Call immediately after login/registration so the backend binds this device token
  /// exclusively to the new user and manages Firebase topic subscriptions server-side.
  Future<void> registerTokenAfterLogin() async {
    try {
      final fcmToken = await _fcm.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _registerDeviceToken(fcmToken, forceRegister: true);
      }
    } catch (e) {
      log('❌ Failed to register token after login: $e');
    }
  }

  /// Call BEFORE clearing the JWT on logout so the backend removes the token
  /// and unsubscribes all user/role topics via the Redis Stream consumer.
  Future<void> unregisterTokenOnLogout() async {
    try {
      final fcmToken = await _fcm.getToken();
      await _apiClient.dio.post(
        '/fcm/remove-fcm',
        data: {
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcmToken': fcmToken,
        },
      );
      _recentNotificationIds.clear();
      log('✅ FCM token unregistered on logout');
    } catch (e) {
      log('⚠️ Failed to unregister FCM token on logout: $e');
    }
  }

  /// Kept as safe no-op compatibility wrappers while backend Redis Stream consumer
  /// manages all role and personal phone topics via Firebase Admin SDK.
  Future<void> subscribeToUserTopics(String? mobile) async {
    try {
      await _fcm.unsubscribeFromTopic('kilinciti_workers_topic');
    } catch (_) {}
  }

  Future<void> unsubscribeFromTopics(String? mobile) async {
    try {
      await _fcm.unsubscribeFromTopic('kilinciti_workers_topic');
      final userTopic = _buildMobileTopic(mobile);
      if (userTopic.isNotEmpty) {
        await _fcm.unsubscribeFromTopic(userTopic);
      }
    } catch (_) {}
  }

  String _buildMobileTopic(String? mobile) {
    if (mobile == null || mobile.trim().isEmpty) return '';
    final String digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      return 'user_${digits.substring(1)}';
    }
    return digits.isNotEmpty ? 'user_$digits' : '';
  }

  // ==============================================================
  // INCOMING EVENT PROCESSING & DEDUPLICATION
  // ==============================================================

  void _processIncomingNotification({
    required String id,
    required String title,
    required String body,
    required Map<String, dynamic> payloadData,
  }) {
    if (!_isLocalPluginReady) return;

    final now = DateTime.now();
    _recentNotificationIds.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _dedupeWindow,
    );

    if (_recentNotificationIds.containsKey(id)) return;
    _recentNotificationIds[id] = now;

    final type = payloadData['type']?.toString().toUpperCase() ?? '';
    final sessionId =
        payloadData['sessionId']?.toString() ??
        payloadData['chatSessionId']?.toString() ??
        payloadData['chatId']?.toString();

    // 1. Suppress OS banner if the user is already viewing this exact chat session
    if (sessionId != null && sessionId.isNotEmpty) {
      final activeSessionId = _ref.read(activeChatSessionProvider);
      if (activeSessionId == sessionId) {
        return;
      }
    }

    // 2. Fallback GoRouter route inspection
    final context = _navigatorKey.currentContext;
    if (context != null) {
      try {
        final router = GoRouter.of(context);
        final currentRoute = router.routerDelegate.currentConfiguration.uri
            .toString();

        if (type.contains('CHAT') &&
            sessionId != null &&
            sessionId.isNotEmpty &&
            currentRoute.contains('${AppRoutes.chatDetail}/$sessionId')) {
          return;
        }
      } catch (e) {
        log('⚠️ Route check failed, proceeding to show notification: $e');
      }
    }

    String stringifiedPayload = '{}';
    try {
      stringifiedPayload = jsonEncode(payloadData);
    } catch (_) {}

    // Mask to positive 32-bit signed integer for Android NotificationManager
    final int notificationIntId = id.hashCode & 0x7FFFFFFF;

    _localPlugin.show(
      notificationIntId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          'Важные уведомления',
          channelDescription: 'Уведомления о заказах, оплатах и сообщениях',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: stringifiedPayload,
    );
  }

  Future<void> _registerDeviceToken(
    String fcmToken, {
    bool forceRegister = false,
  }) async {
    try {
      final token = await _apiClient.storage.read(key: 'jwt_token');
      if (!forceRegister && (token == null || token.isEmpty)) return;

      final String deviceType = (!kIsWeb && Platform.isIOS) ? 'IOS' : 'ANDROID';
      await _apiClient.dio.post(
        '/fcm/save-fcm',
        data: {'fcmToken': fcmToken, 'deviceType': deviceType},
      );
      log('✅ FCM Token registered ($deviceType)');
    } catch (e) {
      log('❌ FCM Token registration failed: $e');
    }
  }

  void _handleFcmForegroundMessage(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);

    final String? title =
        message.notification?.title ?? data['title']?.toString();
    final String? body = message.notification?.body ?? data['body']?.toString();

    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    // Prioritize backend's shared `notificationId` so it matches Socket.io
    final String sharedId =
        data['notificationId']?.toString() ??
        data['id']?.toString() ??
        message.messageId ??
        DateTime.now().millisecondsSinceEpoch.toString();

    _processIncomingNotification(
      id: sharedId,
      title: title ?? 'Уведомление',
      body: body ?? '',
      payloadData: data,
    );
  }

  void _handleSocketMessage(dynamic payload) {
    try {
      final Map<String, dynamic> data = payload is String
          ? Map<String, dynamic>.from(jsonDecode(payload) as Map)
          : Map<String, dynamic>.from(payload as Map);

      Map<String, dynamic> nestedData = {};
      if (data['data'] is Map) {
        nestedData = Map<String, dynamic>.from(data['data'] as Map);
      } else if (data['data'] is String &&
          (data['data'] as String).trim().isNotEmpty) {
        try {
          nestedData = Map<String, dynamic>.from(
            jsonDecode(data['data'] as String) as Map,
          );
        } catch (_) {}
      }

      final Map<String, dynamic> mergedPayload = {
        if (data['notificationId'] != null)
          'notificationId': data['notificationId'],
        if (data['type'] != null) 'type': data['type'],
        if (data['sessionId'] != null) 'sessionId': data['sessionId'],
        if (data['partnerId'] != null) 'partnerId': data['partnerId'],
        if (data['jobId'] != null) 'jobId': data['jobId'],
        if (data['url'] != null) 'url': data['url'],
        ...nestedData,
      };

      // Prioritize shared `notificationId` so it matches FCM
      final String uniqueId =
          mergedPayload['notificationId']?.toString() ??
          data['notificationId']?.toString() ??
          data['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();

      final String title =
          data['title']?.toString() ??
          mergedPayload['title']?.toString() ??
          'Уведомление';
      final String body =
          data['body']?.toString() ??
          data['message']?.toString() ??
          mergedPayload['body']?.toString() ??
          '';

      _processIncomingNotification(
        id: uniqueId,
        title: title,
        body: body,
        payloadData: mergedPayload,
      );
    } catch (e) {
      log('❌ Socket Payload Parse Error: $e');
    }
  }

  void _onSelectNotification(NotificationResponse response) {
    final rawPayload = response.payload;
    if (rawPayload != null && rawPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map) {
          _routeFromData(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        log('❌ Notification tap payload decode error: $e');
      }
    }
  }

  // ==============================================================
  // DEEP LINK & NOTIFICATION TAP ROUTER
  // ==============================================================
  void _routeFromData(Map<String, dynamic> data) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final type = data['type']?.toString().toUpperCase() ?? '';
    final sessionId =
        data['sessionId']?.toString() ??
        data['chatSessionId']?.toString() ??
        data['chatId']?.toString();
    final partnerId =
        data['partnerId']?.toString() ?? data['senderId']?.toString();
    final jobId = data['jobId']?.toString() ?? data['orderId']?.toString();
    final rawUrl = data['url']?.toString();

    // 1. Direct Chat Room Navigation
    if (sessionId != null && sessionId.isNotEmpty) {
      final uri = Uri(
        path: '${AppRoutes.chatDetail}/$sessionId',
        queryParameters: {
          if (partnerId != null && partnerId.isNotEmpty) 'partnerId': partnerId,
        },
      );
      context.push(uri.toString());
      return;
    }

    // 2. Direct Job Detail Navigation
    if (jobId != null && jobId.isNotEmpty) {
      context.push('${AppRoutes.jobDetail}/$jobId');
      return;
    }

    // 3. Payment / Card Notifications
    if (type == 'CARD_LINKED') {
      context.push(AppRoutes.paymentMethods);
      return;
    }
    if (type == 'PAYMENT' || type == 'REFUND') {
      context.push(AppRoutes.customerTransactions);
      return;
    }

    // 4. Parse backend `url` field (e.g. `/chat/:sessionId/:partnerId`)
    if (rawUrl != null && rawUrl.trim().isNotEmpty) {
      final cleanUrl = rawUrl.trim();
      if (cleanUrl.startsWith('/chat/')) {
        final parts = cleanUrl.split('/').where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          final parsedSessionId = parts[1];
          final parsedPartnerId = parts.length >= 3 ? parts[2] : '';
          final uri = Uri(
            path: '${AppRoutes.chatDetail}/$parsedSessionId',
            queryParameters: {
              if (parsedPartnerId.isNotEmpty) 'partnerId': parsedPartnerId,
            },
          );
          context.push(uri.toString());
          return;
        }
      }
      if (cleanUrl.startsWith('/chat-detail/')) {
        final parsedSessionId = cleanUrl.replaceFirst('/chat-detail/', '');
        context.push('${AppRoutes.chatDetail}/$parsedSessionId');
        return;
      }
    }

    // 5. Fallback by Notification Type
    if (type.contains('CHAT')) {
      context.go(AppRoutes.chatList);
    } else if (type.contains('JOB')) {
      context.go(AppRoutes.jobs);
    } else {
      context.push(AppRoutes.notifications);
    }
  }
}
