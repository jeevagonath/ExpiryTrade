import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/shoonya_provider.dart';
import '../utils/cred_theme.dart';
import '../widgets/cred_widgets.dart';
import 'dart:async';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  List<dynamic> _watchlist = [];
  Map<String, dynamic> _indicesData = {};
  bool _isSearching = false;
  Timer? _debounce;
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _initWebSocket();
    _loadIndices();
    _loadWatchlist();
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _initWebSocket() async {
    final client = ref.read(shoonyaClientProvider);
    try {
      await client.connectWebSocket();
      _socketSubscription = client.socketStream.listen(_handleSocketMessage);
    } catch (e) {
      debugPrint('WebSocket Init Error: $e');
    }
  }

  void _handleSocketMessage(Map<String, dynamic> data) {
    if (data['t'] == 'tk' || data['t'] == 'tf') {
      _updatePriceFromFeed(data);
    }
  }

  void _updatePriceFromFeed(Map<String, dynamic> feed) {
    setState(() {
      final feedToken = feed['tk']?.toString();
      if (feedToken == null) return;

      // Update Indices
      if (feedToken == '26000') _updateIndex('NIFTY 50', feed);
      if (feedToken == '1') _updateIndex('SENSEX', feed);

      // Update Watchlist
      for (var i = 0; i < _watchlist.length; i++) {
        final itemToken = (_watchlist[i]['token'] ?? _watchlist[i]['tk'])?.toString();
        if (itemToken == feedToken) {
          _watchlist[i] = {..._watchlist[i], ...feed};
        }
      }
    });
  }

  void _updateIndex(String name, Map<String, dynamic> feed) {
    if (_indicesData[name] != null) {
      _indicesData[name] = {...?_indicesData[name] as Map<String, dynamic>?, ...feed};
    }
  }

  Future<void> _loadIndices() async {
    try {
      final client = ref.read(shoonyaClientProvider);
      
      final niftyQuote = await client.getQuotes(exchange: 'NSE', token: '26000');
      final sensexQuote = await client.getQuotes(exchange: 'BSE', token: '1');

      setState(() {
        _indicesData = {
          'NIFTY 50': niftyQuote,
          'SENSEX': sensexQuote,
        };
      });
      client.subscribeTouchline(['NSE|26000', 'BSE|1']);
    } catch (e) {
      debugPrint('Error loading indices: $e');
    }
  }

  Future<void> _loadWatchlist() async {
    try {
      final client = ref.read(shoonyaClientProvider);
      final response = await client.getWatchList('MW1');
      if (response['stat'] == 'Ok' && response['values'] != null) {
        final List<dynamic> items = response['values'];
        
        final List<dynamic> updatedItems = await Future.wait(items.map((item) async {
          try {
            final quote = await client.getQuotes(
              exchange: item['exch'] ?? '', 
              token: (item['token'] ?? item['tk'] ?? '').toString()
            );
            if (quote['stat'] == 'Ok') {
              return {...item, ...quote};
            }
            return item;
          } catch (e) {
            return item;
          }
        }));

        setState(() {
          _watchlist = updatedItems;
        });

        final keys = _watchlist
            .map((e) => '${e['exch']}|${e['token'] ?? e['tk']}')
            .where((k) => k.split('|').last.isNotEmpty)
            .toList();
        
        if (keys.isNotEmpty) {
          client.subscribeTouchline(keys);
        }
      }
    } catch (e) {
      debugPrint('Error loading watchlist: $e');
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.length < 3) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
        return;
      }

      setState(() => _isSearching = true);
      try {
        final client = ref.read(shoonyaClientProvider);
        final response = await client.searchScrip(searchText: query);
        if (response['stat'] == 'Ok' && response['values'] != null) {
          setState(() {
            _searchResults = response['values'];
          });
        }
      } catch (e) {
        debugPrint('Search error: $e');
      } finally {
        setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _addToWatchlist(dynamic scrip) async {
    try {
      final client = ref.read(shoonyaClientProvider);
      final response = await client.addMultiScrips(
        watchlistName: 'MW1',
        scrips: [
          {'exchange': scrip['exch'], 'token': scrip['token']}
        ],
      );

      if (response['stat'] == 'Ok') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${scrip['tsym']} to watchlist'),
            backgroundColor: CredColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _searchController.clear();
        setState(() => _searchResults = []);
        _loadWatchlist();
      }
    } catch (e) {
      debugPrint('Add error: $e');
    }
  }

  Future<void> _deleteFromWatchlist(dynamic scrip) async {
    try {
      final client = ref.read(shoonyaClientProvider);
      final response = await client.deleteMultiScrips(
        watchlistName: 'MW1',
        scrips: [
          {'exchange': scrip['exch'], 'token': (scrip['token'] ?? scrip['tk']).toString()}
        ],
      );

      if (response['stat'] == 'Ok') {
        if (!mounted) return;
        client.unsubscribeTouchline(['${scrip['exch']}|${scrip['token'] ?? scrip['tk']}']);
        _loadWatchlist();
      }
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CredColors.background,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIndexHeader(),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: CredTextField(
                  controller: _searchController,
                  label: 'Search Scrips',
                  icon: Icons.search,
                  onChanged: _onSearchChanged,
                  suffixIcon: _isSearching 
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(strokeWidth: 2, color: CredColors.primary),
                      )
                    : null,
                ),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  'Watchlist',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _watchlist.isEmpty
                  ? Center(
                      child: Text(
                        'Your watchlist is empty',
                        style: TextStyle(color: CredColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _watchlist.length,
                      itemBuilder: (context, index) {
                        return _buildWatchlistItem(_watchlist[index]);
                      },
                    ),
              ),
            ],
          ),
          if (_searchResults.isNotEmpty) _buildSearchOverlay(),
        ],
      ),
    );
  }

  Widget _buildIndexHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(child: _buildIndexCard('NIFTY 50', _indicesData['NIFTY 50'])),
          const SizedBox(width: 12),
          Expanded(child: _buildIndexCard('SENSEX', _indicesData['SENSEX'])),
        ],
      ),
    );
  }

  Widget _buildIndexCard(String name, Map<String, dynamic>? data) {
    final lp = data?['lp'] ?? '---';
    final pc = data?['pc'] ?? '0.00';
    final change = data?['c'] ?? '0.00';
    final isNegative = pc.toString().startsWith('-');

    return CredCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              color: CredColors.textMuted,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lp,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isNegative ? Icons.remove : Icons.add,
                size: 12,
                color: isNegative ? CredColors.error : CredColors.success,
              ),
              const SizedBox(width: 2),
              Text(
                '$change ($pc%)',
                style: TextStyle(
                  color: isNegative ? CredColors.error : CredColors.success,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWatchlistItem(dynamic item) {
    final lp = item['lp'] ?? '0.00';
    final pc = item['pc'] ?? '0.00';
    final isNegative = pc.toString().startsWith('-');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: CredCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['tsym'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item['exch'] ?? '',
                    style: const TextStyle(color: CredColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lp,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: (isNegative ? CredColors.error : CredColors.success).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${!isNegative ? '+' : ''}${item['c'] ?? '0'} ($pc%)',
                    style: TextStyle(
                      color: isNegative ? CredColors.error : CredColors.success,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.1), size: 16),
              onPressed: () => _deleteFromWatchlist(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return Positioned.fill(
      top: 150,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
        ),
        child: ListView.builder(
          itemCount: _searchResults.length,
          itemBuilder: (context, index) {
            final item = _searchResults[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: CredCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: CredColors.surface,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: const VisualDensity(vertical: -4),
                  title: Text(
                    item['tsym'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    item['exch'] ?? '',
                    style: const TextStyle(color: CredColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.add_circle_outline, color: CredColors.primary, size: 20),
                  onTap: () => _addToWatchlist(item),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
