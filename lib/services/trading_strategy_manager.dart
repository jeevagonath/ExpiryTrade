import 'dart:async';
import 'package:flutter/foundation.dart';
import 'shoonya_api_client.dart';
import 'package:intl/intl.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import 'firestore_service.dart';

class TradingStrategyManager {
  final ShoonyaApiClient apiClient;
  final FlutterSecureStorage storage;
  final FirestoreService firestore;
  final Function(Map<String, dynamic>)? onUpdate;
  
  Timer? _timer;
  Map<String, dynamic> _state = {
    'status': 'Idle',
    'lastRun': null,
    'lastRunDate': null,
    'selectedStrikes': null,
    'error': null,
  };

  TradingStrategyManager(this.apiClient, this.storage, this.firestore, {this.onUpdate});

  Future<void> loadPersistedStrikes() async {
    try {
      // 1. Try Firestore first (for cross-device sync)
      final userId = apiClient.userId;
      if (userId != null) {
        final cloudState = await firestore.getStrategyState(userId);
        if (cloudState != null && cloudState['selectedStrikes'] != null) {
          _state['selectedStrikes'] = cloudState['selectedStrikes'];
          _state['lastRunDate'] = cloudState['lastRunDate'];
          _notify();
          debugPrint('Restored strategy state from Firestore');
          return;
        }
      }

      // 2. Fallback to local storage
      final saved = await storage.read(key: 'selectedStrikes');
      if (saved != null) {
        _state['selectedStrikes'] = jsonDecode(saved);
      }
      
      final lastDate = await storage.read(key: 'lastRunDate');
      if (lastDate != null) {
        _state['lastRunDate'] = lastDate;
      }
      
      _notify();
      debugPrint('Restored strategy state from local storage');
    } catch (e) {
      debugPrint('Error loading persisted strategy: $e');
    }
  }

  Future<void> _saveState() async {
    try {
      // 1. Save locally
      if (_state['selectedStrikes'] != null) {
        await storage.write(
          key: 'selectedStrikes',
          value: jsonEncode(_state['selectedStrikes']),
        );
      } else {
        await storage.delete(key: 'selectedStrikes');
      }

      if (_state['lastRunDate'] != null) {
        await storage.write(key: 'lastRunDate', value: _state['lastRunDate']);
      }

      // 2. Sync to Firestore
      final userId = apiClient.userId;
      if (userId != null) {
        await firestore.saveStrategyState(userId, {
          'selectedStrikes': _state['selectedStrikes'],
          'lastRunDate': _state['lastRunDate'],
          'status': _state['status'],
        });
      }
    } catch (e) {
      debugPrint('Error saving strategy state: $e');
    }
  }

  void handleFirestoreUpdate(Map<String, dynamic>? cloudData) {
    if (cloudData == null) return;
    
    // Only update if cloud data is different and we aren't currently running a strategy
    if (_state['status'] != 'Running...' && cloudData['selectedStrikes'] != _state['selectedStrikes']) {
       _state['selectedStrikes'] = cloudData['selectedStrikes'];
       _state['lastRunDate'] = cloudData['lastRunDate'];
       _notify();
       debugPrint('Strategy state updated from Firestore sync');
    }
  }

  Future<void> clearStrategy() async {
    _state['selectedStrikes'] = null;
    _state['status'] = 'Idle';
    await _saveState();

    final userId = apiClient.userId;
    if (userId != null) {
      await firestore.clearStrategyState(userId);
    }
    
    _notify();
  }

