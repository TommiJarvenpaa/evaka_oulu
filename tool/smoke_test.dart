// Päästä-päähän smoke-testi Oulun eVakan kansalaisrajapintaa vasten.
//
// Käyttö:
//   cd /home/tommi-jarvenpaa/Coding/Flutter/evaka_oulu
//   export EVAKA_EMAIL='oma@sahkoposti.fi'
//   export EVAKA_PASSWORD='salasana'
//   dart run tool/smoke_test.dart
//
// Tavoite: vahvistaa että auth + lapset + varaukset + viestit toimivat
// ennen Flutter-UI:n rakentamista. Ei tee mitään kirjoittavia operaatioita.

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

const String baseUrl = 'https://varhaiskasvatus.ouka.fi';

Future<void> main() async {
  final email = Platform.environment['EVAKA_EMAIL'];
  final password = Platform.environment['EVAKA_PASSWORD'];

  if (email == null || password == null) {
    stderr.writeln(
      'Aseta EVAKA_EMAIL ja EVAKA_PASSWORD ympäristömuuttujat ennen ajoa.',
    );
    exit(2);
  }

  final cookieJar = CookieJar();
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      validateStatus: (s) => s != null && s < 500,
      headers: {
        'User-Agent': 'evaka-oulu-smoke-test/0.1',
        'Accept': 'application/json, text/plain, */*',
        'x-evaka-csrf': '1',
        'Origin': baseUrl,
      },
    ),
  )..interceptors.add(CookieManager(cookieJar));

  await _step('weak-login', () async {
    final r = await dio.post(
      '/api/citizen/auth/weak-login',
      data: {'username': email, 'password': password},
      options: Options(contentType: Headers.jsonContentType),
    );
    _expect(r.statusCode == 200, 'login failed: ${r.statusCode} ${r.data}');
    final cookies = await cookieJar.loadForRequest(Uri.parse(baseUrl));
    final names = cookies.map((c) => c.name).toSet();
    _expect(
      names.any((n) => n.startsWith('evaka.eugw.session')),
      'session cookie missing (got: $names)',
    );
    stdout.writeln('  session-keksi saatu');
  });

  String? authLevel;
  await _step('auth/status', () async {
    final r = await dio.get('/api/citizen/auth/status');
    _expect(r.statusCode == 200, 'auth status ${r.statusCode}');
    final data = r.data as Map;
    _expect(data['loggedIn'] == true, 'not logged in');
    authLevel = data['authLevel'] as String?;
    final user = data['user'] as Map;
    final details = user['details'] as Map;
    stdout.writeln('  käyttäjä: ${details['firstName']} ${details['lastName']}');
    stdout.writeln('  authLevel: $authLevel');
    stdout.writeln(
      '  ominaisuudet: ${(user['accessibleFeatures'] as Map).entries.where((e) => e.value == true).map((e) => e.key).join(", ")}',
    );
  });

  List<Map> children = [];
  await _step('children', () async {
    final r = await dio.get('/api/citizen/children');
    _expect(r.statusCode == 200, 'children ${r.statusCode}');
    children = List<Map>.from(r.data as List);
    stdout.writeln('  ${children.length} lasta:');
    for (final c in children) {
      stdout.writeln(
        '    - ${c['firstName']} ${c['lastName']} (${c['group']?['name']} / ${c['unit']?['name']})',
      );
    }
  });

  final today = DateTime.now();
  final from = _fmtDate(today);
  final to = _fmtDate(today.add(const Duration(days: 60)));

  await _step('reservations $from..$to', () async {
    final r = await dio.get(
      '/api/citizen/reservations',
      queryParameters: {'from': from, 'to': to},
    );
    _expect(r.statusCode == 200, 'reservations ${r.statusCode}');
    final data = r.data as Map;
    final days = List<Map>.from(data['days'] as List);
    stdout.writeln('  ${days.length} päivää haettu');
    int withReservation = 0;
    int withAbsence = 0;
    for (final d in days) {
      for (final child in (d['children'] as List).cast<Map>()) {
        if ((child['reservations'] as List?)?.isNotEmpty ?? false) {
          withReservation++;
        }
        if (child['absence'] != null) withAbsence++;
      }
    }
    stdout.writeln(
      '  $withReservation varausta, $withAbsence poissaoloa ajanjaksolla',
    );
  });

  await _step('messages/received', () async {
    final r = await dio.get(
      '/api/citizen/messages/received',
      queryParameters: {'page': 1},
    );
    _expect(r.statusCode == 200, 'messages ${r.statusCode}');
    final data = r.data as Map;
    final threads = List<Map>.from(data['data'] as List);
    stdout.writeln('  ${threads.length} thread(ia) sivulla 1');
    for (final t in threads.take(3)) {
      final msgs = t['messages'] as List;
      final unread = msgs.where((m) => (m as Map)['readAt'] == null).length;
      stdout.writeln(
        '    - "${t['title']}" (${msgs.length} viesti(ä), $unread lukematta)',
      );
    }
  });

  await _step('messages/unread-count', () async {
    final r = await dio.get('/api/citizen/messages/unread-count');
    _expect(r.statusCode == 200, 'unread-count ${r.statusCode}');
    stdout.writeln('  lukemattomia: ${r.data}');
  });

  await _step('calendar-events $from..$to', () async {
    final r = await dio.get(
      '/api/citizen/calendar-events',
      queryParameters: {'start': from, 'end': to},
    );
    _expect(r.statusCode == 200, 'calendar ${r.statusCode}');
    final events = r.data as List;
    stdout.writeln('  ${events.length} tapahtumaa');
    for (final e in events.take(3)) {
      final m = e as Map;
      stdout.writeln('    - ${m['period']?['start']}: ${m['title']}');
    }
  });

  stdout.writeln('\n✓ kaikki askeleet läpi');
}

Future<void> _step(String name, Future<void> Function() body) async {
  stdout.writeln('\n→ $name');
  try {
    await body();
  } on DioException catch (e) {
    stderr.writeln(
      '  ✗ DioException ${e.response?.statusCode}: ${e.message}\n  body: ${e.response?.data}',
    );
    exit(1);
  } catch (e) {
    stderr.writeln('  ✗ $e');
    exit(1);
  }
}

void _expect(bool cond, String msg) {
  if (!cond) throw Exception(msg);
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, "0")}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
