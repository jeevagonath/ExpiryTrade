import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import 'strategy_screen.dart';
import 'positions_screen.dart';
import 'order_book_screen.dart';
import 'trade_book_screen.dart';
import 'settings_screen.dart';
import '../providers/shoonya_provider.dart';
import '../utils/cred_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    StrategyScreen(),
    PositionsScreen(),
    OrderBookScreen(),
    TradeBookScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final totalPnL = ref.watch(totalPnLProvider);
    final bool isProfit = totalPnL >= 0;

    return Scaffold(
      backgroundColor: CredColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: CredColors.background,
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leadingWidth: 70,
            leading: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CredColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: CredShadows.neumorphicShadow,
                  ),
                  child: Image.asset(
                    'assets/images/logo.png',
                    height: 20,
                    width: 20,
                  ),
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'HERO OR ZERO',
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.w900, 
                    color: Colors.white,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isProfit ? '+' : ''}₹${totalPnL.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isProfit ? CredColors.success : CredColors.error,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                padding: const EdgeInsets.only(right: 20),
                icon: const Icon(Icons.power_settings_new, color: CredColors.textMuted, size: 22),
                onPressed: () => _showLogoutDialog(),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: CredColors.background,
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: CredColors.primary,
          unselectedItemColor: CredColors.textMuted,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.grid_view_rounded, size: 20),
              ),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.bolt_rounded, size: 20),
              ),
              label: 'Strategy',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.pie_chart_rounded, size: 20),
              ),
              label: 'Positions',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.layers_rounded, size: 20),
              ),
              label: 'Order Book',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.history_rounded, size: 20),
              ),
              label: 'Trade Book',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(Icons.settings_rounded, size: 20),
              ),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CredColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('DISCONNECT?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        content: const Text('Are you sure you want to exit the protocol?', style: TextStyle(color: CredColors.textMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('STAY', style: TextStyle(color: CredColors.textMuted, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('DISCONNECT', style: TextStyle(color: CredColors.error, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}
