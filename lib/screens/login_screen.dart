import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/shoonya_provider.dart';
import '../utils/cred_theme.dart';
import '../widgets/cred_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _totpSecretController = TextEditingController();

  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: CredColors.background,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo / Icon
                  Hero(
                    tag: 'app_logo',
                    child: Container(
                      width: 140,
                      height: 140,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: CredColors.surface,
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: CredShadows.neumorphicRaised,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const Text(
                    'Hero or Zero',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Precision Trading Redefined',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CredColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 64),

                  // Login Form
                  CredTextField(
                    controller: _userIdController,
                    label: 'User ID',
                    icon: Icons.person_outline,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                  ),
                  const SizedBox(height: 20),
                  CredTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: CredColors.textMuted,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 20),
                  CredTextField(
                    controller: _totpSecretController,
                    label: 'TOTP (6-digit) or Secret',
                    icon: Icons.security_outlined,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 40),

                  if (authState.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: CredColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          authState.error!,
                          style: const TextStyle(color: CredColors.error, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  CredButton(
                    isLoading: authState.isLoading,
                    onPressed: () {
                      ref.read(authProvider.notifier).login(
                            userId: _userIdController.text,
                            password: _passwordController.text,
                            totpSecret: _totpSecretController.text,
                          );
                    },
                    child: const Text('Enter Fortress'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
