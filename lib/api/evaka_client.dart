import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../auth/secure_storage.dart';
import 'endpoints.dart';

class EvakaClient {
  EvakaClient._(this._dio, this._cookieJar);

  /// Aseta tämä lippu `Options.extra`-joukkoon kun pyyntö EI saa laukaista
  /// automaattista 401-uudelleenkirjautumista (esim. weak-login itse — muuten
  /// interseptori menisi silmukkaan).
  static const String kSkipAuthRetry = 'evakaSkipAuthRetry';

  /// Sisäinen laskuri jolla seurataan kuinka monta kertaa pyyntö on jo
  /// uusittu uudelleenkirjautumisen jälkeen.
  static const String _kAuthRetryCount = 'evakaAuthRetryCount';

  /// Kuinka monta kertaa 401-pyyntö uusitaan automaattisesti ennen kuin
  /// käyttäjälle näytetään virhe.
  static const int _kMaxAuthRetries = 3;

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

    // Single-flight: rinnakkaiset 401-pyynnöt jakavat saman login-yrityksen
    // sen sijaan että jokainen tekisi oman parallel weak-loginin (joka aiemmin
    // aiheutti race conditionin eväste-jarissa ja "Unauthorized"-rungon
    // bubble-upin).
    Future<bool>? ongoingRelogin;

    Future<bool> doRelogin() async {
      final creds = await storage.readCredentials();
      if (creds == null) return false;

      // Yritetään 2 kertaa: jos eka yritys epäonnistuu väliaikaisesta syystä
      // (esim. /auth/status palauttaa loggedIn:false vaikka weak-login antoi
      // 200, tai verkkovirhe), toinen yritys 400 ms viiveellä auttaa yleensä.
      // Tunnusten virheellisyys (403) ei tästä korjaannu — molemmat yritykset
      // epäonnistuvat samalla tavalla ja "Istunto vanhentunut" näytetään.
      const maxAttempts = 2;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
        try {
          // Tyhjennä vanha cookie ennen weak-login:ia: jos palvelin saa
          // voimassaolevan cookien, se voi palauttaa 200 ilman Set-Cookie:a
          // (sessio-rotaatio jää tekemättä). Fresh-client pakottaa palvelimen
          // luomaan uuden sessionin.
          await cookieJar.deleteAll();
          final resp = await dio.post(
            EvakaEndpoints.weakLogin,
            data: {'username': creds.email, 'password': creds.password},
            options: Options(
              contentType: Headers.jsonContentType,
              extra: {kSkipAuthRetry: true},
            ),
          );
          if (resp.statusCode != 200) continue;

          // Varmista että sessio on todella aktivoitu palvelimella. 200-status
          // yksin ei takaa että muut endpointit hyväksyvät uuden sessionin —
          // /auth/status kertoo varmasti. Tämä pyyntö ei saa laukaista
          // auto-relogia (oltaisiin jo sen sisällä).
          final statusResp = await dio.get(
            EvakaEndpoints.authStatus,
            options: Options(extra: {kSkipAuthRetry: true}),
          );
          final data = statusResp.data;
          if (data is Map && data['loggedIn'] == true) {
            return true;
          }
          // 200 mutta loggedIn != true → palvelimen sessio ei kelvannut.
          // Jätä silmukan jatkaa uuteen yritykseen.
        } catch (_) {
          // Verkkovirhe / parse-virhe — yritä uudestaan jos yrityksiä jäljellä
        }
      }
      return false;
    }

    Future<bool> ensureFreshSession() {
      final ongoing = ongoingRelogin;
      if (ongoing != null) return ongoing;
      final fresh = doRelogin();
      ongoingRelogin = fresh;
      fresh.whenComplete(() {
        if (identical(ongoingRelogin, fresh)) ongoingRelogin = null;
      });
      return fresh;
    }

    DioException sessionExpired(Response response) => DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: 'Istunto vanhentunut',
        );

    dio.interceptors.add(InterceptorsWrapper(
      onResponse: (response, handler) async {
        final opts = response.requestOptions;

        // Ohita login-kutsu itse (estää ikuisen silmukan)
        if (opts.extra[kSkipAuthRetry] == true) {
          handler.next(response);
          return;
        }

        if (response.statusCode != 401) {
          handler.next(response);
          return;
        }

        // Yritetään max _kMaxAuthRetries kertaa, sitten siisti virhe
        // (ei päästetä raakaa "Unauthorized"-runkoa JSON-parseriin)
        final retryCount = (opts.extra[_kAuthRetryCount] as int?) ?? 0;
        if (retryCount >= _kMaxAuthRetries) {
          handler.reject(sessionExpired(response), true);
          return;
        }

        final ok = await ensureFreshSession();
        if (!ok) {
          handler.reject(sessionExpired(response), true);
          return;
        }

        try {
          opts.extra[_kAuthRetryCount] = retryCount + 1;
          // Pieni viive ennen retryä — antaa palvelimen istunto-tilan
          // stabiloitua weak-loginin jälkeen ja välttää hetkelliset 401:t.
          await Future<void>.delayed(const Duration(milliseconds: 500));
          // Rakenna pyyntö tyhjästä BaseOptionsin pohjalta sen sijaan että
          // uudelleenkäytetään alkuperäistä [opts]-objektia. Käytännössä sama
          // mitä käyttäjän "Yritä uudelleen" -nappi tekee uudella dio.get/
          // post-kutsulla. Vältetään tilanne jossa ensimmäisen lähetyksen
          // jäljiltä jäänyt Cookie-header tms. säilyy `opts.headers`:issa
          // eikä CookieManager.onRequest jostain syystä kirjoita sitä päälle.
          final retry = await dio.requestUri(
            opts.uri,
            data: opts.data,
            options: Options(
              method: opts.method,
              contentType: opts.contentType,
              responseType: opts.responseType,
              // Säilytä [extra] jotta retry-counter ja kSkipAuthRetry-liput
              // siirtyvät uudelle pyynnölle.
              extra: opts.extra,
            ),
          );
          handler.resolve(retry);
        } on DioException catch (e) {
          handler.reject(e, true);
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
