import 'package:dio/dio.dart';

import '../api/endpoints.dart';
import '../api/evaka_client.dart';
import 'secure_storage.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthService {
  AuthService(this._client, this._storage);

  final EvakaClient _client;
  final SecureStorage _storage;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  /// Yrittää palauttaa session tallennetuilla tunnuksilla.
  Future<AuthStatus> restore() async {
    final creds = await _storage.readCredentials();
    if (creds == null) {
      _status = AuthStatus.unauthenticated;
      return _status;
    }
    try {
      await _weakLogin(creds.email, creds.password);
      _status = AuthStatus.authenticated;
    } on DioException {
      _status = AuthStatus.unauthenticated;
    }
    return _status;
  }

  Future<void> login(String email, String password) async {
    await _weakLogin(email, password);
    await _storage.saveCredentials(email, password);
    _status = AuthStatus.authenticated;
  }

  Future<void> logout() async {
    try {
      await _client.dio.post(EvakaEndpoints.logout);
    } on DioException {
      // Hyväksy verkkovirhe uloskirjautumisessa — sessio tyhjennetään silti
    }
    await _client.clearSession();
    await _storage.clear();
    _status = AuthStatus.unauthenticated;
  }

  Future<void> _weakLogin(String email, String password) async {
    final resp = await _client.dio.post(
      EvakaEndpoints.weakLogin,
      data: {
        'username': email,
        'password': password,
      },
      options: Options(
        contentType: Headers.jsonContentType,
        // Älä laukaise auto-relogia kirjautumiskutsusta itsestään —
        // muuten väärät tunnukset käynnistäisivät rekursiivisen yrityksen.
        extra: {EvakaClient.kSkipAuthRetry: true},
      ),
    );

    if (resp.statusCode != 200) {
      throw DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        message: 'Kirjautuminen epäonnistui (${resp.statusCode})',
      );
    }
  }
}
