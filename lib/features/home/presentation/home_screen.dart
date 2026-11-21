import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../auth/presentation/auth_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../../jobs/providers/job_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../providers/category_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heroController;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _heroFade = CurvedAnimation(parent: _heroController, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _heroController, curve: Curves.easeOutCubic),
        );
    _heroController.forward();
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  void _navigateToCreateJob({String? categoryId}) {
    final isAuth = ref.read(isAuthenticatedProvider);
    if (!isAuth) {
      showAuthBottomSheet(context);
      return;
    }
    context.push(AppRoutes.jobCreateWithCategory(categoryId));
  }

  Future<void> _handleRefresh() async {
    final isAuth = ref.read(isAuthenticatedProvider);
    await Future.wait([
      ref.refresh(publicCategoriesProvider.future),
      if (isAuth)
        ref
            .refresh(customerJobStatsProvider.future)
            .catchError((_) => const CustomerJobStats()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isAuth = ref.watch(isAuthenticatedProvider);
    final categoriesAsync = ref.watch(publicCategoriesProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.recycle, color: Color(0xFF38BDF8), size: 22),
              SizedBox(width: 8),
              Text(
                'Klinciti',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          actions: [
            if (isAuth) ...[
              // Quick shortcut to Orders Dashboard
              IconButton(
                tooltip: 'Мои заказы',
                icon: const Icon(
                  LucideIcons.clipboard_list,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () => context.push(AppRoutes.jobs),
              ),
              // Notification Bell with animated unread badge
              Consumer(
                builder: (context, ref, _) {
                  final unreadCount = ref.watch(unreadCountProvider);
                  return IconButton(
                    tooltip: 'Уведомления',
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          LucideIcons.bell,
                          color: Colors.white,
                          size: 22,
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Container(
                                key: ValueKey<int>(unreadCount),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF0F172A),
                                    width: 1.5,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  unreadCount > 99
                                      ? '99+'
                                      : unreadCount.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: () => context.push(AppRoutes.notifications),
                  );
                },
              ),
            ],
            const SizedBox(width: 6),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: const Color(0xFF0F172A),
          backgroundColor: Colors.white,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ==========================================
              // 1. COMPACT MODERN HERO + INSTANT CTA
              // ==========================================
              SliverToBoxAdapter(child: _buildHeroSection(context)),

              // ==========================================
              // 2. ACTIVE ORDERS QUICK STRIP (AUTH ONLY)
              // ==========================================
              if (isAuth)
                const SliverToBoxAdapter(child: _ActiveOrdersBanner()),

              // ==========================================
              // 3. CATEGORIES HEADER
              // ==========================================
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Выберите услугу',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Быстрый заказ',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ==========================================
              // 4. CATEGORIES LIST / SHIMMER / ERROR
              // ==========================================
              categoriesAsync.when(
                data: (categories) {
                  if (categories.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 48,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              LucideIcons.package_open,
                              size: 46,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Категории временно недоступны',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final cat = categories[index];
                        return _StaggeredEntrance(
                          index: index,
                          child: _CategoryCard(
                            category: cat,
                            onTap: () =>
                                _navigateToCreateJob(categoryId: cat.id),
                          ),
                        );
                      }, childCount: categories.length),
                    ),
                  );
                },
                loading: () => SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, __) => const _CategoryShimmerItem(),
                      childCount: 5,
                    ),
                  ),
                ),
                error: (error, _) {
                  final apiError = ApiException.fromDioException(error);
                  return SliverToBoxAdapter(
                    child: GlobalErrorWidget(
                      message: apiError.message,
                      onRetry: () =>
                          ref.refresh(publicCategoriesProvider.future),
                    ),
                  );
                },
              ),

              // Bottom clearance for floating navigation bar
              const SliverToBoxAdapter(child: SizedBox(height: 112)),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HERO SECTION BUILDER
  // ============================================================
  Widget _buildHeroSection(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: FadeTransition(
        opacity: _heroFade,
        child: SlideTransition(
          position: _heroSlide,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, topPadding + 64, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Вывоз мусора\nбез лишних хлопот',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    color: Colors.white,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Добавьте фото задачи — проверенный мастер приедет в удобное время.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),

                // Primary instant-post CTA button with tactile scale
                _ScaleTap(
                  onTap: () => _navigateToCreateJob(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            LucideIcons.plus,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Создать заявку',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'Займет меньше минуты',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          LucideIcons.arrow_right,
                          color: Color(0xFF0F172A),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Crisp inline trust badges
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _TrustPill(
                        icon: LucideIcons.zap,
                        label: 'Выезд от 30 мин',
                      ),
                      SizedBox(width: 8),
                      _TrustPill(
                        icon: LucideIcons.shield_check,
                        label: 'Безопасная сделка',
                      ),
                      SizedBox(width: 8),
                      _TrustPill(
                        icon: LucideIcons.leaf,
                        label: 'Легальный вывоз',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// COMPACT TRUST PILL
// ============================================================
class _TrustPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF38BDF8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ACTIVE ORDERS QUICK STRIP (SHOWN ONLY WHEN RELEVANT)
// ============================================================
class _ActiveOrdersBanner extends ConsumerWidget {
  const _ActiveOrdersBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(customerJobStatsProvider);

    return statsAsync.maybeWhen(
      data: (stats) {
        final activeCount = stats.pending + stats.accepted + stats.ongoing;
        final paymentPending = stats.paymentPending;

        if (activeCount == 0 && paymentPending == 0) {
          return const SizedBox.shrink();
        }

        final bool hasPaymentDue = paymentPending > 0;
        final Color accent = hasPaymentDue
            ? Colors.indigo
            : const Color(0xFF0F172A);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: _ScaleTap(
            onTap: () => context.push(
              hasPaymentDue
                  ? AppRoutes.jobListByStatus('PAYMENT_PENDING')
                  : AppRoutes.jobs,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: hasPaymentDue ? Colors.indigo.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasPaymentDue
                      ? Colors.indigo.shade200
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.025),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      hasPaymentDue
                          ? LucideIcons.credit_card
                          : LucideIcons.clipboard_check,
                      color: accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasPaymentDue
                              ? 'Ожидают оплаты: $paymentPending'
                              : 'Активные заказы: $activeCount',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          hasPaymentDue
                              ? 'Нажмите, чтобы проверить и оплатить'
                              : 'Открыть панель управления заказами',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasPaymentDue
                                ? Colors.indigo.shade700
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevron_right, color: accent, size: 18),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ============================================================
// MODERN CATEGORY CARD (PARENT CATEGORY ONLY)
// ============================================================
class _CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const _CategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Safely resolve either image or icon URL without risking a null crash
    final String? resolvedImageUrl =
        (category.image != null && category.image!.trim().isNotEmpty)
        ? category.image!.trim()
        : (category.icon != null && category.icon!.trim().isNotEmpty
              ? category.icon!.trim()
              : null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _ScaleTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: resolvedImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: resolvedImageUrl,
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          errorWidget: (_, __, ___) => const Icon(
                            LucideIcons.sparkles,
                            color: Color(0xFF475569),
                            size: 24,
                          ),
                        )
                      : const Icon(
                          LucideIcons.sparkles,
                          color: Color(0xFF475569),
                          size: 24,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Нажмите, чтобы оформить заказ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.chevron_right,
                  color: Color(0xFF64748B),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// SUBTLE STAGGERED ENTRANCE & TACTILE SCALE HELPERS
// ============================================================
class _StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredEntrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final cappedIndex = index.clamp(0, 6);
    final duration = Duration(milliseconds: 260 + (cappedIndex * 55));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _ScaleTap({required this.child, required this.onTap});

  @override
  State<_ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<_ScaleTap> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ============================================================
// SHIMMER LOADING ITEM
// ============================================================
class _CategoryShimmerItem extends StatelessWidget {
  const _CategoryShimmerItem();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 15,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 140,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
