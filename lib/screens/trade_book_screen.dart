import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/shoonya_provider.dart';
import '../utils/cred_theme.dart';
import '../widgets/cred_widgets.dart';

class TradeBookScreen extends ConsumerWidget {
  const TradeBookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tradeBookAsync = ref.watch(tradeBookProvider);

    return Container(
      color: CredColors.background,
      child: RefreshIndicator(
        color: CredColors.primary,
        onRefresh: () => ref.read(tradeBookProvider.notifier).refresh(),
        child: tradeBookAsync.when(
          data: (trades) {
            if (trades.isEmpty) {
              return _buildEmptyState();
            }
            final reversedTrades = trades.reversed.toList();
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: reversedTrades.length,
              itemBuilder: (context, index) {
                return _buildTradeCard(reversedTrades[index]);
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
                  onPressed: () => ref.read(tradeBookProvider.notifier).refresh(),
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
          Icon(Icons.history_toggle_off, size: 64, color: Colors.white.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          const Text('NO RECENT TRADES', style: TextStyle(fontSize: 12, color: CredColors.textMuted, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
        ],
      ),
    );
  }

  Widget _buildTradeCard(dynamic trade) {
    final String tsym = trade['tsym'] ?? 'N/A';
    final String trantype = trade['trantype'] ?? 'B';
    final String fillqty = trade['flqty'] ?? trade['fillshares'] ?? '0';
    final String fillprc = trade['flprc'] ?? trade['avgprc'] ?? '0.00';
    final String fltm = trade['fltm'] ?? 'N/A';
    final String prd = trade['prd'] ?? 'N/A';
    final String remarks = trade['remarks'] ?? '';
    
    final bool isBuy = trantype == 'B';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: CredCard(
        padding: const EdgeInsets.all(20),
        child: Column(
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
                        fltm,
                        style: const TextStyle(color: CredColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: CredColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'EXECUTED',
                    style: TextStyle(color: CredColors.success, fontSize: 10, fontWeight: FontWeight.w900),
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
                  _buildInfoColumn('PRICE', '₹$fillprc', CredColors.primary),
                  _buildInfoColumn('QTY', fillqty, Colors.white),
                  _buildInfoColumn('PRODUCT', prd, CredColors.textMuted),
                ],
              ),
            ),
            if (remarks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'NOTES: $remarks',
                style: const TextStyle(color: CredColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
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