  void startScheduler() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkTimeAndRun();
    });
    debugPrint('Strategy Scheduler Started');
  }

  void stopScheduler() {
    _timer?.cancel();
    _timer = null;
    debugPrint('Strategy Scheduler Stopped');
  }

  void _checkTimeAndRun() {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final currentTime = DateFormat('HH:mm').format(now);
    final weekday = now.weekday; // 1=Mon, 2=Tue, ..., 4=Thu

    // If it's already run today, skip
    if (_state['lastRunDate'] == today) return;

    // Check for Tuesday (2) @ 13:15 -> NIFTY
    if (weekday == 2 && currentTime == '13:15') {
      debugPrint('Auto-triggering Strategy for NIFTY...');
      _state['lastRunDate'] = today;
      _saveState(); // Save immediately to prevent double-runs on restart
      runStrategy('NIFTY', 'NSE', '26000');
    } 
    // Check for Thursday (4) @ 13:15 -> SENSEX
    else if (weekday == 4 && currentTime == '13:15') {
      debugPrint('Auto-triggering Strategy for SENSEX...');
      _state['lastRunDate'] = today;
      _saveState(); // Save immediately to prevent double-runs on restart
      runStrategy('SENSEX', 'BSE', '1');
    }
  }

  void runManualTest() {
    final now = DateTime.now();
    final weekday = now.weekday;
    
    // Default to NIFTY on Tuesday, SENSEX otherwise
    if (weekday == 2) {
      debugPrint('Manual Test: Triggering NIFTY Protocol');
      runStrategy('NIFTY', 'NSE', '26000');
    } else {
      debugPrint('Manual Test: Triggering SENSEX Protocol');
      runStrategy('SENSEX', 'BSE', '1');
    }
  }

  Future<void> runStrategy(String indexName, String exchange, String token) async {
    _state['status'] = 'Running for $indexName...';
    _state['error'] = null;
    _notify();

    try {
      // 1. Get Spot Price
      final quotes = await apiClient.getQuotes(exchange: exchange, token: token);
      if (quotes['stat'] != 'Ok') throw Exception('Failed to get spot price');
      
      final double spotPrice = double.parse(quotes['lp']);
      debugPrint('Spot Price for $indexName: $spotPrice');

      // 2. Calculate strikes (Buffered Floor for PE, Buffered Ceil for CE)
      final int strikeInterval = indexName == 'NIFTY' ? 50 : 100;
      final int buffer = indexName == 'NIFTY' ? 15 : 25;
      
      int peStrike = ((spotPrice - buffer) / strikeInterval).floor() * strikeInterval;
      int ceStrike = ((spotPrice + buffer) / strikeInterval).ceil() * strikeInterval;
      
      debugPrint('Spot: $spotPrice, PE Strike: $peStrike, CE Strike: $ceStrike');

      // 3. Search for CE and PE options at calculated strikes
      final optExch = (exchange == 'NSE' ? 'NFO' : 'BFO');
      
      Future<dynamic> fetchContract(int strike, String type) async {
        final queryIndex = indexName.toUpperCase().trim();
        if (queryIndex.isEmpty) throw Exception('Index name is empty');
        
        final searchQuery = '$queryIndex $strike $type';
        debugPrint('--- Strategy Search Trace ---');
        debugPrint('Index: $queryIndex, Strike: $strike, Type: $type');
        debugPrint('Final Query: "$searchQuery"');
        
        final searchResult = await apiClient.searchScrip(searchText: searchQuery, exchange: optExch);
        
        if (searchResult['stat'] == 'Ok' && searchResult['values'] != null && searchResult['values'].isNotEmpty) {
          var contract = searchResult['values'][0];
          try {
            final quote = await apiClient.getQuotes(
              exchange: contract['exch'],
              token: contract['token'].toString(),
            );
            if (quote['stat'] == 'Ok') {
              return {...(contract as Map<String, dynamic>), ...quote};
            }
          } catch (e) {
            debugPrint('Error fetching quote for $searchQuery: $e');
          }
          return contract;
        }
        return null;
      }

      final ceContract = await fetchContract(ceStrike, 'CE');
      final peContract = await fetchContract(peStrike, 'PE');

      _state['status'] = 'Completed';
      _state['selectedStrikes'] = {
        'index': indexName,
        'spot': spotPrice,
        'ce': ceContract,
        'pe': peContract,
        'time': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      };

      await _saveState();

      // 4. Add to Watchlist for live price updates
      List<Map<String, String>> scripsToWatch = [];
      void addIfNotNull(dynamic contract) {
        if (contract != null) {
          scripsToWatch.add({
            'exchange': contract['exch'].toString(), 
            'token': contract['token'].toString()
          });
        }
      }
      addIfNotNull(ceContract);
      addIfNotNull(peContract);

      if (scripsToWatch.isNotEmpty) {
        await apiClient.addMultiScrips(
          watchlistName: 'MW1',
          scrips: scripsToWatch,
        );
        debugPrint('Added ${scripsToWatch.length} strikes to watchlist');
      }

    } catch (e) {
      _state['status'] = 'Failed';
      _state['error'] = e.toString();
      debugPrint('Strategy Error: $e');
    } finally {
      _notify();
    }
  }

  void _notify() {
    onUpdate?.call(Map.from(_state));
  }
}
