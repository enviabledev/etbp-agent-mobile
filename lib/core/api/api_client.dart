import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:etbp_agent_mobile/config/constants.dart';
import 'package:etbp_agent_mobile/core/auth/token_storage.dart';

class ApiClient {
  late final Dio _dio;
  final TokenStorage _tokenStorage;

  ApiClient({required TokenStorage tokenStorage}) : _tokenStorage = tokenStorage {
    _dio = Dio(BaseOptions(baseUrl: '${AppConstants.apiBaseUrl}${AppConstants.apiPrefix}', connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 30), headers: {'Content-Type': 'application/json'}));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async { final t = await _tokenStorage.getAccessToken(); if (t != null) options.headers['Authorization'] = 'Bearer $t'; return handler.next(options); },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          try { final rt = await _tokenStorage.getRefreshToken(); if (rt == null) return handler.next(error);
            final res = await Dio().post('${AppConstants.apiBaseUrl}${AppConstants.apiPrefix}/auth/refresh', data: {'refresh_token': rt});
            await _tokenStorage.saveTokens(res.data['access_token'], res.data['refresh_token']);
            error.requestOptions.headers['Authorization'] = 'Bearer ${res.data['access_token']}';
            return handler.resolve(await _dio.fetch(error.requestOptions));
          } catch (_) { await _tokenStorage.clearTokens(); }
        }
        return handler.next(error);
      },
    ));
    if (kDebugMode) _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) => _dio.get(path, queryParameters: queryParameters);
  Future<Response> post(String path, {dynamic data}) => _dio.post(path, data: data);
}
