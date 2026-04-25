import 'reservations.dart';

class CalendarEvent {
  CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.period,
    required this.eventType,
    required this.attendingChildren,
    required this.bookedTimes,
  });

  final String id;
  final String title;
  final String description;
  final DateRange period;

  /// "DAYCARE_EVENT" | "DISCUSSION_SURVEY" | muut
  final String eventType;

  /// childId → yksi tai useampi läsnäolokirjaus (useimmin yksi)
  final Map<String, List<AttendingChild>> attendingChildren;

  /// childId → varatut ajat (DISCUSSION_SURVEY: ajat joissa childId != null).
  /// Tyhjä jos kyseessä DAYCARE_EVENT tai ei varattuja.
  final Map<String, List<DiscussionTime>> bookedTimes;

  bool get hasBookedTime => bookedTimes.values.any((l) => l.isNotEmpty);

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final attending = <String, List<AttendingChild>>{};
    final raw = json['attendingChildren'] as Map<String, dynamic>? ?? const {};
    raw.forEach((childId, list) {
      attending[childId] = (list as List)
          .cast<Map<String, dynamic>>()
          .map(AttendingChild.fromJson)
          .toList();
    });

    final booked = <String, List<DiscussionTime>>{};
    final timesRaw =
        json['timesByChild'] as Map<String, dynamic>? ?? const {};
    timesRaw.forEach((parentChildId, list) {
      for (final slot in (list as List).cast<Map<String, dynamic>>()) {
        // Vain ne slot:it jotka ovat VARATTUJA (childId != null)
        final assignedTo = slot['childId'] as String?;
        if (assignedTo == null) continue;
        booked.putIfAbsent(assignedTo, () => []);
        booked[assignedTo]!.add(DiscussionTime.fromJson(slot));
      }
    });

    return CalendarEvent(
      id: json['id'] as String,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      period: DateRange.fromJson(json['period'] as Map<String, dynamic>),
      eventType: (json['eventType'] ?? '') as String,
      attendingChildren: attending,
      bookedTimes: booked,
    );
  }
}

class DiscussionTime {
  DiscussionTime({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final DateTime date;
  final String startTime;
  final String endTime;

  String get startHHmm =>
      startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
  String get endHHmm =>
      endTime.length >= 5 ? endTime.substring(0, 5) : endTime;

  factory DiscussionTime.fromJson(Map<String, dynamic> json) {
    return DiscussionTime(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: (json['startTime'] ?? '') as String,
      endTime: (json['endTime'] ?? '') as String,
    );
  }
}

class AttendingChild {
  AttendingChild({
    required this.type,
    required this.groupName,
    required this.unitName,
    required this.periods,
  });

  /// "GROUP" | "INDIVIDUAL"
  final String type;
  final String? groupName;
  final String? unitName;
  final List<DateRange> periods;

  factory AttendingChild.fromJson(Map<String, dynamic> json) {
    return AttendingChild(
      type: (json['type'] ?? '') as String,
      groupName: json['groupName'] as String?,
      unitName: json['unitName'] as String?,
      periods: (json['periods'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(DateRange.fromJson)
          .toList(),
    );
  }
}
