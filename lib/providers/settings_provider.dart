import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SettingsState {
  final int niftyLots;
  final int sensexLots;

  SettingsState({this.niftyLots = 1, this.sensexLots = 1});

  SettingsState copyWith({int? niftyLots, int? sensexLots}) {
    return SettingsState(
      niftyLots: niftyLots ?? this.niftyLots,
      sensexLots: sensexLots ?? this.sensexLots,
    );
  }

  Map<String, dynamic> toMap() => {
    'niftyLots': niftyLots,
    'sensexLots': sensexLots,
  };

  factory SettingsState.fromMap(Map<String, dynamic> map) => SettingsState(
    niftyLots: map['niftyLots'] ?? 1,
    sensexLots: map['sensexLots'] ?? 1,
  );
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _key = 'app_settings';
  static const _storage = FlutterSecureStorage();

  @override
  SettingsState build() {
    _load();
    return SettingsState();
  }

  Future<void> _load() async {
    try {
      final data = await _storage.read(key: _key);
      if (data != null) {
        state = SettingsState.fromMap(jsonDecode(data));
      }
    } catch (e) {
      // Keep defaults
    }
  }

  Future<void> updateNiftyLots(int lots) async {
    state = state.copyWith(niftyLots: lots);
    await _save();
  }

  Future<void> updateSensexLots(int lots) async {
    state = state.copyWith(sensexLots: lots);
    await _save();
  }

  Future<void> _save() async {
    await _storage.write(key: _key, value: jsonEncode(state.toMap()));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
