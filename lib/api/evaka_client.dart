import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../auth/secure_storage.dart';
import 'endpoints.dart';

class EvakaClient {
  EvakaClient._(this._dio, this._cookieJar);

  final Dio _dio;
  final CookieJar _cookieJar;

  Dio get dio => _dio;
  CookieJar get cookieJar => _cookieJar;

  factory EvakaClient.create(SecureStorage storage) {
    final cookieJar = CookieJar();
    final dio = Dio(
      BaseOptions(
        baseUrl: EvakaEndpoints.baseUrl,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
        responseType: ResponseType.json,
        headers: {
          'User-Agent': 'evaka-oulu-client/0.1 (unofficial; personal use)',
          'Accept': 'application/json, text/plain, */*',
          'x-evaka-csrf': '1',
          'Origin': EvakaEndpoints.baseUrl,
        },
      ),
    )..interceptors.add(CookieManager(cookieJar));

    dio.interceptors.add(InterceptorsWrapper(
      onResponse: (response, handler) async {
        if (response.statusCode != 401 ||
            response.requestOptions.extra['_isRetry'] == true) {
          handler.next(response);
          return;
        }

        final creds = await storage.readCredentials();
        if (creds == null) {
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: 'Istunto vanhentunut',
            ),
            true,
          );
          return;
        }

        try {
          final loginResp = await dio.post(
            EvakaEndpoints.weakLogin,
            data: {'username': creds.email, 'password': creds.password},
            options: Options(
              contentType: Headers.jsonContentType,
              extra: {'_isRetry': true},
            ),
          );
          if (loginResp.statusCode != 200) throw Exception('login failed');

          final retryResp = await dio.fetch(
            response.requestOptions..extra['_isRetry'] = true,
          );
          handler.resolve(retryResp);
        } catch (_) {
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: 'Istunto vanhentunut',
            ),
            true,
          );
        }
      },
    ));

    return EvakaClient._(dio, cookieJar);
  }

  Future<void> clearSession() async {
    _cookieJar.deleteAll();
  }

  Future<bool> isAuthenticated() async {
    try {
      final resp = await _dio.get(EvakaEndpoints.authStatus);
      if (resp.statusCode != 200) return false;
      final data = resp.data;
      return data is Map && data['loggedIn'] == true;
    } on DioException {
      return false;
    }
  }
}
