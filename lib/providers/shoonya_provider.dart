import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/shoonya_api_client.dart';
import '../services/trading_strategy_manager.dart';
import '../services/order_execution_service.dart';
import '../utils/constants.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../services/firestore_service.dart';

final shoonyaClientProvider = Provider((ref) => ShoonyaApiClient());
final storageProvider = Provider((ref) => const FlutterSecureStorage());
final firestoreServiceProvider = Provider((ref) => FirestoreService());

final tradingStrategyProvider = Provider((ref) {
  final client = ref.watch(shoonyaClientProvider);
  final storage = ref.watch(storageProvider);
  final firestore = ref.watch(firestoreServiceProvider);
  return TradingStrategyManager(
    client,
    storage,
    firestore,
    onUpdate: (newState) {
      ref.read(strategyStateProvider.notifier).update(newState);
    },
  );
});

final orderExecutionProvider = Provider((ref) {
  final client = ref.watch(shoonyaClientProvider);
  return OrderExecutionService(client);
});

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;

  AuthState({this.isAuthenticated = false, this.isLoading = false, this.error});
}

class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription? _firestoreSubscription;

  @override
  AuthState build() {
    _checkStoredSession();
    return AuthState();
  }

  Future<void> _checkStoredSession() async {
    try {
      final userId = await _storage.read(key: 'userId');
      final token = await _storage.read(key: 'susertoken');
      final loginDate = await _storage.read(key: 'loginDate');
      
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (userId != null && token != null && loginDate == today) {
        _client.setSession(userId, token);
        _client.connectWebSocket();
        _strategy.startScheduler();
        _strategy.loadPersistedStrikes();
        _startFirestoreSync(userId);
        ref.read(exitStrategyProvider.notifier).startMonitoring();
        state = AuthState(isAuthenticated: true);
      }
    } catch (e) {
      debugPrint('Error restoring session: $e');
    }
  }

  ShoonyaApiClient get _client => ref.read(shoonyaClientProvider);
  FlutterSecureStorage get _storage => ref.read(storageProvider);
  TradingStrategyManager get _strategy => ref.read(tradingStrategyProvider);
  FirestoreService get _firestore => ref.read(firestoreServiceProvider);

  void _startFirestoreSync(String userId) {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = _firestore.streamStrategyState(userId).listen((cloudData) {
      _strategy.handleFirestoreUpdate(cloudData);
    });
  }

  Future<void> login({
    required String userId,
    required String password,
    String? totpSecret,
  }) async {
    state = AuthState(isLoading: true);
    try {
      await _client.login(
        userId: userId,
        password: password,
        apiKey: ShoonyaConfig.apiKey,
        vendorCode: ShoonyaConfig.vendorCode,
        imei: ShoonyaConfig.imei,
        totpSecret: totpSecret,
      );

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _storage.write(key: 'userId', value: userId);
      await _storage.write(key: 'susertoken', value: _client.sessionToken);
      await _storage.write(key: 'loginDate', value: today);

      _client.connectWebSocket();
      _strategy.startScheduler();
      _strategy.loadPersistedStrikes();
      _startFirestoreSync(userId);
      ref.read(exitStrategyProvider.notifier).startMonitoring();

      state = AuthState(isAuthenticated: true);
    } catch (e) {
      state = AuthState(error: e.toString());
    }
  }

  void logout() async {
    _strategy.stopScheduler();
    _firestoreSubscription?.cancel();
    ref.read(exitStrategyProvider.notifier).stopMonitoring();
    _client.closeWebSocket();
    await _storage.delete(key: 'susertoken');
    await _storage.delete(key: 'loginDate');
    state = AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class StrategyNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void update(Map<String, dynamic>? newState) {
    state = newState;
  }
}

final strategyStateProvider = NotifierProvider<StrategyNotifier, Map<String, dynamic>?>(StrategyNotifier.new);

class ExitStrategyNotifier extends Notifier<Map<String, dynamic>> {
  Timer? _monitoringTimer;
  bool _isProcessingExit = false;

  @override
  Map<String, dynamic> build() {
    return {
      'status': 'Idle',
      'peakPnL': 0.0,
      'trailingSL': null, // null means trail hasn't started yet
      'exitTime': '15:00',
      'lastExitReason': null,
      'lastRunDate': null,
    };
  }

