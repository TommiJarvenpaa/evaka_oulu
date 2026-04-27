import 'endpoints.dart';
import 'evaka_client.dart';
import 'json_utils.dart';
import 'models/questionnaire.dart';

class QuestionnaireApi {
  QuestionnaireApi(this._client);

  final EvakaClient _client;

  Future<List<HolidayQuestionnaire>> getActiveQuestionnaires() async {
    final resp =
        await _client.dio.get(EvakaEndpoints.holidayPeriodQuestionnaire);
    return asList(resp.data)
        .cast<Map<String, dynamic>>()
        .map(HolidayQuestionnaire.fromJson)
        .toList();
  }

  /// Tallenna vastaukset OPEN_RANGES-tyyppiseen kyselyyn.
  /// [answers]: childId → lista päivämääräjaksoista
  Future<void> answerOpenRange({
    required String questionnaireId,
    required Map<String, List<({DateTime start, DateTime end})>> answers,
  }) async {
    final openRanges = <String, dynamic>{};
    answers.forEach((childId, ranges) {
      openRanges[childId] = ranges
          .map((r) => {'start': _fmt(r.start), 'end': _fmt(r.end)})
          .toList();
    });

    await _client.dio.post(
      EvakaEndpoints.questionnaireOpenRange(questionnaireId),
      data: {'openRanges': openRanges},
    );
  }
}

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, "0")}-'
    '${d.month.toString().padLeft(2, "0")}-'
    '${d.day.toString().padLeft(2, "0")}';
