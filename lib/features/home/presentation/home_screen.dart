import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import '../../auth/presentation/auth_bottom_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../../shared/widgets/global_error_widget.dart';
import '../../../core/network/api_exceptions.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(publicCategoriesProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Ensures status bar text is white against our dark header
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC), // Modern off-white background
        extendBodyBehindAppBar: true, // Covers the top bar space
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // title: const Text(
          //   'Klinciti',
          //   style: TextStyle(
          //     color: Colors.white,
          //     fontWeight: FontWeight.w900,
          //     fontSize: 26,
          //     letterSpacing: -0.5,
          //   ),
          // ),
          actions: [
            if (ref.watch(isAuthenticatedProvider))
              Consumer(
                builder: (context, ref, child) {
                  final unreadCount = ref.watch(unreadCountProvider);
                  return IconButton(
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(LucideIcons.bell, color: Colors.white),
                        if (unreadCount > 0)
                          Positioned(
                            right: -2,
                            top: -4,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.elasticOut,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF0F172A),
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                unreadCount > 99
                                    ? '99+'
                                    : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: () => context.push('/notifications'),
                  );
                },
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(publicCategoriesProvider.future),
          color: const Color(0xFF0F172A),
          child: CustomScrollView(
            slivers: [
              // ==========================================
              // 1. HERO SECTION (Dark gradient, Title, Features)
              // ==========================================
              SliverToBoxAdapter(child: _buildHeroSection(context)),

              // ==========================================
              // 2. CATEGORIES SECTION HEADER
              // ==========================================
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Text(
                    'Категории отходов',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A).withOpacity(0.9),
                    ),
                  ),
                ),
              ),

              // ==========================================
              // 3. CATEGORIES LIST / SHIMMER / ERROR
              // ==========================================
              categoriesAsync.when(
                data: (categories) {
                  if (categories.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            children: [
                              Icon(
                                LucideIcons.package_open,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Категории не найдены',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final cat = categories[index];
                        return _CategoryListItem(
                          category: cat,
                          onTap: () {
                            final isAuth = ref.read(isAuthenticatedProvider);
                            if (!isAuth) {
                              showAuthBottomSheet(context);
                            } else {
                              context.push(
                                '/create-job?category=${Uri.encodeComponent(cat.id)}',
                              );
                            }
                          },
                        );
                      }, childCount: categories.length),
                    ),
                  );
                },

                // ==========================================
                // 💎 SHIMMER LOADING EFFECT
                // ==========================================
                loading: () => SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const _CategoryShimmerItem(),
                      childCount: 5, // Show 5 skeleton items while loading
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
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A), // Dark slate
            Color(0xFF1E293B), // Lighter slate
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topPadding + 64), // Space for status bar & app bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Вывоз мусора\nи утилизация',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Оформите заказ и получите выгодные предложения от исполнителей мгновенно.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // HORIZONTAL FEATURES LIST
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFeatureCard(
                  icon: LucideIcons.zap,
                  title: 'Быстро',
                  subtitle: 'Выезд от 30 минут',
                ),
                _buildFeatureCard(
                  icon: LucideIcons.wallet,
                  title: 'Выгодно',
                  subtitle: 'Низкие цены',
                ),
                _buildFeatureCard(
                  icon: LucideIcons.leaf,
                  title: 'Экологично',
                  subtitle: 'Законная свалка',
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// REAL CATEGORY ITEM
// ============================================================
class _CategoryListItem extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;

  const _CategoryListItem({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: const Color(0xFF0F172A).withOpacity(0.05),
          highlightColor: const Color(0xFF0F172A).withOpacity(0.02),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9), // Slate 100
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: category.image != null && category.image!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: category.icon!,
                            width: 32,
                            height: 32,
                          )
                        : const Icon(
                            LucideIcons.sparkles,
                            color: Color(0xFF475569),
                            size: 28,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Нажмите для заказа', // Subtitle hint
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.chevron_right,
                    color: Color(0xFF94A3B8),
                    size: 20,
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
// SHIMMER LOADING ITEM
// ============================================================
class _CategoryShimmerItem extends StatelessWidget {
  const _CategoryShimmerItem();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 24,
              height: 24,
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
