import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/shoonya_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/cred_theme.dart';
import '../widgets/cred_widgets.dart';
import 'dart:async';

class StrategyScreen extends ConsumerStatefulWidget {
  const StrategyScreen({super.key});

  @override
  ConsumerState<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends ConsumerState<StrategyScreen> {
  StreamSubscription? _socketSubscription;
  Map<String, dynamic> _livePrices = {};
  Set<String> _selectedTokens = {};
  bool _selectionInitialized = false;

  @override
  void initState() {
    super.initState();
    _initWebSocket();
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  void _initWebSocket() async {
    final client = ref.read(shoonyaClientProvider);
    _socketSubscription = client.socketStream.listen(_handleSocketMessage);
  }

  void _handleSocketMessage(Map<String, dynamic> data) {
    if (data['t'] == 'tk' || data['t'] == 'tf') {
      setState(() {
        final token = data['tk']?.toString();
        if (token != null) {
          _livePrices[token] = data;
        }
      });
    }
  }

  String? _lastSubscribedStrikes;

  void _subscribeToStrikes(Map<String, dynamic>? strikes) {
    if (strikes == null) return;
    
    final List<String> tokens = [];
    ['ce', 'pe'].forEach((key) {
      final contract = strikes[key];
      if (contract != null) {
        tokens.add((contract['token'] ?? contract['tk']).toString());
      }
    });

    if (tokens.isEmpty) return;
    
    final subKey = tokens.join('_');
    if (_lastSubscribedStrikes == subKey) return;
    _lastSubscribedStrikes = subKey;

    final client = ref.read(shoonyaClientProvider);
    final indexName = strikes['index'] ?? 'NIFTY';
    final exchange = indexName == 'SENSEX' ? 'BFO' : 'NFO';
    
    final keys = tokens.map((t) => '$exchange|$t').toList();
    client.subscribeTouchline(keys);
    debugPrint('Subscribed to strikes: $keys');

    // Initialize selection state if not already done for this set of strikes
    if (!_selectionInitialized) {
      setState(() {
        _selectedTokens = Set.from(tokens);
        _selectionInitialized = true;
      });
    }
  }

  void _toggleSelection(String token) {
    setState(() {
      if (_selectedTokens.contains(token)) {
        _selectedTokens.remove(token);
      } else {
        _selectedTokens.add(token);
      }
    });
  }

  void _handleBuyNow(Map<String, dynamic> strikes) async {
    final List<Map<String, dynamic>> selectedContracts = [];
    ['ce', 'pe'].forEach((key) {
      final contract = strikes[key];
      if (contract != null && _selectedTokens.contains((contract['token'] ?? contract['tk']).toString())) {
        selectedContracts.add(contract as Map<String, dynamic>);
      }
    });

    if (selectedContracts.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No strikes selected'),
          backgroundColor: CredColors.error,
        ),
      );
      return;
    }

    final indexName = strikes['index'] ?? 'NIFTY';
    final exchange = indexName == 'SENSEX' ? 'BFO' : 'NFO';
    final settings = ref.read(settingsProvider);
    final int lotMultiplier = indexName == 'SENSEX' ? settings.sensexLots : settings.niftyLots;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildOrderConfirmationDialog(
        context, 
        selectedContracts,
        lotMultiplier,
        exchange
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Shielding your position...'),
        backgroundColor: CredColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final client = ref.read(shoonyaClientProvider);
      final List<String> errors = [];
      int successCount = 0;

      for (var contract in selectedContracts) {
        final lotSize = contract['ls'] ?? '0';
        final int baseQty = int.tryParse(lotSize.toString()) ?? 0;
        final int finalQty = baseQty * lotMultiplier;

        final result = await client.placeOrder(
          exchange: exchange,
          tradingSymbol: contract['tsym'],
          quantity: finalQty.toString(),
          price: '0',
          product: 'M',
          transactionType: 'B',
          priceType: 'MKT',
          retention: 'DAY',
          remarks: 'Strategy Buy - ${contract['tsym']}',
        );

        if (result['stat'] == 'Ok') {
          successCount++;
        } else {
          errors.add('${contract['tsym']}: ${result['emsg']}');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      
      if (errors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('All $successCount orders deployed!'),
            backgroundColor: CredColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deployed: $successCount | Failed: ${errors.length}\n${errors.join('\n')}'),
            backgroundColor: CredColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Critical Error: $e'),
          backgroundColor: CredColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildOrderConfirmationDialog(
    BuildContext context, 
    List<Map<String, dynamic>> selectedContracts,
    int lotMultiplier,
    String exchange
  ) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: CredCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deploy Protocol',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Market Entry | $exchange',
              style: const TextStyle(color: CredColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: selectedContracts.map((contract) {
                    final lotSize = contract['ls'] ?? '0';
                    final int baseQty = int.tryParse(lotSize.toString()) ?? 0;
                    final int finalQty = baseQty * lotMultiplier;
                    final ltp = contract['lp'] ?? '0.00';
                    final side = contract['tsym'].toString().contains('CE') ? 'CALL' : 'PUT';
                    final color = side == 'CALL' ? CredColors.success : CredColors.error;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDialogOrderItem(side, contract['tsym'], finalQty, ltp, color),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Abort', style: TextStyle(color: CredColors.textMuted)),
                  ),
                ),
                Expanded(
                  child: CredButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogOrderItem(String side, String tsym, dynamic lot, dynamic ltp, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$side: $tsym',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Lot: $lot | LTP: ₹$ltp',
            style: TextStyle(color: CredColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(strategyStateProvider);

    if (state?['selectedStrikes'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _subscribeToStrikes(state!['selectedStrikes']);
      });
    }

    return Container(
      color: CredColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Strategy Engine',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 20),
            _buildStrategyCard(context, state),
            const SizedBox(height: 20),
            _buildExitStrategyCard(context),
            const SizedBox(height: 20),
            if (state?['selectedStrikes'] != null)
              _buildSelectedStrikesCard(state!['selectedStrikes']),
            if (state?['selectedStrikes'] == null)
              CredCard(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.auto_awesome, size: 48, color: CredColors.primary.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      const Text(
                        'Engine on Standby',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Will activate on Tuesday/Thursday',
                        style: TextStyle(color: CredColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExitStrategyCard(BuildContext context) {
    final exitState = ref.watch(exitStrategyProvider);
    final isCompleted = exitState['status'] == 'Completed';

    return CredCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Exit Guardian',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isCompleted ? CredColors.success : CredColors.secondary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  exitState['status']?.toUpperCase() ?? 'IDLE',
                  style: TextStyle(
                    color: isCompleted ? CredColors.success : CredColors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildExitTargetItem(
                  Icons.trending_up, 
                  'Peak P&L', 
                  '₹${exitState['peakPnL']?.toStringAsFixed(2) ?? '0.00'}',
                  CredColors.success
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildExitTargetItem(
                  Icons.shield_outlined, 
                  'Floor', 
                  exitState['trailingSL'] != null 
                      ? '₹${exitState['trailingSL']!.toStringAsFixed(2)}'
                      : '---',
                  CredColors.error
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildExitTargetItem(
                  Icons.timer_outlined, 
                  'Deadline', 
                  '${exitState['exitTime']}',
                  CredColors.primary
                ),
              ),
            ],
          ),
          if (exitState['lastExitReason'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, color: CredColors.textMuted, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Last Event: ${exitState['lastExitReason']}',
                      style: const TextStyle(fontSize: 12, color: CredColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExitTargetItem(IconData icon, String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 8),
        Text(
          label, 
          style: const TextStyle(fontSize: 10, color: CredColors.textMuted, fontWeight: FontWeight.bold)
        ),
        Text(
          value, 
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white)
        ),
      ],
    );
  }

  Widget _buildStrategyCard(BuildContext context, Map<String, dynamic>? state) {
    return CredCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Auto Protocol',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      ref.read(tradingStrategyProvider).runStrategy('NIFTY', 'NSE', '26000');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: CredColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.play_arrow, color: CredColors.secondary, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'TEST',
                            style: TextStyle(color: CredColors.secondary, fontSize: 9, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: CredColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      state?['status']?.toUpperCase() ?? 'IDLE',
                      style: const TextStyle(color: CredColors.primary, fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildScheduleItem('TUE', '1:15 PM', 'NIFTY 50')),
              const SizedBox(width: 12),
              Expanded(child: _buildScheduleItem('THU', '1:15 PM', 'SENSEX')),
            ],
          ),
          if (state?['error'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CredColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                state!['error'],
                style: const TextStyle(color: CredColors.error, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CredColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: CredShadows.neumorphicPressed,
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_mode, color: CredColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getNextRunStatus(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (state?['lastRunDate'] != null)
                        Text(
                          'Last sync: ${state!['lastRunDate']}',
                          style: const TextStyle(color: CredColors.textMuted, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleItem(String day, String time, String index) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CredColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: CredShadows.neumorphicPressed,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day, 
            style: const TextStyle(color: CredColors.primary, fontWeight: FontWeight.w900, fontSize: 14)
          ),
          const SizedBox(height: 4),
          Text(
            index, 
            style: const TextStyle(color: CredColors.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedStrikesCard(Map<String, dynamic> strikes) {
    return CredCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Strikes Detected',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: CredColors.textMuted, size: 20),
                onPressed: () {
                  setState(() {
                    _selectionInitialized = false;
                    _selectedTokens.clear();
                  });
                  ref.read(tradingStrategyProvider).clearStrategy();
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strikes['index']?.toUpperCase() ?? '',
                    style: const TextStyle(color: CredColors.secondary, fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Spot @ ${strikes['spot']}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white),
                  ),
                ],
              ),
              Text(
                strikes['time'] ?? '',
                style: const TextStyle(color: CredColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildStrikeBox('CALL OPTION', strikes['ce'], CredColors.success)),
              const SizedBox(width: 12),
              Expanded(child: _buildStrikeBox('PUT OPTION', strikes['pe'], CredColors.error)),
            ],
          ),
          const SizedBox(height: 24),
          CredButton(
            onPressed: () => _handleBuyNow(strikes),
            child: const Text('DEPLOY PROTOCOL'),
          ),
        ],
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CredColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Engine?', style: TextStyle(color: Colors.white)),
        content: const Text('This will reset current strike selection.', style: TextStyle(color: CredColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: CredColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(tradingStrategyProvider).clearStrategy();
              Navigator.pop(context);
            },
            child: const Text('Reset', style: TextStyle(color: CredColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildStrikeBox(String label, dynamic contract, Color accentColor) {
    if (contract == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CredColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: CredShadows.neumorphicPressed,
        ),
        child: Text('WAITING...', style: TextStyle(color: accentColor.withValues(alpha: 0.3), fontSize: 12, fontWeight: FontWeight.w900)),
      );
    }

    final token = (contract['token'] ?? contract['tk'])?.toString();
    final isSelected = token != null && _selectedTokens.contains(token);
    final liveData = token != null ? _livePrices[token] : null;
    final lp = liveData?['lp'] ?? contract['lp'] ?? '0.00';
    final pc = liveData?['pc'] ?? contract['pc'] ?? '0.00';
    final isNegative = pc.toString().startsWith('-');

    return GestureDetector(
      onTap: token != null ? () => _toggleSelection(token) : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CredColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: accentColor, width: 2) : null,
          boxShadow: isSelected ? null : CredShadows.neumorphicPressed,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                ),
                const SizedBox(height: 8),
                Text(
                  contract['tsym']?.toString().split('-').first ?? 'N/A',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Text(
                  lp.toString(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '${!isNegative ? '+' : ''}${liveData?['c'] ?? contract['c'] ?? '0'} ($pc%)',
                  style: TextStyle(
                    color: isNegative ? CredColors.error : CredColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (token != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? accentColor : Colors.transparent,
                    border: Border.all(color: isSelected ? accentColor : CredColors.textMuted, width: 1.5),
                  ),
                  child: isSelected 
                    ? const Icon(Icons.check, size: 14, color: Colors.black)
                    : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getNextRunStatus() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final hour = now.hour;
    final minute = now.minute;

    if (weekday == 2) { // Tuesday
      if (hour < 13 || (hour == 13 && minute < 15)) {
        return 'Today at 01:15 PM [NIFTY]';
      }
      return 'Thursday at 01:15 PM [SENSEX]';
    } else if (weekday < 2) { // Mon
      return 'Tuesday at 01:15 PM [NIFTY]';
    } else if (weekday == 4) { // Thursday
      if (hour < 13 || (hour == 13 && minute < 15)) {
        return 'Today at 01:15 PM [SENSEX]';
      }
      return 'Tuesday at 01:15 PM [NIFTY]';
    } else if (weekday < 4) { // Wed
      return 'Thursday at 01:15 PM [SENSEX]';
    } else { // Fri, Sat, Sun
      return 'Tuesday at 01:15 PM [NIFTY]';
    }
  }
}
