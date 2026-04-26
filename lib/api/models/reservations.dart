class ReservationsResponse {
  ReservationsResponse({
    required this.children,
    required this.days,
    required this.reservableRange,
  });

  final List<ReservationChild> children;
  final List<ReservationDay> days;
  final DateRange? reservableRange;

  factory ReservationsResponse.fromJson(Map<String, dynamic> json) {
    return ReservationsResponse(
      children: (json['children'] as List)
          .cast<Map<String, dynamic>>()
          .map(ReservationChild.fromJson)
          .toList(),
      days: (json['days'] as List)
          .cast<Map<String, dynamic>>()
          .map(ReservationDay.fromJson)
          .toList(),
      reservableRange: json['reservableRange'] == null
          ? null
          : DateRange.fromJson(
              json['reservableRange'] as Map<String, dynamic>,
            ),
    );
  }
}

class ReservationChild {
  ReservationChild({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.preferredName,
    required this.imageId,
    required this.upcomingPlacementUnitName,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String preferredName;
  final String? imageId;
  final String? upcomingPlacementUnitName;

  String get displayName =>
      preferredName.isNotEmpty ? preferredName : firstName;

  factory ReservationChild.fromJson(Map<String, dynamic> json) {
    return ReservationChild(
      id: json['id'] as String,
      firstName: (json['firstName'] ?? '') as String,
      lastName: (json['lastName'] ?? '') as String,
      preferredName: (json['preferredName'] ?? '') as String,
      imageId: json['imageId'] as String?,
      upcomingPlacementUnitName:
          json['upcomingPlacementUnitName'] as String?,
    );
  }
}

class ReservationDay {
  ReservationDay({
    required this.date,
    required this.holiday,
    required this.children,
  });

  final DateTime date;
  final bool holiday;
  final List<ReservationChildDay> children;

  factory ReservationDay.fromJson(Map<String, dynamic> json) {
    return ReservationDay(
      date: DateTime.parse(json['date'] as String),
      holiday: (json['holiday'] ?? false) as bool,
      children: (json['children'] as List)
          .cast<Map<String, dynamic>>()
          .map(ReservationChildDay.fromJson)
          .toList(),
    );
  }
}

class ReservationChildDay {
  ReservationChildDay({
    required this.childId,
    required this.scheduleType,
    required this.shiftCare,
    required this.absence,
    required this.reservations,
    required this.holidayPeriodEffectType,
  });

  final String childId;

  /// "RESERVATION_REQUIRED" | "FIXED_SCHEDULE" | "TERM_BREAK"
  final String scheduleType;
  final bool shiftCare;
  final Absence? absence;
  final List<Reservation> reservations;

  /// "ReservationsClosed" | null
  final String? holidayPeriodEffectType;

  bool get hasReservation => reservations.isNotEmpty;
  bool get isAbsent => absence != null;
  bool get reservationsClosed => holidayPeriodEffectType == 'ReservationsClosed';

  factory ReservationChildDay.fromJson(Map<String, dynamic> json) {
    final holidayEffect = json['holidayPeriodEffect'] as Map<String, dynamic>?;
    return ReservationChildDay(
      childId: json['childId'] as String,
      scheduleType: (json['scheduleType'] ?? '') as String,
      shiftCare: (json['shiftCare'] ?? false) as bool,
      absence: json['absence'] == null
          ? null
          : Absence.fromJson(json['absence'] as Map<String, dynamic>),
      reservations: (json['reservations'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Reservation.fromJson)
          .toList(),
      holidayPeriodEffectType: holidayEffect?['type'] as String?,
    );
  }
}

class Reservation {
  Reservation({required this.type, required this.start, required this.end});

  /// "TIMES" | "NO_TIMES" (harvemmin)
  final String type;
  final String? start;
  final String? end;

  factory Reservation.fromJson(Map<String, dynamic> json) {
    // Todellinen rakenne: {"type": "TIMES", "range": {"start": "...", "end": "..."}}
    final range = json['range'] as Map<String, dynamic>?;
    return Reservation(
      type: (json['type'] ?? '') as String,
      start: range?['start'] as String?,
      end: range?['end'] as String?,
    );
  }
}

class Absence {
  Absence({required this.type, required this.editable});

  /// "SICKLEAVE" | "OTHER_ABSENCE" | "PLANNED_ABSENCE" | "UNKNOWN_ABSENCE"
  final String type;
  final bool editable;

  factory Absence.fromJson(Map<String, dynamic> json) {
    return Absence(
      type: (json['type'] ?? '') as String,
      editable: (json['editable'] ?? false) as bool,
    );
  }
}

class DateRange {
  DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  factory DateRange.fromJson(Map<String, dynamic> json) {
    return DateRange(
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
    );
  }
}
