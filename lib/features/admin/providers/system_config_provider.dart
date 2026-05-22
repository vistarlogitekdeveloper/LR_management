import 'package:flutter_riverpod/flutter_riverpod.dart';

class SystemConfig {
  final String lrPrefix;
  final String lrFormat;
  final int nextLrNumber;
  final bool dailyBackup;
  final String backupTime;
  final bool auditTrail;
  final String passwordPolicy;

  const SystemConfig({
    this.lrPrefix = 'VLL',
    this.lrFormat = 'VLL/YY/MM/00001',
    this.nextLrNumber = 57,
    this.dailyBackup = true,
    this.backupTime = '02:00',
    this.auditTrail = true,
    this.passwordPolicy = 'Min 8 chars, 1 number',
  });

  SystemConfig copyWith({
    String? lrPrefix,
    String? lrFormat,
    int? nextLrNumber,
    bool? dailyBackup,
    String? backupTime,
    bool? auditTrail,
    String? passwordPolicy,
  }) {
    return SystemConfig(
      lrPrefix: lrPrefix ?? this.lrPrefix,
      lrFormat: lrFormat ?? this.lrFormat,
      nextLrNumber: nextLrNumber ?? this.nextLrNumber,
      dailyBackup: dailyBackup ?? this.dailyBackup,
      backupTime: backupTime ?? this.backupTime,
      auditTrail: auditTrail ?? this.auditTrail,
      passwordPolicy: passwordPolicy ?? this.passwordPolicy,
    );
  }
}

class SystemConfigNotifier extends StateNotifier<SystemConfig> {
  SystemConfigNotifier() : super(const SystemConfig());

  void update(SystemConfig cfg) => state = cfg;
}

final systemConfigProvider =
    StateNotifierProvider<SystemConfigNotifier, SystemConfig>(
        (ref) => SystemConfigNotifier());
