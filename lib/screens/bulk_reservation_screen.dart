import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/reservations.dart';
import '../api/reservations_api.dart';
import '../state/app_state.dart';
import '../widgets/child_image.dart';
import '../widgets/day_card.dart';

enum _Repetition { daily, weekly, irregular }

class BulkReservationScreen extends ConsumerStatefulWidget {
  const BulkReservationScreen({super.key, required this.data});

  final ReservationsResponse data;

  @override
  ConsumerState<BulkReservationScreen> createState() =>
      _BulkReservationScreenState();
}

class _BulkReservationScreenState
    extends ConsumerState<BulkReservationScreen> {
  late Set<String> _selectedChildIds;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  _Repetition _mode = _Repetition.daily;

  // Yksi rule kaikille päiville
  DaySpec _daily = const DaySpec();

  // Viikonpäiväkohtainen (1=ma … 5=pe)
  final Map<int, DaySpec> _weekly = {
    1: const DaySpec(),
    2: const DaySpec(),
    3: const DaySpec(),
    4: const DaySpec(),
    5: const DaySpec(),
  };

  // Päiväkohtainen
  final Map<DateTime, DaySpec> _irregular = {};

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedChildIds = widget.data.children.map((c) => c.id).toSet();
  }

  DateTime get _minDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rangeStart = widget.data.reservableRange?.start;
    if (rangeStart != null) {
      final start = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
      return start.isAfter(today) ? start : today;
    }
    return today;
  }

  DateTime get _maxDate {
    return widget.data.reservableRange?.end ??
        _minDate.add(const Duration(days: 180));
  }

  Set<DateTime> get _holidays => widget.data.days
      .where((d) => d.holiday)
      .map((d) => _dateOnly(d.date))
      .toSet();

  Set<DateTime> get _noChildDays => widget.data.days
      .where((d) => d.children.isEmpty)
      .map((d) => _dateOnly(d.date))
      .toSet();

  Set<DateTime> get _closedDays => widget.data.days
      .where((d) => d.children.any((c) => c.reservationsClosed))
      .map((d) => _dateOnly(d.date))
      .toSet();

  List<DateTime> _eligibleDays() {
    if (_rangeStart == null || _rangeEnd == null) return const [];
    final holidays = _holidays;
    final noChild = _noChildDays;
    final out = <DateTime>[];
    var d = _dateOnly(_rangeStart!);
    final end = _dateOnly(_rangeEnd!);
    while (!d.isAfter(end)) {
      final isWeekend = d.weekday == DateTime.saturday ||
          d.weekday == DateTime.sunday;
      if (!isWeekend && !holidays.contains(d) && !noChild.contains(d)) {
        out.add(d);
      }
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _minDate,
      lastDate: _maxDate,
      initialDateRange: _rangeStart != null && _rangeEnd != null
          ? DateTimeRange(start: _rangeStart!, end: _rangeEnd!)
          : null,
      helpText: '',
      locale: const Locale('fi', 'FI'),
    );
    if (picked != null) {
      setState(() {
        _rangeStart = picked.start;
        _rangeEnd = picked.end;
        _irregular.clear();
        for (final d in _eligibleDays()) {
          _irregular[d] = const DaySpec();
        }
      });
    }
  }

  /// Mikä spec sovelletaan tälle päivälle? Null jos päivä ohitetaan.
  DaySpec? _specForDay(DateTime day) {
    switch (_mode) {
      case _Repetition.daily:
        return _daily;
      case _Repetition.weekly:
        return _weekly[day.weekday];
      case _Repetition.irregular:
        return _irregular[_dateOnly(day)];
    }
  }

  Future<void> _submit() async {
    if (_selectedChildIds.isEmpty) {
      setState(() => _error = 'Valitse vähintään yksi lapsi');
      return;
    }
    if (_rangeStart == null || _rangeEnd == null) {
      setState(() => _error = 'Valitse aikaväli');
      return;
    }
    final days = _eligibleDays();
    if (days.isEmpty) {
      setState(() => _error = 'Välillä ei ole yhtään arkipäivää');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final api = ref.read(reservationsApiProvider);
      final reservationInputs = <ReservationInput>[];
      // Per-päivä poissaolot ryhmiteltynä tyypin mukaan
      final absencesByType = <String, List<DateTime>>{};

      final closed = _closedDays;
      for (final d in days) {
        final spec = _specForDay(d);
        if (spec == null) continue;
        final isClosed = closed.contains(d);
        for (final childId in _selectedChildIds) {
          switch (spec.kind) {
            case DayKind.present:
              if (!isClosed) {
                reservationInputs.add(ReservationInput.times(
                  childId: childId,
                  date: d,
                  start: TimePickerField.hhmm(spec.start),
                  end: TimePickerField.hhmm(spec.end),
                ));
              }
            case DayKind.poissa:
            case DayKind.sairas:
            case DayKind.tyhja:
              reservationInputs
                  .add(ReservationInput.clear(childId: childId, date: d));
          }
        }
        if (spec.kind == DayKind.poissa) {
          absencesByType.putIfAbsent('OTHER_ABSENCE', () => []).add(d);
        } else if (spec.kind == DayKind.sairas) {
          absencesByType.putIfAbsent('SICKLEAVE', () => []).add(d);
        }
      }

      if (reservationInputs.isEmpty && absencesByType.isEmpty) {
        setState(() {
          _error = 'Asetusten mukaan ei tullut yhtään merkintää';
          _submitting = false;
        });
        return;
      }

      if (reservationInputs.isNotEmpty) {
        await api.postReservations(reservationInputs);
      }
      // Yksi /absences-kutsu per päivä per tyyppi (yksinkertaisin)
      int absenceCount = 0;
      for (final entry in absencesByType.entries) {
        for (final d in entry.value) {
          await api.postAbsence(
            childIds: _selectedChildIds.toList(),
            start: d,
            end: d,
            absenceType: entry.key,
          );
          absenceCount++;
        }
      }

      ref.invalidate(reservationsProvider);
      if (!mounted) return;
      final realRes =
          reservationInputs.where((r) => r.type != 'NOTHING').length;
      final parts = <String>[];
      if (realRes > 0) parts.add('$realRes varausta');
      if (absenceCount > 0) parts.add('$absenceCount poissaoloa');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(parts.isEmpty
                ? 'Tallennettu'
                : '${parts.join(" + ")} tallennettu')),
      );
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
    final dateFmt = DateFormat('d.M.yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Massailmoitus'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Tallenna'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('Lapset', style: theme.textTheme.labelLarge),
            for (final c in widget.data.children)
              InkWell(
                onTap: () => setState(() {
                  if (_selectedChildIds.contains(c.id)) {
                    _selectedChildIds.remove(c.id);
                  } else {
                    _selectedChildIds.add(c.id);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selectedChildIds.contains(c.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedChildIds.add(c.id);
                          } else {
                            _selectedChildIds.remove(c.id);
                          }
                        }),
                        visualDensity: VisualDensity.compact,
                      ),
                      ChildImage(
                        imageId: c.imageId,
                        fallbackLetter:
                            c.displayName.isNotEmpty ? c.displayName[0] : '?',
                        radius: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(c.displayName),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            Text('Aikaväli', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(
                _rangeStart == null
                    ? 'Valitse aikaväli'
                    : '${dateFmt.format(_rangeStart!)} – ${dateFmt.format(_rangeEnd!)}',
              ),
              onPressed: _submitting ? null : _pickDateRange,
            ),
            const SizedBox(height: 4),
            Text(
              'Enimmillään ${dateFmt.format(_maxDate)} asti',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_rangeStart != null) ...[
              const SizedBox(height: 4),
              Text(
                '${_eligibleDays().length} arkipäivää valittu '
                '(viikonloput ja pyhät pois)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            if (_rangeStart != null && _rangeEnd != null) ...[
              const SizedBox(height: 16),
              Text('Miten kellonaika toistuu',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              SegmentedButton<_Repetition>(
                segments: const [
                  ButtonSegment(
                      value: _Repetition.daily, label: Text('Päivä')),
                  ButtonSegment(
                      value: _Repetition.weekly, label: Text('Viikko')),
                  ButtonSegment(
                      value: _Repetition.irregular, label: Text('Vaihtuva')),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              if (_mode == _Repetition.daily) _dailySection(),
              if (_mode == _Repetition.weekly) _weeklySection(),
              if (_mode == _Repetition.irregular) _irregularSection(),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dailySection() {
    return DayCard(
      title: 'Sama merkintä kaikille arkipäiville',
      subtitle: _rangeStart != null
          ? '${_eligibleDays().length} päivää valitulla aikavälillä'
          : 'Valitse aikaväli',
      spec: _daily,
      onChanged: (s) => setState(() => _daily = s),
    );
  }

  Widget _weeklySection() {
    const fullNames = {1: 'Maanantai', 2: 'Tiistai', 3: 'Keskiviikko',
                       4: 'Torstai', 5: 'Perjantai'};
    final activeWeekdays = _eligibleDays().map((d) => d.weekday).toSet();
    final visible = activeWeekdays.isEmpty
        ? const [1, 2, 3, 4, 5]
        : ([1, 2, 3, 4, 5]..removeWhere((wd) => !activeWeekdays.contains(wd)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int wd in visible)
          DayCard(
            title: fullNames[wd]!,
            spec: _weekly[wd]!,
            onChanged: (s) => setState(() => _weekly[wd] = s),
          ),
      ],
    );
  }

  Widget _irregularSection() {
    final days = _eligibleDays();
    if (days.isEmpty) {
      return Text(
        'Valitse aikaväli ensin',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final closed = _closedDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final d in days)
          DayCard(
            title: _capitalize(DateFormat('EEEE d.M.', 'fi_FI').format(d)),
            spec: _irregular[d] ?? const DaySpec(),
            onChanged: (s) => setState(() => _irregular[d] = s),
            timesEditable: !closed.contains(d),
          ),
      ],
    );
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
