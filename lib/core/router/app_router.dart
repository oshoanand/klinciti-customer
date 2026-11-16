import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_names.dart';

// --- Layout ---
import '../../shared/layouts/main_scaffold.dart';

// --- Screens ---
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/support/presentation/support_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_edit_screen.dart';

// ==========================================
// JOBS FEATURE
// ==========================================
import '../../features/jobs/presentation/job_list_screen.dart';
import '../../features/jobs/presentation/job_create_screen.dart';
import '../../features/jobs/presentation/job_edit_screen.dart';

// ==========================================
// CHAT FEATURE
// ==========================================
import '../../features/chat/presentation/screens/chat_inbox_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';

// ==========================================
// 1. GLOBAL NAVIGATOR KEY
// ==========================================
// Required by PushNotificationService to navigate when the app is in the background
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,

    // ==========================================
    // 2. GLOBAL REDIRECT LOGIC
    // ==========================================
    redirect: (context, state) async {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

      // Force Onboarding for first-time users
      if (!hasSeenOnboarding && state.matchedLocation != AppRoutes.onboarding) {
        return AppRoutes.onboarding;
      }

      return null;
    },

    routes: [
      // ==========================================
      // FULL SCREEN ROUTES (No Bottom Nav)
      // ==========================================
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) =>
            OnboardingScreen(onFinish: () => context.go(AppRoutes.home)),
      ),
      GoRoute(
        path: AppRoutes.orders,
        builder: (context, state) => const JobListScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.editJob}/:id',
        builder: (context, state) {
          final jobId = state.pathParameters['id']!;
          return JobEditScreen(jobId: jobId);
        },
      ),
      GoRoute(
        path: AppRoutes.profileEdit,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.support,
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // ==========================================
      // ✅ CONNECTED CHAT DETAIL SCREEN
      // Expects paths like: /chat/session_uuid/partner_uuid OR /chat/new_admin/admin
      // ==========================================
      GoRoute(
        path: '${AppRoutes.chatDetail}/:sessionId/:partnerId',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          final partnerId = state.pathParameters['partnerId']!;

          // ✅ Extract UI fallbacks safely passed via context.push(..., extra: {...})
          final extra = state.extra as Map<String, dynamic>?;
          final partnerName = extra?['partnerName'] as String?;
          final partnerAvatar = extra?['partnerAvatar'] as String?;

          return ChatDetailScreen(
            sessionId: sessionId,
            partnerId: partnerId,
            partnerName: partnerName,
            partnerAvatar: partnerAvatar,
          );
        },
      ),

      // ==========================================
      // SHELL ROUTE (With Bottom Nav, Drawer & Animated Tabs)
      // ==========================================
      StatefulShellRoute(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        navigatorContainerBuilder: (context, navigationShell, children) {
          // Note: Ensure FadeIndexedStack is imported or exists in your project
          return FadeIndexedStack(
            index: navigationShell.currentIndex,
            children: children,
          );
        },
        branches: [
          // TAB 0: Home (Главная)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // TAB 1: Create Job (Создать)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.createJob,
                builder: (context, state) {
                  // Extracts the parent Category UUID passed from the HomeScreen
                  final category = state.uri.queryParameters['category'];
                  return JobCreateScreen(initialCategory: category);
                },
              ),
            ],
          ),
          // TAB 2: Chats (Чат)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chatList,
                builder: (context, state) => const ChatInboxScreen(),
              ),
            ],
          ),
          // TAB 3: Profile (Профиль - Dummy branch, intercepted by Scaffold)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profileDummy,
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
