import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../utils/cred_theme.dart';
import '../widgets/cred_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _niftyController;
  late TextEditingController _sensexController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _niftyController = TextEditingController(text: settings.niftyLots.toString());
    _sensexController = TextEditingController(text: settings.sensexLots.toString());
  }

  @override
  void dispose() {
    _niftyController.dispose();
    _sensexController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final niftyLots = int.tryParse(_niftyController.text) ?? 1;
    final sensexLots = int.tryParse(_sensexController.text) ?? 1;

    await ref.read(settingsProvider.notifier).updateNiftyLots(niftyLots);
    await ref.read(settingsProvider.notifier).updateSensexLots(sensexLots);

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Protocol updated successfully'),
          backgroundColor: CredColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CredColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuration',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage your trading multipliers',
              style: TextStyle(color: CredColors.textMuted, fontSize: 16),
            ),
            const SizedBox(height: 40),
            _buildSectionHeader('QUANTITY PROTOCOL'),
            const SizedBox(height: 20),
            CredCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildLotInput(
                    label: 'NIFTY LOTS',
                    controller: _niftyController,
                    icon: Icons.trending_up,
                    subtitle: 'Base: 50 units per lot',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Divider(color: Colors.white10),
                  ),
                  _buildLotInput(
                    label: 'SENSEX LOTS',
                    controller: _sensexController,
                    icon: Icons.bolt,
                    subtitle: 'Base: 10 units per lot',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            CredButton(
              onPressed: _saveSettings,
              child: const Text('SAVE PROTOCOL'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: CredColors.primary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
      ),
    );
  }

  Widget _buildLotInput({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: CredColors.textMuted, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: CredTextField(
                controller: controller,
                label: 'Number of Lots',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: CredColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: CredShadows.neumorphicPressed,
              ),
              child: Text(
                'LOTS',
                style: TextStyle(
                  color: CredColors.primary.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(color: CredColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}
