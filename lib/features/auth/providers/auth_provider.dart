import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/socket/socket_service.dart';

// ==========================================
// 1. GLOBAL AUTH STATE
// ==========================================
final isAuthenticatedProvider = StateProvider<bool>((ref) => false);
final currentUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

// ==========================================
// 2. AUTH CONTROLLER PROVIDER
// ==========================================
final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref.watch(apiClientProvider), ref);
});

// ==========================================
// 3. AUTH CONTROLLER IMPLEMENTATION
// ==========================================
class AuthController {
  static const String _jwtKey = 'jwt_token';
  static const String _userIdKey = 'user_id';
  static const String _userDataKey = 'user_data';

  final ApiClient _api;
  final Ref _ref;

  AuthController(this._api, this._ref);

  Future<void> checkInitialAuth() async {
    try {
      final results = await Future.wait([
        _api.storage.read(key: _jwtKey),
        _api.storage.read(key: _userIdKey),
        _api.storage.read(key: _userDataKey),
      ]);

      final token = results[0];
      final userId = results[1];
      final userDataStr = results[2];

      if (token != null &&
          token.isNotEmpty &&
          userId != null &&
          userId.isNotEmpty &&
          userDataStr != null &&
          userDataStr.isNotEmpty) {
        final decoded = jsonDecode(userDataStr);
        if (decoded is! Map) {
          throw const FormatException('Corrupt user_data format');
        }

        final userData = Map<String, dynamic>.from(decoded);
        _ref.read(currentUserProvider.notifier).state = userData;
        _ref.read(isAuthenticatedProvider.notifier).state = true;

        // Run FCM & Socket initialization in the background so cold start isn't blocked
        unawaited(_initRealtimeServices(userId));
      } else {
        await clearSession();
      }
    } catch (e) {
      log('⚠️ Initial auth check failed, clearing corrupt session: $e');
      await clearSession();
    }
  }

  Future<void> login(String identifier, String password) async {
    try {
      final response = await _api.dio.post(
        '/auth/login',
        data: {'identifier': identifier.trim(), 'password': password},
      );

      if (response.data is! Map) {
        throw ApiException('Некорректный ответ сервера при входе');
      }

      await saveSession(Map<String, dynamic>.from(response.data as Map));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> saveSession(Map<String, dynamic> data) async {
    final payload = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;

    final String token = (payload['accessToken'] ?? payload['token'] ?? '')
        .toString()
        .trim();
    final Map<String, dynamic>? userObject = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : null;
    final String userId = (userObject?['id'] ?? payload['userId'] ?? '')
        .toString()
        .trim();

    if (token.isEmpty || userId.isEmpty) {
      throw ApiException('Сервер не вернул токен или ID пользователя');
    }

    // 1. Persist session to secure storage
    await Future.wait([
      _api.storage.write(key: _jwtKey, value: token),
      _api.storage.write(key: _userIdKey, value: userId),
      if (userObject != null)
        _api.storage.write(key: _userDataKey, value: jsonEncode(userObject)),
    ]);

    // 2. Update Riverpod auth state
    if (userObject != null) {
      _ref.read(currentUserProvider.notifier).state = userObject;
    }
    _ref.read(isAuthenticatedProvider.notifier).state = true;

    // 3. Register FCM token & open Socket.io connection independently
    unawaited(_initRealtimeServices(userId));
  }

  /// Keeps Riverpod state and secure storage in sync after profile/avatar edits.
  Future<void> updateCurrentUser(Map<String, dynamic> updatedFields) async {
    final current = _ref.read(currentUserProvider) ?? <String, dynamic>{};
    final merged = <String, dynamic>{...current, ...updatedFields};

    _ref.read(currentUserProvider.notifier).state = merged;
    await _api.storage.write(key: _userDataKey, value: jsonEncode(merged));
  }

  Future<void> logout(BuildContext context) async {
    try {
      // Unregister THIS device's FCM token while JWT is still present in storage
      final currentUser = _ref.read(currentUserProvider);
      final notifService = _ref.read(notificationServiceProvider);

      await notifService.unregisterTokenOnLogout();

      // Clean up any legacy client-side topic subscriptions on older installs
      final mobile = currentUser?['mobile']?.toString();
      if (mobile != null && mobile.isNotEmpty) {
        await notifService.unsubscribeFromTopics(mobile);
      }
    } catch (e) {
      log('⚠️ FCM logout cleanup error (ignored): $e');
    } finally {
      await clearSession();

      if (context.mounted) {
        context.go('/home');
      }
    }
  }

  /// Context-free local teardown (usable from 401 interceptors and corrupt-storage recovery).
  Future<void> clearSession() async {
    _ref.read(socketServiceProvider).disconnect();

    await Future.wait([
      _api.storage.delete(key: _jwtKey),
      _api.storage.delete(key: _userIdKey),
      _api.storage.delete(key: _userDataKey),
    ]);

    _ref.read(isAuthenticatedProvider.notifier).state = false;
    _ref.read(currentUserProvider.notifier).state = null;
  }

  /// Runs FCM token registration and Socket.io connection in parallel with
  /// isolated error handling so a failure in one never blocks the other.
  Future<void> _initRealtimeServices(String userId) async {
    await Future.wait([
      _ref
          .read(notificationServiceProvider)
          .registerTokenAfterLogin()
          .catchError((Object e) {
            log('⚠️ FCM token registration skipped: $e');
          }),
      _ref.read(socketServiceProvider).connect(userId).catchError((Object e) {
        log('⚠️ Socket connection skipped: $e');
      }),
    ]);
  }
}
