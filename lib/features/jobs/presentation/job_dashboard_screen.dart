import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../providers/job_provider.dart';

class JobDashboardScreen extends ConsumerWidget {
  const JobDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(customerJobStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Мои заказы',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              LucideIcons.refresh_cw,
              size: 20,
              color: Color(0xFF0F172A),
            ),
            tooltip: 'Обновить',
            onPressed: () => ref.invalidate(customerJobStatsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.jobCreate),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text(
          'Создать заказ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        onRefresh: () async {
          ref.invalidate(customerJobStatsProvider);
          await ref.read(customerJobStatsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          children: [
            statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0F172A)),
                ),
              ),
              error: (err, _) => _buildErrorCard(
                message: err.toString(),
                onRetry: () => ref.invalidate(customerJobStatsProvider),
              ),
              data: (stats) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action-required banner when completed jobs await payment
                  if (stats.paymentPending > 0) ...[
                    _buildPaymentAlertBanner(
                      context: context,
                      count: stats.paymentPending,
                    ),
                    const SizedBox(height: 20),
                  ],

                  const Text(
                    'Статистика заказов',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 14),

                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.08,
                    children: [
                      _buildStatCard(
                        context: context,
                        title: 'Поиск\nмастера',
                        count: stats.pending,
                        icon: LucideIcons.search,
                        color: const Color(0xFF3B82F6),
                        status: 'PENDING',
                      ),
                      _buildStatCard(
                        context: context,
                        title: 'Мастер\nназначен',
                        count: stats.accepted,
                        icon: LucideIcons.user_check,
                        color: Colors.purple,
                        status: 'ACCEPTED',
                      ),
                      _buildStatCard(
                        context: context,
                        title: 'Сейчас\nв работе',
                        count: stats.ongoing,
                        icon: LucideIcons.hammer,
                        color: Colors.orange,
                        status: 'ONGOING',
                      ),
                      _buildStatCard(
                        context: context,
                        title: 'Ожидает\nоплаты',
                        count: stats.paymentPending,
                        icon: LucideIcons.credit_card,
                        color: Colors.indigo,
                        status: 'PAYMENT_PENDING',
                        highlightIfNonZero: true,
                      ),
                      _buildStatCard(
                        context: context,
                        title: 'Оплаченные\nзаказы',
                        count: stats.paid,
                        icon: LucideIcons.wallet,
                        color: Colors.teal,
                        status: 'PAID',
                      ),
                      _buildStatCard(
                        context: context,
                        title: 'Успешно\nзавершено',
                        count: stats.completed,
                        icon: LucideIcons.circle_check,
                        color: Colors.green,
                        status: 'COMPLETED',
                      ),
                      _buildStatCard(
                        context: context,
                        title: 'Спорные\nзаказы',
                        count: stats.disputed,
                        icon: LucideIcons.triangle_alert,
                        color: Colors.deepOrange,
                        status: 'DISPUTED',
                        highlightIfNonZero: true,
                      ),
                      _buildStatCard(
                        context: context,
                        title: 'Отмененные\nзаказы',
                        count: stats.cancelled,
                        icon: LucideIcons.circle_x,
                        color: Colors.red,
                        status: 'CANCELLED',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentAlertBanner({
    required BuildContext context,
    required int count,
  }) {
    return InkWell(
      onTap: () => context.push('${AppRoutes.jobList}?status=PAYMENT_PENDING'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.indigo.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                LucideIcons.credit_card,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ожидают оплаты: $count',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Проверьте фотоотчет и оплатите выполненную работу',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevron_right, color: Colors.indigo.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required String status,
    bool highlightIfNonZero = false,
  }) {
    final bool shouldHighlight = highlightIfNonZero && count > 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => context.push('${AppRoutes.jobList}?status=$status'),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: shouldHighlight
                  ? color.withValues(alpha: 0.5)
                  : Colors.grey.shade200,
              width: shouldHighlight ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        count > 99 ? '99+' : count.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard({
    required String message,
    required VoidCallback onRetry,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.circle_alert, color: Colors.red, size: 36),
          const SizedBox(height: 12),
          Text(
            'Не удалось загрузить статистику\n$message',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refresh_cw, size: 16),
            label: const Text('Повторить'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