  void startMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkConditions();
    });
    debugPrint('Exit Strategy Monitoring Started');
  }

  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    debugPrint('Exit Strategy Monitoring Stopped');
  }

  Future<void> _checkConditions() async {
    if (_isProcessingExit) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // We only reset peak if it's a new day, or if we want to reset for a new strategy run
    // For now, let's assume it's for the current day's active positions.

    final totalPnL = ref.read(totalPnLProvider);
    final now = DateTime.now();
    final currentTime = DateFormat('HH:mm').format(now);

    // Check for open positions first
    final positions = ref.read(positionsProvider).value ?? [];
    final bool hasOpenPositions = positions.any((p) {
      final qty = double.tryParse(p['netqty']?.toString() ?? '0') ?? 0;
      return qty != 0;
    });

    if (!hasOpenPositions) {
      // If no open positions, we might want to reset peakPnL for the next run, 
      // but definitely don't trigger any exit logic.
      if (state['peakPnL'] != 0.0 || state['trailingSL'] != null) {
        state = {
          ...state,
          'peakPnL': 0.0,
          'trailingSL': null,
        };
      }
      return;
    }

    bool shouldExit = false;
    String reason = '';

    // Update Peak P&L
    double currentPeak = state['peakPnL'] ?? 0.0;
    if (totalPnL > currentPeak) {
      currentPeak = totalPnL;
    }

    // Calculate Trailing SL
    // Logic: Starts at 200 profit, SL is 50. Increases by 50 for every 50 profit.
    double? currentTrail;
    if (currentPeak >= 200) {
      currentTrail = 50 + ((currentPeak - 200) ~/ 50) * 50;
    }

    // Update state with new peak and trail
    if (currentPeak != state['peakPnL'] || currentTrail != state['trailingSL']) {
       state = {
         ...state,
         'peakPnL': currentPeak,
         'trailingSL': currentTrail,
       };
    }

    // Condition 1: Trailing SL Hit
    if (currentTrail != null && totalPnL <= currentTrail) {
      shouldExit = true;
      reason = 'Trailing SL (₹${currentTrail.toStringAsFixed(2)}) Hit @ ₹${totalPnL.toStringAsFixed(2)}';
    } 
    // Condition 2: Time Exit (3:00 PM)
    else if (currentTime == state['exitTime'] || (now.hour >= 15 && now.hour < 16)) {
       final positions = ref.read(positionsProvider).value ?? [];
       final hasOpenPositions = positions.any((p) {
         final qty = double.tryParse(p['netqty']?.toString() ?? '0') ?? 0;
         return qty != 0;
       });

       if (hasOpenPositions) {
         shouldExit = true;
         reason = 'Time Exit (3:00 PM) reached with open positions';
       }
    }

    if (shouldExit && state['lastRunDate'] != today) {
      _isProcessingExit = true;
      state = {
        ...state,
        'status': 'Exiting...',
      };

      try {
        debugPrint('Triggering Auto-Exit: $reason');
        final executor = ref.read(orderExecutionProvider);
        await executor.squareOffAllPositions();
        
        state = {
          ...state,
          'status': 'Completed',
          'lastExitReason': reason,
          'lastRunDate': today,
        };
      } catch (e) {
        state = {
          ...state,
          'status': 'Failed',
          'error': e.toString(),
        };
      } finally {
        _isProcessingExit = false;
      }
    }
  }
}

final exitStrategyProvider = NotifierProvider<ExitStrategyNotifier, Map<String, dynamic>>(ExitStrategyNotifier.new);

class OrderBookNotifier extends AsyncNotifier<List<dynamic>> {
  @override
  FutureOr<List<dynamic>> build() {
    return _fetchOrders();
  }

  Future<List<dynamic>> _fetchOrders() async {
    final client = ref.read(shoonyaClientProvider);
    return await client.getOrderBook();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchOrders());
  }
}

final orderBookProvider = AsyncNotifierProvider<OrderBookNotifier, List<dynamic>>(OrderBookNotifier.new);

class TradeBookNotifier extends AsyncNotifier<List<dynamic>> {
  @override
  FutureOr<List<dynamic>> build() {
    return _fetchTrades();
  }

  Future<List<dynamic>> _fetchTrades() async {
    final client = ref.read(shoonyaClientProvider);
    return await client.getTradeBook();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchTrades());
  }
}

final tradeBookProvider = AsyncNotifierProvider<TradeBookNotifier, List<dynamic>>(TradeBookNotifier.new);

class PositionsNotifier extends AsyncNotifier<List<dynamic>> {
  StreamSubscription? _socketSubscription;

  @override
  FutureOr<List<dynamic>> build() async {
    final positions = await _fetchPositions();
    _subscribeToPositions(positions);
    _listenToSocket();
    return positions;
  }

  Future<List<dynamic>> _fetchPositions() async {
    final client = ref.read(shoonyaClientProvider);
    return await client.getPositionBook();
  }

  void _subscribeToPositions(List<dynamic> positions) {
    if (positions.isEmpty) return;
    final client = ref.read(shoonyaClientProvider);
    final keys = positions
        .map((p) => '${p['exch']}|${p['token']}')
        .toList();
    client.subscribeTouchline(keys);
  }

  void _listenToSocket() {
    _socketSubscription?.cancel();
    final client = ref.read(shoonyaClientProvider);
    _socketSubscription = client.socketStream.listen((data) {
      if (data['t'] == 'tk' || data['t'] == 'tf') {
        _updatePrice(data);
      }
    });
  }

  void _updatePrice(Map<String, dynamic> update) {
    final token = update['tk']?.toString();
    if (token == null || state.value == null) return;

    final updatedPositions = state.value!.map((p) {
      if (p['token']?.toString() == token) {
        return {...p, ...update};
      }
      return p;
    }).toList();

    state = AsyncValue.data(updatedPositions);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final positions = await _fetchPositions();
      _subscribeToPositions(positions);
      return positions;
    });
  }
}

final positionsProvider = AsyncNotifierProvider<PositionsNotifier, List<dynamic>>(PositionsNotifier.new);

double calculatePositionPnL(dynamic pos) {
  final double netqty = double.tryParse(pos['netqty']?.toString() ?? '0') ?? 0.0;
  final double lp = double.tryParse(pos['lp']?.toString() ?? '0') ?? 0.0;
  final double netavgprc = double.tryParse(pos['netavgprc']?.toString() ?? '0') ?? 0.0;
  final double prcftr = double.tryParse(pos['prcftr']?.toString() ?? '1') ?? 1.0;
  final double rpnl = double.tryParse(pos['rpnl']?.toString() ?? '0') ?? 0.0;

  final double urmtom = netqty * (lp - netavgprc) * prcftr;
  return rpnl + urmtom;
}

final totalPnLProvider = Provider<double>((ref) {
  final positionsAsync = ref.watch(positionsProvider);
  return positionsAsync.maybeWhen(
    data: (positions) {
      double total = 0.0;
      for (var pos in positions) {
        total += calculatePositionPnL(pos);
      }
      return total;
    },
    orElse: () => 0.0,
  );
});
