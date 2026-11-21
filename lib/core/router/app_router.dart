import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_names.dart';

// --- Auth ---
import '../../features/auth/providers/auth_provider.dart';

// --- Layout ---
import '../../shared/layouts/main_scaffold.dart';

// --- Core Screens ---
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/support/presentation/support_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_edit_screen.dart';

// ==========================================
// JOBS FEATURE
// ==========================================
import '../../features/jobs/presentation/job_dashboard_screen.dart';
import '../../features/jobs/presentation/job_list_screen.dart';
import '../../features/jobs/presentation/job_detail_screen.dart';
import '../../features/jobs/presentation/job_create_screen.dart';
import '../../features/jobs/presentation/job_edit_screen.dart';

// ==========================================
// CHAT FEATURE
// ==========================================
import '../../features/chat/presentation/screens/chat_inbox_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';

// ==========================================
// PAYMENT FEATURE
// ==========================================
import '../../features/payments/presentation/linked_cards_screen.dart';
import '../../features/payments/presentation/transactions_screen.dart';

// ==========================================
// 1. GLOBAL NAVIGATOR KEY
// ==========================================
// Required by PushNotificationService to navigate when the app is in the background
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// Route prefixes that require an authenticated customer session
const List<String> _protectedPrefixes = [
  AppRoutes.jobs,
  AppRoutes.createJob,
  AppRoutes.editJob,
  AppRoutes.chatList,
  AppRoutes.chatDetail,
  AppRoutes.notifications,
  AppRoutes.profileEdit,
];

bool _isProtectedRoute(String location) {
  return _protectedPrefixes.any(
    (prefix) => location == prefix || location.startsWith('$prefix/'),
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,

    // ==========================================
    // 2. GLOBAL REDIRECT LOGIC
    // ==========================================
    redirect: (context, state) async {
      final location = state.matchedLocation;

      // 1. Force Onboarding for first-time users
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

      if (!hasSeenOnboarding && location != AppRoutes.onboarding) {
        return AppRoutes.onboarding;
      }

      // Prevent returning to onboarding once completed
      if (hasSeenOnboarding && location == AppRoutes.onboarding) {
        return AppRoutes.home;
      }

      // 2. Guard protected routes against unauthenticated deep links / push taps
      final isAuthenticated = ref.read(isAuthenticatedProvider);
      if (!isAuthenticated && _isProtectedRoute(location)) {
        return AppRoutes.home;
      }

      return null;
    },

    // ==========================================
    // 3. FALLBACK ERROR SCREEN (404 / BAD DEEP LINK)
    // ==========================================
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Color(0xFF0F172A)),
          onPressed: () => context.go(AppRoutes.home),
        ),
        title: const Text(
          'Страница не найдена',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.compass,
                size: 52,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 16),
              const Text(
                'Не удалось открыть экран',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state.uri.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.home),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('На главную'),
              ),
            ],
          ),
        ),
      ),
    ),

    routes: [
      // ==========================================
      // FULL SCREEN ROUTES (No Bottom Nav)
      // ==========================================
      GoRoute(
        path: AppRoutes.onboarding,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            OnboardingScreen(onFinish: () => context.go(AppRoutes.home)),
      ),

      // --- Customer Job Management Flow ---
      GoRoute(
        path: AppRoutes.jobs,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const JobDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.jobList,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final status = state.uri.queryParameters['status'];
          return JobListScreen(initialStatus: status);
        },
      ),
      GoRoute(
        path: AppRoutes.jobDetailPattern,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return JobDetailScreen(jobId: jobId);
        },
      ),
      GoRoute(
        path: AppRoutes.jobEditPattern,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final jobId = state.pathParameters['jobId']!;
          return JobEditScreen(jobId: jobId);
        },
      ),

      // --- Profile, Support & Notifications ---
      GoRoute(
        path: AppRoutes.profileEdit,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: AppRoutes.support,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // --- Payment Methods & Transaction History ---
      GoRoute(
        path: AppRoutes.paymentMethods,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            const LinkedCardsScreen(isWorkerPayoutMode: false),
      ),
      GoRoute(
        path: AppRoutes.customerTransactions,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CustomerTransactionsScreen(),
      ),

      // --- Chat Detail Screen ---
      // Expects paths like: /chat/<sessionId>/<partnerId> or /chat/new_admin/admin
      GoRoute(
        path: AppRoutes.chatDetailPattern,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          final partnerId = state.pathParameters['partnerId']!;

          // Safely extract optional UI fallbacks passed via context.push(..., extra: {...})
          final extra = state.extra is Map
              ? Map<String, dynamic>.from(state.extra as Map)
              : null;
          final partnerName = extra?['partnerName']?.toString();
          final partnerAvatar = extra?['partnerAvatar']?.toString();

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
                path: AppRoutes.jobCreate,
                builder: (context, state) {
                  // Support both ?categoryId= (new) and ?category= (legacy)
                  final categoryId =
                      state.uri.queryParameters['categoryId'] ??
                      state.uri.queryParameters['category'];
                  return JobCreateScreen(initialCategory: categoryId);
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

          // TAB 3: Profile (Профиль - Dummy branch, intercepted by MainScaffold Drawer)
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
