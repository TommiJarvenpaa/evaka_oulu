import 'dart:convert';

/// Tulkitse Dion vastausdata Mapiksi. Useimmiten Dio palauttaa jo Mapin,
/// mutta joskus (esim. content-type ei matchaa) palautuu String — tällöin
/// dekoodataan käsin.
Map<String, dynamic> asMap(dynamic data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  }
  throw FormatException(
    'Odotettiin Map-vastausta, saatiin ${data.runtimeType}: '
    '${data.toString().substring(0, data.toString().length.clamp(0, 200))}',
  );
}

List<dynamic> asList(dynamic data) {
  if (data is List) return data;
  if (data is String) {
    final decoded = jsonDecode(data);
    if (decoded is List) return decoded;
  }
  throw FormatException(
    'Odotettiin List-vastausta, saatiin ${data.runtimeType}: '
    '${data.toString().substring(0, data.toString().length.clamp(0, 200))}',
  );
}
