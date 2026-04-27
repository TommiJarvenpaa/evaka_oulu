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
    required this.slotsByChild,
  });

  final String id;
  final String title;
  final String description;
  final DateRange period;

  /// "DAYCARE_EVENT" | "DISCUSSION_SURVEY" | muut
  final String eventType;

  /// childId → läsnäolokirjaukset (DAYCARE_EVENT)
  final Map<String, List<AttendingChild>> attendingChildren;

  /// childId → varatut ajat (DISCUSSION_SURVEY, childId != null sloteissa)
  final Map<String, List<DiscussionTime>> bookedTimes;

  /// DISCUSSION_SURVEY: eligibleChildId → kaikki slotit (vapaat + varatut)
  final Map<String, List<DiscussionTime>> slotsByChild;

  bool get hasBookedTime => bookedTimes.values.any((l) => l.isNotEmpty);
  bool get isDiscussion => eventType == 'DISCUSSION_SURVEY';

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final attending = <String, List<AttendingChild>>{};
    final rawAttending =
        json['attendingChildren'] as Map<String, dynamic>? ?? {};
    rawAttending.forEach((childId, list) {
      attending[childId] = (list as List)
          .cast<Map<String, dynamic>>()
          .map(AttendingChild.fromJson)
          .toList();
    });

    final booked = <String, List<DiscussionTime>>{};
    final slots = <String, List<DiscussionTime>>{};
    final timesRaw =
        json['timesByChild'] as Map<String, dynamic>? ?? {};
    timesRaw.forEach((eligibleChildId, list) {
      final allSlots = (list as List)
          .cast<Map<String, dynamic>>()
          .map(DiscussionTime.fromJson)
          .toList();
      slots[eligibleChildId] = allSlots;
      final bookedForChild = allSlots
          .where((s) => s.childId == eligibleChildId)
          .toList();
      if (bookedForChild.isNotEmpty) {
        booked[eligibleChildId] = bookedForChild;
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
      slotsByChild: slots,
    );
  }
}

class DiscussionTime {
  DiscussionTime({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.childId,
    required this.isEditable,
  });

  final String id;
  final DateTime date;
  final String startTime;
  final String endTime;

  /// null = vapaa, non-null = tämä lapsi on varannut
  final String? childId;
  final bool isEditable;

  bool get isAvailable => childId == null;

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
      childId: json['childId'] as String?,
      isEditable: (json['isEditable'] ?? true) as bool,
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
