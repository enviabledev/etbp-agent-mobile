import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etbp_agent_mobile/core/api/api_client.dart';
import 'package:etbp_agent_mobile/core/api/endpoints.dart';
import 'package:etbp_agent_mobile/core/auth/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((_) => TokenStorage());
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(tokenStorage: ref.read(tokenStorageProvider)));

class AgentAuth {
  final bool isAuthenticated;
  final String? agentName;
  final String? terminalName;
  AgentAuth({this.isAuthenticated = false, this.agentName, this.terminalName});
}

final authProvider = StateNotifierProvider<AuthNotifier, AgentAuth>((ref) => AuthNotifier(ref.read(apiClientProvider), ref.read(tokenStorageProvider)));

class AuthNotifier extends StateNotifier<AgentAuth> {
  final ApiClient _api;
  final TokenStorage _storage;
  AuthNotifier(this._api, this._storage) : super(AgentAuth());

  Future<bool> checkAuth() async {
    if (!await _storage.hasTokens()) return false;
    try {
      final res = await _api.get(Endpoints.agentProfile);
      state = AgentAuth(isAuthenticated: true, agentName: '${res.data['first_name']} ${res.data['last_name']}', terminalName: res.data['terminal']?['name']);
      return true;
    } catch (_) { return false; }
  }

  Future<void> login(String email, String password) async {
    final res = await _api.post(Endpoints.login, data: {'email': email, 'password': password});
    await _storage.saveTokens(res.data['access_token'], res.data['refresh_token']);
    final profile = await _api.get(Endpoints.agentProfile);
    state = AgentAuth(isAuthenticated: true, agentName: '${profile.data['first_name']} ${profile.data['last_name']}', terminalName: profile.data['terminal']?['name']);
  }

  Future<void> logout() async {
    try { final rt = await _storage.getRefreshToken(); if (rt != null) await _api.post(Endpoints.logout, data: {'refresh_token': rt}); } catch (_) {}
    await _storage.clearTokens();
    state = AgentAuth();
  }
}
