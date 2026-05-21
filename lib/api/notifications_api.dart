import 'endpoints.dart';
import 'evaka_client.dart';

/// API kotinäkymän bannereille ja kalenterin "päivittäisten palveluaikojen
/// ilmoitukset" -bannerille. Endpointtien vastaukset ovat melko vapaamuotoisia
/// (joskus listaa, joskus pelkkä luku) joten parsiminen on defensiivistä.
class NotificationsApi {
  NotificationsApi(this._client);

  final EvakaClient _client;

  /// Hakemusten tilailmoitusten lukumäärä — kasvaa kun hakemuksen tila
  /// muuttuu (esim. käsittelyssä → päätös tehty).
  ///
  /// Backend palauttaa joko pelkän luvun (esim. `3`) tai listan
  /// notifikaatio-objekteja. Käsittelemme molemmat.
  Future<int> getApplicationNotificationCount() async {
    final resp =
        await _client.dio.get(EvakaEndpoints.applicationNotifications);
    return _toCount(resp.data);
  }

  /// Vanhenevat tulotiedot — palauttaa listan päivämääriä tai vastaavaa.
  /// Banner näytetään jos lista on epätyhjä.
  Future<List<DateTime>> getExpiringIncomeDates() async {
    final resp = await _client.dio.get(EvakaEndpoints.incomeExpiring);
    final raw = resp.data;
    if (raw is List) {
      final out = <DateTime>[];
      for (final entry in raw) {
        if (entry is String) {
          final d = DateTime.tryParse(entry);
          if (d != null) out.add(d);
        } else if (entry is Map && entry['expirationDate'] is String) {
          final d = DateTime.tryParse(entry['expirationDate'] as String);
          if (d != null) out.add(d);
        } else if (entry is Map && entry['date'] is String) {
          final d = DateTime.tryParse(entry['date'] as String);
          if (d != null) out.add(d);
        }
      }
      return out;
    }
    return const [];
  }

  /// Päivittäisten palveluaikojen ilmoitukset. Jokainen sisältää id:n
  /// jonka voi kuitata `dismissDailyServiceTimeNotifications`-kutsulla.
  Future<List<DailyServiceTimeNotification>>
      getDailyServiceTimeNotifications() async {
    final resp =
        await _client.dio.get(EvakaEndpoints.dailyServiceTimeNotifications);
    final raw = resp.data;
    if (raw is! List) return const [];
    return raw
        .cast<Map<String, dynamic>>()
        .map(DailyServiceTimeNotification.fromJson)
        .toList();
  }

  Future<void> dismissDailyServiceTimeNotifications(
    List<String> notificationIds,
  ) async {
    if (notificationIds.isEmpty) return;
    // Espoon API odottaa pelkän listan UUIDeja bodyna
    await _client.dio.post(
      EvakaEndpoints.dailyServiceTimeNotificationsDismiss,
      data: notificationIds,
    );
  }

  int _toCount(dynamic data) {
    if (data is int) return data;
    if (data is num) return data.toInt();
    if (data is String) return int.tryParse(data.trim()) ?? 0;
    if (data is List) return data.length;
    if (data is Map && data['count'] is num) {
      return (data['count'] as num).toInt();
    }
    return 0;
  }
}

class DailyServiceTimeNotification {
  DailyServiceTimeNotification({
    required this.id,
    required this.dateFrom,
    required this.hasDeletedReservations,
  });

  final String id;
  final DateTime? dateFrom;
  final bool hasDeletedReservations;

  factory DailyServiceTimeNotification.fromJson(Map<String, dynamic> json) {
    final df = json['dateFrom'] as String?;
    return DailyServiceTimeNotification(
      id: json['id'] as String,
      dateFrom: df == null ? null : DateTime.tryParse(df),
      hasDeletedReservations:
          (json['hasDeletedReservations'] ?? false) as bool,
    );
  }
}
