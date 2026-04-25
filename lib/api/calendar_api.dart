import 'endpoints.dart';
import 'evaka_client.dart';
import 'json_utils.dart';
import 'models/calendar_event.dart';

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, "0")}-'
    '${d.month.toString().padLeft(2, "0")}-'
    '${d.day.toString().padLeft(2, "0")}';

class CalendarApi {
  CalendarApi(this._client);

  final EvakaClient _client;

  Future<List<CalendarEvent>> getEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    final resp = await _client.dio.get(
      EvakaEndpoints.calendarEvents,
      queryParameters: {'start': _fmt(start), 'end': _fmt(end)},
    );
    return asList(resp.data)
        .cast<Map<String, dynamic>>()
        .map(CalendarEvent.fromJson)
        .toList();
  }
}
