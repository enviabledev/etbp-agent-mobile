import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:etbp_agent_mobile/config/constants.dart';

class TokenStorage {
  final FlutterSecureStorage _s = const FlutterSecureStorage();
  Future<void> saveTokens(String a, String r) async { await _s.write(key: AppConstants.accessTokenKey, value: a); await _s.write(key: AppConstants.refreshTokenKey, value: r); }
  Future<String?> getAccessToken() => _s.read(key: AppConstants.accessTokenKey);
  Future<String?> getRefreshToken() => _s.read(key: AppConstants.refreshTokenKey);
  Future<void> clearTokens() async { await _s.delete(key: AppConstants.accessTokenKey); await _s.delete(key: AppConstants.refreshTokenKey); }
  Future<bool> hasTokens() async => (await getAccessToken()) != null;
}
