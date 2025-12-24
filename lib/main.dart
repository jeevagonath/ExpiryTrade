import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'providers/shoonya_provider.dart';
import 'utils/cred_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  runApp(
    const ProviderScope(
      child: ExpiryTradeApp(),
    ),
  );
}

class ExpiryTradeApp extends ConsumerWidget {
  const ExpiryTradeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'Hero or Zero',
      debugShowCheckedModeBanner: false,
      theme: CredTheme.darkTheme,
      home: authState.isAuthenticated ? const HomeScreen() : const LoginScreen(),
    );
  }
}
