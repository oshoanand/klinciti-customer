import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/route_names.dart';
import '../providers/payment_provider.dart';

class CustomerTransactionsScreen extends ConsumerStatefulWidget {
  const CustomerTransactionsScreen({super.key});

  @override
  ConsumerState<CustomerTransactionsScreen> createState() =>
      _CustomerTransactionsScreenState();
}

class _CustomerTransactionsScreenState
    extends ConsumerState<CustomerTransactionsScreen> {
  String _selectedDirection = 'ALL'; // 'ALL' | 'OUTGOING' | 'INCOMING'

  static const List<({String id, String label})> _filters = [
    (id: 'ALL', label: 'Все'),
    (id: 'OUTGOING', label: 'Оплаты'),
    (id: 'INCOMING', label: 'Возвраты'),
  ];

  Future<void> _openPdf(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(customerTransactionsProvider(_selectedDirection));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrow_left, color: Color(0xFF0F172A)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Транзакции',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              LucideIcons.refresh_cw,
              size: 18,
              color: Color(0xFF0F172A),
            ),
            tooltip: 'Обновить',
            onPressed: () => ref
                .read(customerTransactionsProvider(_selectedDirection).notifier)
                .refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar (All / Payments / Refunds)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(
              children: _filters.map((filter) {
                final isSelected = _selectedDirection == filter.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected && _selectedDirection != filter.id) {
                        setState(() => _selectedDirection = filter.id);
                      }
                    },
                    backgroundColor: const Color(0xFFF1F5F9),
                    selectedColor: const Color(0xFF0F172A),
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF475569),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF0F172A),
              onRefresh: () => ref
                  .read(
                    customerTransactionsProvider(_selectedDirection).notifier,
                  )
                  .refresh(),
              child: txAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0F172A)),
                ),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.circle_alert,
                          color: Colors.red,
                          size: 38,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ошибка загрузки: $err',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () => ref
                              .read(
                                customerTransactionsProvider(_selectedDirection)
                                    .notifier,
                              )
                              .refresh(),
                          icon: const Icon(LucideIcons.refresh_cw, size: 15),
                          label: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (paginated) {
                  if (paginated.items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  LucideIcons.arrow_left_right,
                                  size: 36,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Транзакций пока нет',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Здесь будет отображаться история ваших оплат, счетов и возвратов.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount:
                        paginated.items.length + (paginated.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Explicit Load More button at bottom
                      if (index == paginated.items.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton(
                              onPressed: paginated.isLoadingMore
                                  ? null
                                  : () => ref
                                        .read(
                                          customerTransactionsProvider(
                                            _selectedDirection,
                                          ).notifier,
                                        )
                                        .loadMore(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0F172A),
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: paginated.isLoadingMore
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF0F172A),
                                      ),
                                    )
                                  : Text(
                                      'Загрузить ещё (${paginated.items.length} из ${paginated.total})',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      }

                      final tx = paginated.items[index];
                      return _CustomerTransactionTile(
                        tx: tx,
                        onOpenJob: tx.jobId != null
                            ? () => context.push(
                                AppRoutes.jobDetailById(tx.jobId!),
                              )
                            : null,
                        onOpenPdf:
                            (tx.invoicePdfUrl != null &&
                                tx.invoicePdfUrl!.isNotEmpty)
                            ? () => _openPdf(tx.invoicePdfUrl!)
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTransactionTile extends StatelessWidget {
  final CustomerTransactionModel tx;
  final VoidCallback? onOpenJob;
  final VoidCallback? onOpenPdf;

  const _CustomerTransactionTile({
    required this.tx,
    this.onOpenJob,
    this.onOpenPdf,
  });

  @override
  Widget build(BuildContext context) {
    final isIncoming = tx.isIncoming;
    final accentColor = isIncoming
        ? const Color(0xFF16A34A)
        : const Color(0xFF0F172A);
    final sign = isIncoming ? '+' : '−';
    final dateStr = tx.createdAt != null
        ? DateFormat('dd.MM.yyyy, HH:mm').format(tx.createdAt!.toLocal())
        : '';

    final shortJobId = tx.jobId != null && tx.jobId!.length >= 8
        ? '#${tx.jobId!.substring(0, 8)}'
        : '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpenJob,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isIncoming ? Colors.green : Colors.indigo)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isIncoming
                          ? LucideIcons.arrow_down_left
                          : (tx.paymentMethod == 'B2B_INVOICE'
                                ? LucideIcons.file_text
                                : LucideIcons.credit_card),
                      size: 20,
                      color: isIncoming ? Colors.green : Colors.indigo,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (shortJobId.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Заказ $shortJobId',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$sign${tx.amount.toStringAsFixed(0)} ₽',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildStatusBadge(tx.status),
                    ],
                  ),
                ],
              ),
              if (onOpenPdf != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onOpenPdf,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(LucideIcons.download, size: 14),
                    label: const Text(
                      'Открыть счёт (PDF)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'CONFIRMED':
      case 'PAID':
      case 'SUCCEEDED':
        color = Colors.teal;
        label = 'Успешно';
        break;
      case 'PENDING':
      case 'PROCESSING':
        color = Colors.orange;
        label = 'В обработке';
        break;
      case 'FAILED':
      case 'CANCELED':
      case 'REJECTED':
        color = Colors.red;
        label = 'Отменено';
        break;
      default:
        color = Colors.blueGrey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
