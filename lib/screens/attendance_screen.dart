import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/reservations.dart';
import '../api/reservations_api.dart';
import '../state/app_state.dart';
import '../widgets/child_image.dart';
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
        itemCount: data.days.length,
        itemBuilder: (context, i) {
          final day = data.days[i];
          return _DayCard(day: day, childrenById: childrenById);
        },
      ),
    );
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({required this.day, required this.childrenById});

  final ReservationDay day;
  final Map<String, ReservationChild> childrenById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekday = DateFormat('EEEE', 'fi_FI').format(day.date);
    final dateStr = DateFormat('d.M.yyyy').format(day.date);
    final isToday = _isSameDay(day.date, DateTime.now());
    final isWeekend = day.date.weekday == DateTime.saturday ||
        day.date.weekday == DateTime.sunday;
    final notReservable = day.holiday || day.children.isEmpty;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: notReservable ? theme.colorScheme.surfaceContainerLow : null,
      child: InkWell(
        onTap: notReservable
            ? null
            : () => _openEditSheet(context, ref, day, childrenById),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  if (day.holiday) ...[
                    const SizedBox(width: 8),
                    const Chip(
                      label: Text('Pyhäpäivä'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                  if (isWeekend && !day.holiday) ...[
                    const SizedBox(width: 8),
                    const Chip(
                      label: Text('Viikonloppu'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Text('tänään',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        )),
                  ],
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
      child: Row(
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
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _EditSheet(day: day, childrenById: childrenById),
  );
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.day, required this.childrenById});

  final ReservationDay day;
  final Map<String, ReservationChild> childrenById;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

enum _Mode { reservation, absence, clear }

class _EditSheetState extends ConsumerState<_EditSheet> {
  _Mode _mode = _Mode.reservation;
  TimeOfDay _start = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);
  bool _sameTimeForAll = true;
  final Map<String, TimeOfDay> _childStarts = {};
  final Map<String, TimeOfDay> _childEnds = {};
  String _absenceType = 'OTHER_ABSENCE';
  late Set<String> _selectedChildIds;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedChildIds =
        widget.day.children.map((c) => c.childId).toSet();
    // Esitäytä per-lapsi ajat olemassa olevista varauksista tai oletuksista
    for (final cd in widget.day.children) {
      final r = cd.reservations.isNotEmpty ? cd.reservations.first : null;
      if (r?.type == 'TIMES' && r?.start != null && r?.end != null) {
        _childStarts[cd.childId] = _parseHHmm(r!.start!) ?? _start;
        _childEnds[cd.childId] = _parseHHmm(r.end!) ?? _end;
      } else {
        _childStarts[cd.childId] = _start;
        _childEnds[cd.childId] = _end;
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedChildIds.isEmpty) {
      setState(() => _error = 'Valitse vähintään yksi lapsi');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(reservationsApiProvider);
      final date = widget.day.date;
      final ids = _selectedChildIds.toList();

      switch (_mode) {
        case _Mode.reservation:
          await api.postReservations([
            for (final id in ids)
              ReservationInput.times(
                childId: id,
                date: date,
                start: _sameTimeForAll
                    ? _hhmm(_start)
                    : _hhmm(_childStarts[id] ?? _start),
                end: _sameTimeForAll
                    ? _hhmm(_end)
                    : _hhmm(_childEnds[id] ?? _end),
              ),
          ]);
        case _Mode.clear:
          await api.postReservations([
            for (final id in ids)
              ReservationInput.clear(childId: id, date: date),
          ]);
        case _Mode.absence:
          // Tyhjennä mahdolliset varaukset ensin, sitten merkkaa poissaolo
          await api.postReservations([
            for (final id in ids)
              ReservationInput.clear(childId: id, date: date),
          ]);
          await api.postAbsence(
            childIds: ids,
            start: date,
            end: date,
            absenceType: _absenceType,
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
    final dateStr = DateFormat(
      "EEEE d.M.yyyy",
      'fi_FI',
    ).format(widget.day.date);
    final children = widget.day.children
        .map((cd) => widget.childrenById[cd.childId])
        .whereType<ReservationChild>()
        .toList();

    return SafeArea(
      top: false,
      child: Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_capitalize(dateStr),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(
                value: _Mode.reservation,
                icon: Icon(Icons.event_available),
                label: Text('Varaus'),
              ),
              ButtonSegment(
                value: _Mode.absence,
                icon: Icon(Icons.event_busy),
                label: Text('Poissa'),
              ),
              ButtonSegment(
                value: _Mode.clear,
                icon: Icon(Icons.delete_outline),
                label: Text('Tyhjä'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          Text('Lapset', style: Theme.of(context).textTheme.labelLarge),
          for (final c in children)
            CheckboxListTile(
              title: Text(c.displayName),
              subtitle: c.upcomingPlacementUnitName != null
                  ? Text(c.upcomingPlacementUnitName!,
                      style: Theme.of(context).textTheme.bodySmall)
                  : null,
              value: _selectedChildIds.contains(c.id),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selectedChildIds.add(c.id);
                } else {
                  _selectedChildIds.remove(c.id);
                }
              }),
            ),
          const SizedBox(height: 8),
          if (_mode == _Mode.reservation) _reservationTimeSection(children),
          if (_mode == _Mode.absence) _absenceTypeRow(),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Tallenna'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _reservationTimeSection(List<ReservationChild> children) {
    final showPerChildToggle = _selectedChildIds.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPerChildToggle)
          SwitchListTile(
            title: const Text('Sama aika kaikille lapsille'),
            value: _sameTimeForAll,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _sameTimeForAll = v),
          ),
        if (_sameTimeForAll || _selectedChildIds.length <= 1)
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'Alkaa',
                  value: _start,
                  onChanged: (v) => setState(() => _start = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: 'Päättyy',
                  value: _end,
                  onChanged: (v) => setState(() => _end = v),
                ),
              ),
            ],
          )
        else
          ...children.where((c) => _selectedChildIds.contains(c.id)).map(
                (c) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.displayName,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: _TimeField(
                              label: 'Alkaa',
                              value: _childStarts[c.id] ?? _start,
                              onChanged: (v) => setState(
                                () => _childStarts[c.id] = v,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeField(
                              label: 'Päättyy',
                              value: _childEnds[c.id] ?? _end,
                              onChanged: (v) => setState(
                                () => _childEnds[c.id] = v,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  Widget _absenceTypeRow() {
    return DropdownButtonFormField<String>(
      initialValue: _absenceType,
      decoration: const InputDecoration(
        labelText: 'Poissaolon tyyppi',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'OTHER_ABSENCE', child: Text('Poissaolo')),
        DropdownMenuItem(value: 'SICKLEAVE', child: Text('Sairaus')),
      ],
      onChanged: (v) => setState(() => _absenceType = v ?? 'OTHER_ABSENCE'),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value,
          initialEntryMode: TimePickerEntryMode.input,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(_hhmm(value)),
      ),
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

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
