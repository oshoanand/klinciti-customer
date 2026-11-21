import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/route_names.dart';
import '../providers/job_provider.dart';

class JobListScreen extends ConsumerStatefulWidget {
  final String? initialStatus;

  const JobListScreen({super.key, this.initialStatus});

  @override
  ConsumerState<JobListScreen> createState() => _JobListScreenState();
}

class _JobListScreenState extends ConsumerState<JobListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<({String status, String label})> _tabs = [
    (status: 'PENDING', label: 'Поиск мастера'),
    (status: 'ACCEPTED', label: 'Назначен'),
    (status: 'ONGOING', label: 'В работе'),
    (status: 'PAYMENT_PENDING', label: 'К оплате'),
    (status: 'PAID', label: 'Оплачено'),
    (status: 'COMPLETED', label: 'Завершенные'),
    (status: 'DISPUTED', label: 'Спорные'),
    (status: 'CANCELLED', label: 'Отмененные'),
  ];

  @override
  void initState() {
    super.initState();
    int initialIndex = 0;
    if (widget.initialStatus != null) {
      final target = widget.initialStatus!.toUpperCase();
      final idx = _tabs.indexWhere((t) => t.status == target);
      if (idx != -1) initialIndex = idx;
    }

    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          'Список заказов',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF0F172A),
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: const Color(0xFF0F172A),
          indicatorWeight: 3,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) => _JobListTab(status: t.status)).toList(),
      ),
    );
  }
}

class _JobListTab extends ConsumerStatefulWidget {
  final String status;

  const _JobListTab({required this.status});

  @override
  ConsumerState<_JobListTab> createState() => _JobListTabState();
}

class _JobListTabState extends ConsumerState<_JobListTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      ref.read(customerJobsListProvider(widget.status).notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(customerJobsListProvider(widget.status));

    return RefreshIndicator(
      color: const Color(0xFF0F172A),
      onRefresh: () =>
          ref.read(customerJobsListProvider(widget.status).notifier).refresh(),
      child: jobsAsync.when(
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
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  'Ошибка загрузки: $err',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(customerJobsListProvider(widget.status).notifier)
                      .refresh(),
                  icon: const Icon(LucideIcons.refresh_cw, size: 16),
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
                const SizedBox(height: 110),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.clipboard_list,
                        size: 52,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'В этой категории пока нет заказов',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount:
                paginated.items.length + (paginated.isLoadingMore ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == paginated.items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                );
              }
              return _buildJobCard(context, paginated.items[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildJobCard(BuildContext context, CustomerJobModel job) {
    final createdStr = job.createdAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(job.createdAt!.toLocal())
        : '';

    final priceLabel = job.budget > 0
        ? '${job.budget.toStringAsFixed(0)} ₽'
        : 'Договорная';

    final title = (job.categoryName != null && job.categoryName!.isNotEmpty)
        ? job.categoryName!
        : 'Заказ #${job.id.substring(0, job.id.length >= 6 ? 6 : job.id.length)}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('${AppRoutes.jobDetail}/${job.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Category Title + Budget
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (job.subcategoryName != null &&
                            job.subcategoryName!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            job.subcategoryName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    priceLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Row 2: Description snippet
              Text(
                job.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF334155),
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 10),

              // Row 3: Address
              Row(
                children: [
                  Icon(
                    LucideIcons.map_pin,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      job.pickupAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),

              // Row 4: Assigned worker preview (if assigned)
              if (job.workerName != null && job.workerName!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage:
                            (job.workerImage != null &&
                                job.workerImage!.isNotEmpty)
                            ? NetworkImage(job.workerImage!)
                            : null,
                        child:
                            (job.workerImage == null ||
                                job.workerImage!.isEmpty)
                            ? const Icon(
                                LucideIcons.user,
                                size: 13,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Мастер: ${job.workerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Row 5: Created date + Status/Payment badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 13,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        createdStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  _buildStatusBadge(job),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(CustomerJobModel job) {
    String text;
    Color color;

    if (job.isPaymentPending) {
      text = 'Ожидает оплаты';
      color = Colors.indigo;
    } else if (job.isPaid) {
      text = 'Оплачено';
      color = Colors.teal;
    } else {
      switch (job.status) {
        case 'PENDING':
          text = 'Поиск мастера';
          color = const Color(0xFF3B82F6);
          break;
        case 'ACCEPTED':
          text = 'Мастер назначен';
          color = Colors.purple;
          break;
        case 'ONGOING':
          text = 'В работе';
          color = Colors.orange;
          break;
        case 'COMPLETED':
          text = 'Завершен';
          color = Colors.green;
          break;
        case 'DISPUTED':
          text = 'Спор';
          color = Colors.deepOrange;
          break;
        case 'CANCELLED':
          text = 'Отменен';
          color = Colors.red;
          break;
        default:
          text = job.status;
          color = Colors.blueGrey;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
