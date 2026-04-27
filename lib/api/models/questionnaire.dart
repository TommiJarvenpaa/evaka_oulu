class HolidayQuestionnaire {
  HolidayQuestionnaire({
    required this.questionnaire,
    required this.eligibleChildren,
    required this.previousAnswers,
  });

  final QuestionnaireDetails questionnaire;

  /// childId → lista sallituista vastausjaksoista
  final Map<String, List<QuestionnaireRange>> eligibleChildren;

  /// Aiemmin tallennetut vastaukset: childId → lista jaksoja
  final Map<String, List<QuestionnaireRange>> previousAnswers;

  bool get hasActiveQuestionnaire => questionnaire.isActive;

  factory HolidayQuestionnaire.fromJson(Map<String, dynamic> json) {
    final qJson = json['questionnaire'] as Map<String, dynamic>;
    final eligRaw = json['eligibleChildren'] as Map<String, dynamic>? ?? {};
    final prevRaw = json['previousAnswers'] as List? ?? [];

    final eligible = <String, List<QuestionnaireRange>>{};
    eligRaw.forEach((childId, ranges) {
      eligible[childId] = (ranges as List)
          .cast<Map<String, dynamic>>()
          .map(QuestionnaireRange.fromJson)
          .toList();
    });

    final previous = <String, List<QuestionnaireRange>>{};
    for (final item in prevRaw.cast<Map<String, dynamic>>()) {
      final childId = item['childId'] as String;
      final ranges = (item['openRanges'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(QuestionnaireRange.fromJson)
          .toList();
      previous[childId] = ranges;
    }

    return HolidayQuestionnaire(
      questionnaire: QuestionnaireDetails.fromJson(qJson),
      eligibleChildren: eligible,
      previousAnswers: previous,
    );
  }
}

class QuestionnaireDetails {
  QuestionnaireDetails({
    required this.id,
    required this.type,
    required this.titleFi,
    required this.descriptionFi,
    required this.descriptionLinkFi,
    required this.active,
    required this.period,
    required this.absenceType,
    required this.absenceTypeThreshold,
    required this.periods,
  });

  final String id;

  /// "OPEN_RANGES" | "FIXED_PERIOD"
  final String type;

  final String titleFi;
  final String descriptionFi;
  final String descriptionLinkFi;
  final QuestionnaireRange active;
  final QuestionnaireRange period;
  final String absenceType;
  final int absenceTypeThreshold;

  /// Sallitut vastausjaksot (OPEN_RANGES: käyttäjä valitsee näiden sisältä)
  final List<QuestionnaireRange> periods;

  bool get isActive {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return !today.isBefore(active.start) && !today.isAfter(active.end);
  }

  factory QuestionnaireDetails.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as Map<String, dynamic>? ?? {};
    final desc = json['description'] as Map<String, dynamic>? ?? {};
    final descLink = json['descriptionLink'] as Map<String, dynamic>? ?? {};

    return QuestionnaireDetails(
      id: json['id'] as String,
      type: (json['type'] ?? 'OPEN_RANGES') as String,
      titleFi: (title['fi'] ?? '') as String,
      descriptionFi: (desc['fi'] ?? '') as String,
      descriptionLinkFi: (descLink['fi'] ?? '') as String,
      active: QuestionnaireRange.fromJson(
          json['active'] as Map<String, dynamic>),
      period: QuestionnaireRange.fromJson(
          json['period'] as Map<String, dynamic>),
      absenceType: (json['absenceType'] ?? 'FREE_ABSENCE') as String,
      absenceTypeThreshold:
          ((json['absenceTypeThreshold'] ?? 0) as num).toInt(),
      periods: (json['periods'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(QuestionnaireRange.fromJson)
          .toList(),
    );
  }
}

class QuestionnaireRange {
  QuestionnaireRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Map<String, dynamic> toJson() => {
        'start': _fmt(start),
        'end': _fmt(end),
      };

  factory QuestionnaireRange.fromJson(Map<String, dynamic> json) {
    return QuestionnaireRange(
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, "0")}-'
      '${d.month.toString().padLeft(2, "0")}-'
      '${d.day.toString().padLeft(2, "0")}';
}
