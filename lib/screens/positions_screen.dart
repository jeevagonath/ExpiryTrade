import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/shoonya_provider.dart';
import '../utils/cred_theme.dart';
import '../widgets/cred_widgets.dart';

class PositionsScreen extends ConsumerWidget {
  const PositionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionsAsync = ref.watch(positionsProvider);

    return Container(
      color: CredColors.background,
      child: RefreshIndicator(
        color: CredColors.primary,
        onRefresh: () => ref.read(positionsProvider.notifier).refresh(),
        child: positionsAsync.when(
          data: (positions) {
            final metrics = _calculateTotalMetrics(positions);
            final bool isEmpty = positions.isEmpty;
            final bool hasOpenPositions = positions.any((p) {
              final qty = double.tryParse(p['netqty']?.toString() ?? '0') ?? 0;
              return qty != 0;
            });

            return Column(
              children: [
                _buildTotalPnLHeader(context, ref, metrics['totalPnL'] ?? 0.0, hasOpenPositions),
                Expanded(
                  child: isEmpty 
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: positions.length,
                        itemBuilder: (context, index) {
                          return _buildPositionCard(context, ref, positions[index]);
                        },
                      ),
                ),
              ],
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
                  onPressed: () => ref.read(positionsProvider.notifier).refresh(),
                  child: const Text('RETRY SYNC', style: TextStyle(color: CredColors.primary, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, double> _calculateTotalMetrics(List<dynamic> positions) {
    double totalPnL = 0.0;
    for (var pos in positions) {
      totalPnL += calculatePositionPnL(pos);
    }
    return {'totalPnL': totalPnL};
  }

  Widget _buildTotalPnLHeader(BuildContext context, WidgetRef ref, double totalPnL, bool hasOpenPositions) {
    final bool isProfit = totalPnL >= 0;
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: CredCard(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL NET P&L',
                  style: TextStyle(color: CredColors.textMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                const SizedBox(height: 8),
                Text(
                  '${isProfit ? '+' : ''}₹${totalPnL.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isProfit ? CredColors.success : CredColors.error,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (hasOpenPositions)
              SizedBox(
                width: 100,
                child: CredButton(
                  onPressed: () => _showCloseAllConfirmation(context, ref),
                  gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
                  child: const Text('CLOSE ALL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCloseAllConfirmation(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildConfirmationDialog(
        context,
        'ABANDON ALL',
        'This will square off all active positions at market price immediately.',
        'SQUARE OFF ALL',
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(orderExecutionProvider).squareOffAllPositions();
        if (context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All positions abandoned successfully'),
              backgroundColor: CredColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        ref.read(positionsProvider.notifier).refresh();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Protocol Failure: $e'), backgroundColor: CredColors.error, behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }

  Widget _buildConfirmationDialog(BuildContext context, String title, String content, String confirmLabel) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: CredCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 12),
            Text(content, style: const TextStyle(color: CredColors.textMuted, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('CANCEL', style: TextStyle(color: CredColors.textMuted, fontSize: 12)),
                  ),
                ),
                Expanded(
                  child: CredButton(
                    onPressed: () => Navigator.pop(context, true),
                    gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)]),
                    child: Text(confirmLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionCard(BuildContext context, WidgetRef ref, dynamic pos) {
    final String tsym = pos['tsym'] ?? 'N/A';
    final String prd = pos['prd'] ?? 'N/A';
    final double netqty = double.tryParse(pos['netqty']?.toString() ?? '0') ?? 0.0;
    final double lp = double.tryParse(pos['lp']?.toString() ?? '0') ?? 0.0;
    final double avg = double.tryParse(pos['netavgprc']?.toString() ?? '0') ?? 0.0;
    final double pnl = calculatePositionPnL(pos);
    final bool isProfit = pnl >= 0;
    final bool canClose = netqty != 0;

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
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white, letterSpacing: -0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: CredColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              prd,
                              style: const TextStyle(color: CredColors.primary, fontSize: 10, fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (canClose)
                            InkWell(
                              onTap: () => _showCloseConfirmation(context, ref, pos),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: CredColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'CLOSE',
                                  style: TextStyle(color: CredColors.error, fontSize: 10, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isProfit ? '+' : ''}₹${pnl.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: isProfit ? CredColors.success : CredColors.error,
                      ),
                    ),
                    const Text('NET P&L', style: TextStyle(color: CredColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
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
                  _buildMetricColumn('QUANTITY', netqty.toInt().toString(), Colors.white),
                  _buildMetricColumn('AVG PRICE', '₹${avg.toStringAsFixed(2)}', CredColors.textMuted),
                  _buildMetricColumn('LTP', '₹${lp.toStringAsFixed(2)}', CredColors.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCloseConfirmation(BuildContext context, WidgetRef ref, dynamic pos) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildConfirmationDialog(
        context,
        'CLOSE POSITION',
        'Confirm closure of ${pos['tsym']} (${pos['netqty']} units) at market price.',
        'SQUARE OFF',
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(orderExecutionProvider).squareOffPosition(pos);
        if (context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${pos['tsym']} abandoned successfully'),
              backgroundColor: CredColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        ref.read(positionsProvider.notifier).refresh();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Protocol Failure: $e'), backgroundColor: CredColors.error, behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }

  Widget _buildMetricColumn(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: CredColors.textMuted, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: valueColor)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assessment_outlined, size: 64, color: Colors.white.withValues(alpha: 0.05)),
          const SizedBox(height: 16),
          const Text('NO ACTIVE POSITIONS', style: TextStyle(fontSize: 12, color: CredColors.textMuted, fontWeight: FontWeight.w900, letterSpacing: 2.0)),
        ],
      ),
    );
  }
}
