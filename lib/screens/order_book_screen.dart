import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/shoonya_provider.dart';
import '../utils/cred_theme.dart';
import '../widgets/cred_widgets.dart';

class OrderBookScreen extends ConsumerWidget {
  const OrderBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderBookAsync = ref.watch(orderBookProvider);

    return Container(
      color: CredColors.background,
      child: RefreshIndicator(
        color: CredColors.primary,
        onRefresh: () => ref.read(orderBookProvider.notifier).refresh(),
        child: orderBookAsync.when(
          data: (orders) {
            if (orders.isEmpty) {
              return _buildEmptyState();
            }
            final reversedOrders = orders.reversed.toList();
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: reversedOrders.length,
              itemBuilder: (context, index) {
                return _buildOrderCard(reversedOrders[index]);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: CredColors.primary)),
          error: (err, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: CredColors.error, size: 48),
                const SizedBox(height: 16),
                Text('Sync Error: $err', style: const TextStyle(color: CredColors.textMuted)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.read(orderBookProvider.notifier).refresh(),
                  child: const Text('RETRY SYNC', style: TextStyle(color: CredColors.primary, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_edu_outlined, size: 64, color: Colors.white.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          const Text('NO RECENT ORDERS', style: TextStyle(fontSize: 12, color: CredColors.textMuted, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    final String tsym = order['tsym'] ?? 'N/A';
    final String status = order['status'] ?? 'N/A';
    final String trantype = order['trantype'] ?? 'B';
    final String prctyp = order['prctyp'] ?? 'LMT';
    final String prc = order['prc'] ?? '0.00';
    final String qty = order['qty'] ?? '0';
    final String prd = order['prd'] ?? 'N/A';
    final String fillshares = order['fillshares'] ?? '0';
    final String avgprc = order['avgprc'] ?? '0.00';
    final String remarks = order['remarks'] ?? '';
    final String rejreason = order['rejreason'] ?? '';
    
    final bool isBuy = trantype == 'B';
    final bool isRejected = status.toLowerCase().contains('rejected');
    final bool isCancelled = status.toLowerCase().contains('cancelled');
    final bool isCompleted = status.toLowerCase() == 'complete';

    Color statusColor = CredColors.secondary;
    if (isCompleted) statusColor = CredColors.success;
    if (isRejected || isCancelled) statusColor = CredColors.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: CredCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tsym,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white, letterSpacing: -0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order['norentm'] ?? '',
                        style: const TextStyle(color: CredColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CredColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: CredShadows.neumorphicPressed,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoColumn('SIDE', isBuy ? 'BUY' : 'SELL', isBuy ? CredColors.success : CredColors.error),
                  _buildInfoColumn('QTY', '$fillshares/$qty', Colors.white),
                  _buildInfoColumn('PRICE', prc, CredColors.primary),
                  _buildInfoColumn('TYPE', prctyp, CredColors.textMuted),
                ],
              ),
            ),
            if (remarks.isNotEmpty || rejreason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                rejreason.isNotEmpty ? 'REJECTION: $rejreason' : 'REMARKS: $remarks',
                style: TextStyle(
                  color: rejreason.isNotEmpty ? CredColors.error.withValues(alpha: 0.7) : CredColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: CredColors.textMuted, fontSize: 8, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: valueColor),
        ),
      ],
    );
  }
}
