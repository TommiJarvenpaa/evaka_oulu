import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/reservations.dart';
import '../api/reservations_api.dart';
import '../state/app_state.dart';
import '../widgets/child_image.dart';
import '../widgets/day_card.dart';
import 'attendance_history_screen.dart';
import 'bulk_reservation_screen.dart';

class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reservationsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('Varausten haku epäonnistui:\n$e',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(reservationsProvider),
                child: const Text('Yritä uudelleen'),
              ),
            ],
          ),
        ),
      ),
      data: (data) => Scaffold(
        body: _ReservationsList(data: data),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.event_repeat),
          label: const Text('Massailmoitus'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BulkReservationScreen(data: data),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReservationsList extends ConsumerWidget {
  const _ReservationsList({required this.data});

  final ReservationsResponse data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenById = {for (final c in data.children) c.id: c};

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(reservationsProvider);
        await ref.read(reservationsProvider.future);
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: data.days.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return const _HistoryButton();
          }
          final day = data.days[i - 1];
          return _DayCard(
            day: day,
            childrenById: childrenById,
            reservableRange: data.reservableRange,
          );
        },
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListTile(
        leading: Icon(Icons.history, color: theme.colorScheme.primary),
        title: const Text('Hoitoaikahistoria'),
        subtitle: const Text('Aiempien päivien toteutuneet hoitoajat'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AttendanceHistoryScreen(),
            ),
          );
        },
      ),
    );
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.day,
    required this.childrenById,
    required this.reservableRange,
  });

  final ReservationDay day;
  final Map<String, ReservationChild> childrenById;
  final DateRange? reservableRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekday = DateFormat('EEEE', 'fi_FI').format(day.date);
    final dateStr = DateFormat('d.M.yyyy').format(day.date);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _isSameDay(day.date, now);
    // Menneitä päiviä ei saa muokata: toteutuneet hoitoajat on jo kirjattu.
    // reservationsProvider hakee from=today, joten näitä ei pitäisi koskaan
    // päätyä tähän — suoja on belt-and-suspenders mahdollisten cache- tai
    // konfiguraatiomuutosten varalta.
    final isPast = day.date.isBefore(today);
    final isWeekend = day.date.weekday == DateTime.saturday ||
        day.date.weekday == DateTime.sunday;
    final notReservable = day.holiday || day.children.isEmpty;
    final hasLockedTimes = !notReservable &&
        (day.children.any((c) => c.reservationsClosed) ||
            (reservableRange != null &&
                (day.date.isBefore(reservableRange!.start) ||
                    day.date.isAfter(reservableRange!.end))));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: notReservable ? theme.colorScheme.surfaceContainerLow : null,
      child: InkWell(
        onTap: (notReservable || isPast)
            ? null
            : () => _openEditSheet(context, ref, day, childrenById, reservableRange),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${_capitalize(weekday)} $dateStr',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isToday
                          ? theme.colorScheme.primary
                          : (notReservable
                              ? theme.colorScheme.onSurfaceVariant
                              : null),
                    ),
                  ),
                  if (day.holiday)
                    const Chip(
                      label: Text('Pyhäpäivä'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (isWeekend && !day.holiday)
                    const Chip(
                      label: Text('Viikonloppu'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (isToday)
                    Text('tänään',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        )),
                  if (hasLockedTimes)
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              if (day.children.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final childDay in day.children)
                  _ChildDayRow(
                    child: childrenById[childDay.childId],
                    childDay: childDay,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildDayRow extends StatelessWidget {
  const _ChildDayRow({required this.child, required this.childDay});

  final ReservationChild? child;
  final ReservationChildDay childDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = child?.displayName ?? '(lapsi)';

    final (label, color, icon) = _status(childDay, theme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ChildImage(
                imageId: child?.imageId,
                fallbackLetter: name.isNotEmpty ? name[0] : '?',
                radius: 14,
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name, style: theme.textTheme.bodyMedium),
              ),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ],
          ),
          if (childDay.hasAttendance)
            Padding(
              // Sisennys lapsen kuvan + ikonin perään, jotta toteutunut aika
              // näyttää linjautuvan varatun ajan kanssa
              padding: const EdgeInsets.only(left: 50, top: 2),
              child: Text(
                _attendanceLabel(childDay.attendances),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  (String label, Color? color, IconData icon) _status(
      ReservationChildDay d, ThemeData theme) {
    if (d.absence != null) {
      return (
        _absenceLabel(d.absence!.type),
        Colors.orange.shade700,
        Icons.event_busy,
      );
    }
    if (d.reservations.isNotEmpty) {
      final r = d.reservations.first;
      if (r.type == 'TIMES' && r.start != null && r.end != null) {
        return (
          '${_trimSeconds(r.start!)}–${_trimSeconds(r.end!)}',
          theme.colorScheme.primary,
          Icons.event_available,
        );
      }
      return ('Varattu', theme.colorScheme.primary, Icons.event_available);
    }
    if (d.scheduleType == 'FIXED_SCHEDULE') {
      return ('Kiinteä aikataulu', Colors.grey.shade600, Icons.schedule);
    }
    if (d.scheduleType == 'TERM_BREAK') {
      return ('Loma-aika', Colors.grey.shade600, Icons.beach_access);
    }
    return ('Ei merkintää', Colors.grey.shade600, Icons.help_outline);
  }
}

Future<void> _openEditSheet(
  BuildContext context,
  WidgetRef ref,
  ReservationDay day,
  Map<String, ReservationChild> childrenById,
  DateRange? reservableRange,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _EditSheet(
      day: day,
      childrenById: childrenById,
      reservableRange: reservableRange,
    ),
  );
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({
    required this.day,
    required this.childrenById,
    required this.reservableRange,
  });

  final ReservationDay day;
  final Map<String, ReservationChild> childrenById;
  final DateRange? reservableRange;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late Map<String, DaySpec> _childSpecs;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _childSpecs = {};
    for (final cd in widget.day.children) {
      _childSpecs[cd.childId] = _specFromExisting(cd);
    }
  }

  bool _timesEditable(ReservationChildDay cd) {
    if (cd.reservationsClosed) return false;
    final range = widget.reservableRange;
    if (range != null) {
      final d = widget.day.date;
      if (d.isBefore(range.start) || d.isAfter(range.end)) return false;
    }
    return true;
  }

  DaySpec _specFromExisting(ReservationChildDay cd) {
    if (cd.absence != null) {
      final kind = cd.absence!.type == 'SICKLEAVE'
          ? DayKind.sairas
          : DayKind.poissa;
      return DaySpec(kind: kind);
    }
    if (cd.reservations.isNotEmpty) {
      final r = cd.reservations.first;
      if (r.type == 'TIMES' && r.start != null && r.end != null) {
        return DaySpec(
          kind: DayKind.present,
          start: _parseHHmm(r.start!) ??
              const TimeOfDay(hour: 7, minute: 0),
          end: _parseHHmm(r.end!) ??
              const TimeOfDay(hour: 17, minute: 0),
        );
      }
    }
    return const DaySpec();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(reservationsApiProvider);
      final date = widget.day.date;

      final reservationInputs = <ReservationInput>[];
      // Lähetään yksi /absences-kutsu per (childId, tyyppi) -kombo päivälle
      final absences = <(String childId, String type)>[];

      for (final cd in widget.day.children) {
        final spec = _childSpecs[cd.childId];
        if (spec == null) continue;
        switch (spec.kind) {
          case DayKind.present:
            reservationInputs.add(ReservationInput.times(
              childId: cd.childId,
              date: date,
              start: TimePickerField.hhmm(spec.start),
              end: TimePickerField.hhmm(spec.end),
            ));
          case DayKind.poissa:
          case DayKind.sairas:
          case DayKind.tyhja:
            reservationInputs
                .add(ReservationInput.clear(childId: cd.childId, date: date));
        }
        if (spec.kind == DayKind.poissa) {
          absences.add((cd.childId, 'OTHER_ABSENCE'));
        } else if (spec.kind == DayKind.sairas) {
          absences.add((cd.childId, 'SICKLEAVE'));
        }
      }

      if (reservationInputs.isNotEmpty) {
        await api.postReservations(reservationInputs);
      }
      // Niputa poissaolot tyypin mukaan: yksi kutsu per tyyppi
      final byType = <String, List<String>>{};
      for (final (id, type) in absences) {
        byType.putIfAbsent(type, () => []).add(id);
      }
      for (final entry in byType.entries) {
        await api.postAbsence(
          childIds: entry.value,
          start: date,
          end: date,
          absenceType: entry.key,
        );
      }

      ref.invalidate(reservationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Tallennus epäonnistui: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat("EEEE d.M.yyyy", 'fi_FI').format(widget.day.date);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_capitalize(dateStr), style: theme.textTheme.titleLarge),
              if (widget.day.children.any((cd) => !_timesEditable(cd))) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline,
                          size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Varausaika suljettu – voit muokata vain poissaoloja.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final cd in widget.day.children)
                _childCard(cd),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Peruuta'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Tallenna'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _childCard(ReservationChildDay cd) {
    final child = widget.childrenById[cd.childId];
    final name = child?.displayName ?? '(lapsi)';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return DayCard(
      shortBadge: initial,
      title: name,
      subtitle: child?.upcomingPlacementUnitName,
      spec: _childSpecs[cd.childId] ?? const DaySpec(),
      onChanged: (s) => setState(() => _childSpecs[cd.childId] = s),
      timesEditable: _timesEditable(cd),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _trimSeconds(String t) {
  // "07:00" or "07:00:00" → "07:00"
  return t.length >= 5 ? t.substring(0, 5) : t;
}

/// Muotoile toteutuneet hoitoajat. Voi olla useita jaksoja (esim. hae
/// puoleenpäivään, palaa iltapäiväksi).
String _attendanceLabel(List<Attendance> attendances) {
  if (attendances.isEmpty) return '';
  final parts = attendances.map((a) {
    final start = _trimSeconds(a.startTime);
    final end = a.endTime == null ? '' : _trimSeconds(a.endTime!);
    return a.isOngoing ? 'paikalla $start –' : '$start – $end';
  }).join(', ');
  return 'Toteutunut: $parts';
}

TimeOfDay? _parseHHmm(String s) {
  // "07:00" tai "07:00:00"
  final parts = s.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String _absenceLabel(String type) {
  switch (type) {
    case 'SICKLEAVE':
      return 'Sairaus';
    case 'OTHER_ABSENCE':
      return 'Poissaolo';
    case 'PLANNED_ABSENCE':
      return 'Suunniteltu poissa';
    case 'UNKNOWN_ABSENCE':
      return 'Poissa (määrittelemätön)';
    case 'FORCE_MAJEURE':
      return 'Päiväkoti suljettu';
    case 'PARENTLEAVE':
      return 'Vanhempainvapaa';
    default:
      return type;
  }
}
