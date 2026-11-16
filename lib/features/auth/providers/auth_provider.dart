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
  final ApiClient _api;
  final Ref _ref;

  AuthController(this._api, this._ref);

  Future<void> checkInitialAuth() async {
    try {
      final token = await _api.storage.read(key: 'jwt_token');
      final userId = await _api.storage.read(key: 'user_id');
      final userDataStr = await _api.storage.read(key: 'user_data');

      // ✅ FIX: Ensure ALL required data exists before marking as authenticated
      if (token != null &&
          token.isNotEmpty &&
          userId != null &&
          userDataStr != null) {
        final userData = jsonDecode(userDataStr) as Map<String, dynamic>;
        _ref.read(currentUserProvider.notifier).state = userData;
        _ref.read(isAuthenticatedProvider.notifier).state = true;

        // ISOLATED TRY-CATCH: Setup FCM & Socket without breaking auth
        try {
          final mobile = userData['mobile']?.toString();
          final notifService = _ref.read(notificationServiceProvider);

          // 1. Register Token & Topics
          await notifService.registerTokenAfterLogin();
          await notifService.subscribeToUserTopics(mobile);

          // 2. Connect Real-time Socket
          await _ref.read(socketServiceProvider).connect(userId);
        } catch (e) {
          log('FCM/Socket Setup Error (Ignored): $e');
        }
      } else {
        // If data is corrupt or missing, ensure a clean logged-out state
        _ref.read(isAuthenticatedProvider.notifier).state = false;
        _ref.read(currentUserProvider.notifier).state = null;
      }
    } catch (e) {
      // Only reach here if storage read fails entirely
      _ref.read(isAuthenticatedProvider.notifier).state = false;
      _ref.read(currentUserProvider.notifier).state = null;
    }
  }

  Future<void> login(String identifier, String password) async {
    try {
      final response = await _api.dio.post(
        '/auth/login',
        data: {'identifier': identifier, 'password': password},
      );
      await saveSession(response.data);
    } catch (e) {
      throw ApiException.fromDioException(e as dynamic);
    }
  }

  Future<void> saveSession(Map<String, dynamic> data) async {
    final token = data['accessToken'] ?? data['token'];
    final userObject = data['user'];
    final userId = userObject?['id'] ?? data['userId'];

    if (token != null) {
      // 1. Save auth data to storage
      await _api.storage.write(key: 'jwt_token', value: token);

      if (userId != null) {
        await _api.storage.write(key: 'user_id', value: userId.toString());
      }

      if (userObject != null) {
        await _api.storage.write(
          key: 'user_data',
          value: jsonEncode(userObject),
        );

        // Safely cast the map
        _ref.read(currentUserProvider.notifier).state =
            Map<String, dynamic>.from(userObject);

        // =======================================================
        // 2. FCM & SOCKET BEST PRACTICE: REGISTER DEVICE
        // =======================================================
        try {
          final mobile = userObject['mobile']?.toString();
          final notifService = _ref.read(notificationServiceProvider);

          // Must happen AFTER token is set in storage/Dio headers
          await notifService.registerTokenAfterLogin();
          await notifService.subscribeToUserTopics(mobile);

          // Connect Socket immediately on login
          await _ref.read(socketServiceProvider).connect(userId.toString());
        } catch (e) {
          log('Setup Error on Login (Ignored): $e');
        }
      }

      // 3. Update Auth State
      _ref.read(isAuthenticatedProvider.notifier).state = true;
    }
  }

  Future<void> logout(BuildContext context) async {
    try {
      final currentUser = _ref.read(currentUserProvider);

      if (currentUser != null) {
        try {
          // Tell backend to drop the FCM token from the database
          await _api.dio.post('/fcm/remove-fcm', data: {});

          final mobile = currentUser['mobile']?.toString();
          await _ref
              .read(notificationServiceProvider)
              .unsubscribeFromTopics(mobile);
        } catch (e) {
          log('FCM Unsubscribe Error (Ignored): $e');
        }
      }
    } catch (_) {
    } finally {
      // ✅ Disconnect socket BEFORE wiping storage to ensure clean teardown
      _ref.read(socketServiceProvider).disconnect();

      // 1. Clear local storage (this automatically removes the token for all future API calls)
      await _api.storage.delete(key: 'jwt_token');
      await _api.storage.delete(key: 'user_id');
      await _api.storage.delete(key: 'user_data');

      // 2. Reset Riverpod auth state
      _ref.read(isAuthenticatedProvider.notifier).state = false;
      _ref.read(currentUserProvider.notifier).state = null;

      // Navigate home
      if (context.mounted) {
        context.go('/home');
      }
    }
  }
}
