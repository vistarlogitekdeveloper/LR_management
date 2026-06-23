class ApiConfig {
  ApiConfig._();

  // Override per environment:
  //   flutter run --dart-define=API_BASE_URL=http://localhost:5000/api/v1/lr-management
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://vistar-crm.onrender.com/api/v1/lr-management',
  );

  // Backend login requires {tenant_code, username, password}. The login screen
  // doesn't have a tenant picker yet — until it does, fall back to this default
  // so the existing 2-field UI keeps working:
  //   flutter run --dart-define=DEFAULT_TENANT_CODE=VLL
  static const String defaultTenantCode = String.fromEnvironment(
    'DEFAULT_TENANT_CODE',
    defaultValue: 'VISTAR',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
