import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:otp/otp.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';

class ShoonyaApiClient {
  static const String baseUrl = 'https://api.shoonya.com/NorenWClientTP/';
  static const String socketUrl = 'wss://api.shoonya.com/NorenWSTP/';
  
  String? _sessionToken;
  String? _userId;
  WebSocketChannel? _channel;
  final _socketStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  
  final Set<String> _activeSubscriptions = {};
  int _reconnectAttempts = 0;
  bool _isConnecting = false;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get socketStream => _socketStreamController.stream;
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  String _sha256Hash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  Future<Map<String, dynamic>> login({
    required String userId,
    required String password,
    required String apiKey,
    required String vendorCode,
    required String imei,
    String? totpSecret,
    String? totpCode,
  }) async {
    final hashedPassword = _sha256Hash(password);
    final appKey = _sha256Hash('$userId|$apiKey');
    
    String finalTotp = totpCode ?? '';
    if (totpSecret != null && (totpCode == null || totpCode.isEmpty)) {
      final trimmedSecret = totpSecret.trim();
      // Use as is if it's already a 6-digit code
      if (RegExp(r'^\d{6}$').hasMatch(trimmedSecret)) {
        finalTotp = trimmedSecret;
      } else {
        try {
          String cleanSecret = trimmedSecret.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
          while (cleanSecret.length % 8 != 0) {
            cleanSecret += '=';
          }
          finalTotp = OTP.generateTOTPCodeString(
            cleanSecret,
            DateTime.now().millisecondsSinceEpoch,
            interval: 30,
            algorithm: Algorithm.SHA1,
            isGoogle: true,
          );
        } catch (e) {
          throw Exception('TOTP Selection Error: ${e.toString()}');
        }
      }
    }

    final payload = {
      'jData': jsonEncode({
        'apkversion': '1.0.0',
        'uid': userId,
        'pwd': hashedPassword,
        'vc': vendorCode,
        'appkey': appKey,
        'imei': imei,
        'source': 'API',
        'factor2': finalTotp,
      }),
      'jKey': '',
    };

    print('Requesting Login for $userId...');
    final response = await http.post(
      Uri.parse('${baseUrl}QuickAuth'),
      body: 'jData=${payload['jData']}&jKey=',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['stat'] == 'Ok') {
        final newToken = data['susertoken'];
        _sessionToken = newToken;
        _userId = userId;
        debugPrint('--- Login Success ---');
        debugPrint('New Token: $newToken');
        return data;
      } else {
        print('Login Failed: ${data['emsg']}');
        throw Exception('Login failed: ${data['emsg']}');
      }
    } else {
      throw Exception('HTTP Error: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> searchScrip({
    required String searchText,
    String? exchange,
  }) async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'stext': searchText,
        if (exchange != null) 'exch': exchange,
      }),
      'jKey': _sessionToken,
    };

    final jData = jsonEncode({
      'uid': _userId,
      'stext': searchText.replaceAll(' ', '%20'),
      if (exchange != null) 'exch': exchange,
    });

    final url = '${baseUrl}SearchScrip/';
    final body = 'jData=$jData&jKey=$_sessionToken';
    debugPrint('--- SearchScrip Request ---');
    debugPrint('URL: $url');
    debugPrint('Body: $body');

    final response = await http.post(
      Uri.parse(url),
      body: body,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    debugPrint('--- SearchScrip Response ---');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['stat'] != 'Ok') {
        print('SearchScrip Error: ${data['emsg']}');
      }
      return data;
    } else {
      throw Exception('Search failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> addMultiScrips({
    required String watchlistName,
    required List<Map<String, String>> scrips,
  }) async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    // Format: NSE|22#BSE|506734
    final scripsString = scrips
        .map((s) => '${s['exchange']}|${s['token']}')
        .join('#');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'wlname': watchlistName,
        'scrips': scripsString,
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}AddMultiScripsToMW'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['stat'] != 'Ok') {
        print('AddMultiScrips Error: ${data['emsg']}');
      }
      return data;
    } else {
      throw Exception('AddMultiScrips failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> deleteMultiScrips({
    required String watchlistName,
    required List<Map<String, String>> scrips,
  }) async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    // Format: NSE|22#BSE|506734
    final scripsString = scrips
        .map((s) => '${s['exchange']}|${s['token']}')
        .join('#');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'wlname': watchlistName,
        'scrips': scripsString,
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}DeleteMultiMWScrips'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['stat'] != 'Ok') {
        print('DeleteMultiScrips Error: ${data['emsg']}');
      }
      return data;
    } else {
      throw Exception('DeleteMultiScrips failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getIndexList({required String exchange}) async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'exch': exchange,
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}GetIndexList'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('GetIndexList failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getQuotes({
    required String exchange,
    required String token,
  }) async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'exch': exchange,
        'token': token,
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}GetQuotes'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['stat'] != 'Ok') {
        print('GetQuotes Error for $token: ${data['emsg']}');
      }
      return data;
    } else {
      throw Exception('GetQuotes failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getWatchList(String watchlistName) async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'wlname': watchlistName,
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}MarketWatch'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('MarketWatch failed: ${response.statusCode}');
    }
  }

  bool get isAuthenticated => _sessionToken != null;
  String? get sessionToken => _sessionToken;
  String? get userId => _userId;

  void setSession(String userId, String token) {
    debugPrint('--- Session Restored/Set ---');
    debugPrint('User: $userId');
    debugPrint('Token: $token');
    _userId = userId;
    _sessionToken = token;
  }

  Future<void> connectWebSocket() async {
    if (_sessionToken == null || _userId == null) return;
    if (_isConnecting) return;
    
    _isConnecting = true;
    _reconnectTimer?.cancel();

    try {
      debugPrint('--- WebSocket Connection Details ---');
      debugPrint('URL: $socketUrl');
      
      _channel = WebSocketChannel.connect(Uri.parse(socketUrl));
      
      final connectMessage = {
        't': 'c',
        'uid': _userId,
        'actid': _userId,
        'source': 'API',
        'susertoken': _sessionToken,
      };

      final connectJson = jsonEncode(connectMessage);
      debugPrint('Connect Message: $connectJson');

      _channel!.sink.add(connectJson);

      _channel!.stream.listen(
        (message) {
          debugPrint('WebSocket Received: $message');
          final data = jsonDecode(message);
          _socketStreamController.add(data);
          
          if (data['t'] == 'ck') {
            _isConnecting = false;
            if (data['s'] == 'OK') {
              _reconnectAttempts = 0;
              _connectionStatusController.add(true);
              print('WebSocket Authenticated');
              _resubscribeAll();
            } else {
              print('WebSocket Authentication Failed: ${data['emsg']}');
              _connectionStatusController.add(false);
            }
          }
        },
        onError: (err) {
          print('WebSocket Error: $err');
          _handleDisconnect();
        },
        onDone: () {
          print('WebSocket Closed');
          _handleDisconnect();
        },
      );
    } catch (e) {
      print('WebSocket Connection Error: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnecting = false;
    _connectionStatusController.add(false);
    _channel = null;
    
    if (_sessionToken != null) {
      _reconnectAttempts++;
      final delay = _reconnectAttempts < 10 
          ? Duration(seconds: _reconnectAttempts * 2) 
          : const Duration(seconds: 30);
          
      print('Reconnecting in ${delay.inSeconds}s (Attempt $_reconnectAttempts)');
      _reconnectTimer = Timer(delay, () => connectWebSocket());
    }
  }

  void _resubscribeAll() {
    if (_activeSubscriptions.isEmpty) return;
    print('Re-subscribing to ${_activeSubscriptions.length} items...');
    final keys = _activeSubscriptions.toList();
    
    // Shoonya API suggests chunking if keys are many, but for now we'll send all
    final subMessage = {
      't': 't',
      'k': keys.join('#'),
    };
    _channel?.sink.add(jsonEncode(subMessage));
  }

  Future<List<dynamic>> getOrderBook() async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'prd': '', // empty for all products
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}OrderBook'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data;
      } else if (data is Map && data['stat'] == 'Ok') {
        return data['values'] ?? [];
      } else if (data is Map && data['stat'] == 'Not_Ok') {
        final emsg = (data['emsg'] ?? '').toString().toLowerCase();
        if (emsg.contains('no data')) return [];
        throw Exception(data['emsg']);
      }
      return [];
    } else {
      throw Exception('OrderBook failed: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> getPositionBook() async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'actid': _userId,
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}PositionBook'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data;
      } else if (data is Map && data['stat'] == 'Ok') {
        return data['values'] ?? [];
      } else if (data is Map && data['stat'] == 'Not_Ok') {
        final emsg = (data['emsg'] ?? '').toString().toLowerCase();
        if (emsg.contains('no data')) return [];
        throw Exception(data['emsg']);
      }
      return [];
    } else {
      throw Exception('PositionBook failed: ${response.statusCode}');
    }
  }

  Future<List<dynamic>> getTradeBook() async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'actid': _userId,
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}TradeBook'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        return data;
      } else if (data is Map && data['stat'] == 'Ok') {
        return data['values'] ?? [];
      } else if (data is Map && data['stat'] == 'Not_Ok') {
        final emsg = (data['emsg'] ?? '').toString().toLowerCase();
        if (emsg.contains('no data')) return [];
        throw Exception(data['emsg']);
      }
      return [];
    } else {
      throw Exception('TradeBook failed: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> placeOrder({
    required String exchange,
    required String tradingSymbol,
    required String quantity,
    required String price,
    required String product,
    required String transactionType,
    required String priceType,
    required String retention,
    String? triggerPrice,
    String? disclosedQuantity,
    String? remarks,
  }) async {
    if (_sessionToken == null) throw Exception('Not authenticated');

    final payload = {
      'jData': jsonEncode({
        'uid': _userId,
        'actid': _userId,
        'exch': exchange,
        'tsym': tradingSymbol,
        'qty': quantity,
        'prc': price,
        'prd': product,
        'trantype': transactionType,
        'prctyp': priceType,
        'ret': retention,
        if (triggerPrice != null) 'trgprc': triggerPrice,
        if (disclosedQuantity != null) 'dscqty': disclosedQuantity,
        if (remarks != null) 'remarks': remarks,
        'ordersource': 'MOB',
      }),
      'jKey': _sessionToken,
    };

    final response = await http.post(
      Uri.parse('${baseUrl}PlaceOrder'),
      body: 'jData=${payload['jData']}&jKey=${payload['jKey']}',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    );

    final data = jsonDecode(response.body);
    if (data['stat'] != 'Ok') {
      debugPrint('PlaceOrder Error: ${data['emsg']}');
    } else {
      debugPrint('Order placed successfully: ${data['norenordno']}');
    }
    return data;
  }

  void subscribeTouchline(List<String> keys) {
    _activeSubscriptions.addAll(keys);
    if (_channel == null) return;
    
    final subMessage = {
      't': 't',
      'k': keys.join('#'),
    };
    
    _channel!.sink.add(jsonEncode(subMessage));
  }

  void unsubscribeTouchline(List<String> keys) {
    for (final key in keys) {
      _activeSubscriptions.remove(key);
    }
    if (_channel == null) return;
    
    final unsubMessage = {
      't': 'u',
      'k': keys.join('#'),
    };
    
    _channel!.sink.add(jsonEncode(unsubMessage));
  }

  void closeWebSocket() {
    _channel?.sink.close();
  }
}
