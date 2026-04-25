import 'endpoints.dart';
import 'evaka_client.dart';
import 'json_utils.dart';
import 'models/reservations.dart';

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, "0")}-'
    '${d.month.toString().padLeft(2, "0")}-'
    '${d.day.toString().padLeft(2, "0")}';

class ReservationsApi {
  ReservationsApi(this._client);

  final EvakaClient _client;

  Future<ReservationsResponse> getReservations({
    required DateTime from,
    required DateTime to,
  }) async {
    final resp = await _client.dio.get(
      EvakaEndpoints.reservations,
      queryParameters: {'from': _fmt(from), 'to': _fmt(to)},
    );
    return ReservationsResponse.fromJson(asMap(resp.data));
  }

  /// Aseta varaus (tai poista tyypillä NOTHING) listalle lapsi/päivä-yhdistelmiä.
  Future<void> postReservations(List<ReservationInput> inputs) async {
    await _client.dio.post(
      EvakaEndpoints.reservations,
      data: inputs.map((i) => i.toJson()).toList(),
    );
  }

  /// Merkitse poissaolo. Selain tekee ensin postReservations tyypillä NOTHING
  /// niille lapsille/päiville joilla on olemassa varaus — hoida se kutsujalla.
  Future<void> postAbsence({
    required List<String> childIds,
    required DateTime start,
    required DateTime end,
    required String absenceType,
  }) async {
    await _client.dio.post(
      EvakaEndpoints.absences,
      data: {
        'childIds': childIds,
        'dateRange': {'start': _fmt(start), 'end': _fmt(end)},
        'absenceType': absenceType,
      },
    );
  }
}

class ReservationInput {
  ReservationInput.times({
    required this.childId,
    required this.date,
    required this.start,
    required this.end,
  }) : type = 'RESERVATIONS';

  ReservationInput.clear({required this.childId, required this.date})
      : type = 'NOTHING',
        start = null,
        end = null;

  final String type;
  final String childId;
  final DateTime date;
  final String? start;
  final String? end;

  Map<String, dynamic> toJson() {
    if (type == 'NOTHING') {
      return {'type': 'NOTHING', 'childId': childId, 'date': _fmt(date)};
    }
    return {
      'type': type,
      'childId': childId,
      'date': _fmt(date),
      'reservation': {'start': '$start:00', 'end': '$end:00'},
      'secondReservation': null,
    };
  }
}
