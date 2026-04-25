import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/reservations.dart';
import '../api/reservations_api.dart';
import '../state/app_state.dart';

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
  String _absenceType = 'OTHER_ABSENCE';
  _Repetition _mode = _Repetition.daily;

  // DAILY
  TimeOfDay _dailyStart = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _dailyEnd = const TimeOfDay(hour: 17, minute: 0);
  bool _dailyAbsent = false;

  // WEEKLY — viikonpäiväkohtaiset ajat (1=ma … 5=pe)
  final Map<int, bool> _weeklyEnabled = {1: true, 2: true, 3: true, 4: true, 5: true};
  final Map<int, bool> _weeklyAbsent = {1: false, 2: false, 3: false, 4: false, 5: false};
  final Map<int, TimeOfDay> _weeklyStarts = {
    1: const TimeOfDay(hour: 7, minute: 0),
    2: const TimeOfDay(hour: 7, minute: 0),
    3: const TimeOfDay(hour: 7, minute: 0),
    4: const TimeOfDay(hour: 7, minute: 0),
    5: const TimeOfDay(hour: 7, minute: 0),
  };
  final Map<int, TimeOfDay> _weeklyEnds = {
    1: const TimeOfDay(hour: 17, minute: 0),
    2: const TimeOfDay(hour: 17, minute: 0),
    3: const TimeOfDay(hour: 17, minute: 0),
    4: const TimeOfDay(hour: 17, minute: 0),
    5: const TimeOfDay(hour: 17, minute: 0),
  };

  // IRREGULAR — päiväkohtaiset ajat ja per-päivä poissaolo-toggle
  final Map<DateTime, TimeOfDay> _irregularStarts = {};
  final Map<DateTime, TimeOfDay> _irregularEnds = {};
  final Set<DateTime> _irregularAbsentDays = {};

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedChildIds = widget.data.children.map((c) => c.id).toSet();
  }

  DateTime get _minDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _maxDate {
    return widget.data.reservableRange?.end ??
        _minDate.add(const Duration(days: 180));
  }

  Set<DateTime> get _holidays => widget.data.days
      .where((d) => d.holiday)
      .map((d) => _dateOnly(d.date))
      .toSet();

  /// Päivät joille API ei palauta lasta (viikonloput, erikoispäivät)
  Set<DateTime> get _noChildDays => widget.data.days
      .where((d) => d.children.isEmpty)
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
      helpText: 'Valitse aikaväli',
      locale: const Locale('fi', 'FI'),
    );
    if (picked != null) {
      setState(() {
        _rangeStart = picked.start;
        _rangeEnd = picked.end;
        // Esitäytä IRREGULAR-ajat oletuksilla
        _irregularStarts.clear();
        _irregularEnds.clear();
        _irregularAbsentDays.clear();
        for (final d in _eligibleDays()) {
          _irregularStarts[d] = _dailyStart;
          _irregularEnds[d] = _dailyEnd;
        }
      });
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
      final absentDays = <DateTime>[];

      for (final d in days) {
        final spec = _specForDay(d);
        if (spec.skip) continue;

        if (spec.absent) {
          absentDays.add(d);
          // Tyhjennä mahdolliset olemassa olevat varaukset
          for (final childId in _selectedChildIds) {
            reservationInputs
                .add(ReservationInput.clear(childId: childId, date: d));
          }
        } else {
          for (final childId in _selectedChildIds) {
            reservationInputs.add(ReservationInput.times(
              childId: childId,
              date: d,
              start: _hhmm(spec.start!),
              end: _hhmm(spec.end!),
            ));
          }
        }
      }

      if (reservationInputs.isEmpty && absentDays.isEmpty) {
        setState(() {
          _error = 'Asetusten mukaan ei tullut yhtään merkintää';
          _submitting = false;
        });
        return;
      }

      if (reservationInputs.isNotEmpty) {
        await api.postReservations(reservationInputs);
      }
      // Poissaolot lähetetään yhtenä kutsuna per päivä (yksinkertaisuus)
      for (final d in absentDays) {
        await api.postAbsence(
          childIds: _selectedChildIds.toList(),
          start: d,
          end: d,
          absenceType: _absenceType,
        );
      }

      ref.invalidate(reservationsProvider);
      if (!mounted) return;
      final parts = <String>[];
      final realRes = reservationInputs
          .where((r) => r.type != 'NOTHING')
          .length;
      if (realRes > 0) parts.add('$realRes varausta');
      if (absentDays.isNotEmpty) parts.add('${absentDays.length} poissaoloa');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${parts.join(" + ")} tallennettu')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Tallennus epäonnistui: $e';
        _submitting = false;
      });
    }
  }

  // Vanha `_timesForDay` korvattiin `_specForDay`:llä joka tukee myös poissaoloa
  /// Mitä tehdä yhdelle päivälle: skip (ei mitään), absent, tai times.
  ({bool skip, bool absent, TimeOfDay? start, TimeOfDay? end}) _specForDay(
      DateTime day) {
    switch (_mode) {
      case _Repetition.daily:
        if (_dailyAbsent) return (skip: false, absent: true, start: null, end: null);
        return (skip: false, absent: false, start: _dailyStart, end: _dailyEnd);
      case _Repetition.weekly:
        final wd = day.weekday;
        if (!(_weeklyEnabled[wd] ?? false)) {
          return (skip: true, absent: false, start: null, end: null);
        }
        if (_weeklyAbsent[wd] ?? false) {
          return (skip: false, absent: true, start: null, end: null);
        }
        return (skip: false, absent: false,
            start: _weeklyStarts[wd], end: _weeklyEnds[wd]);
      case _Repetition.irregular:
        final d = _dateOnly(day);
        if (_irregularAbsentDays.contains(d)) {
          return (skip: false, absent: true, start: null, end: null);
        }
        final s = _irregularStarts[d];
        final e = _irregularEnds[d];
        if (s == null || e == null) {
          return (skip: true, absent: false, start: null, end: null);
        }
        return (skip: false, absent: false, start: s, end: e);
    }
  }

  /// Onko jollain päivällä asetuksena poissaolo? Käytetään
  /// poissaolotyypin dropdownin näkymisen päättelemiseen.
  bool get _hasAbsenceConfigured {
    switch (_mode) {
      case _Repetition.daily:
        return _dailyAbsent;
      case _Repetition.weekly:
        return _weeklyAbsent.entries.any(
          (e) => (_weeklyEnabled[e.key] ?? false) && e.value,
        );
      case _Repetition.irregular:
        return _irregularAbsentDays.isNotEmpty;
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
            // LAPSET
            Text('Lapset', style: theme.textTheme.labelLarge),
            for (final c in widget.data.children)
              CheckboxListTile(
                title: Text(c.displayName),
                value: _selectedChildIds.contains(c.id),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedChildIds.add(c.id);
                  } else {
                    _selectedChildIds.remove(c.id);
                  }
                }),
              ),
            const SizedBox(height: 16),

            // PÄIVÄMÄÄRÄVÄLI
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
            const SizedBox(height: 16),

            // TOISTUMISTYYPPI
            Text('Miten kellonaika toistuu',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            SegmentedButton<_Repetition>(
              segments: const [
                ButtonSegment(
                  value: _Repetition.daily,
                  label: Text('Päivä'),
                ),
                ButtonSegment(
                  value: _Repetition.weekly,
                  label: Text('Viikko'),
                ),
                ButtonSegment(
                  value: _Repetition.irregular,
                  label: Text('Vaihtuva'),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            if (_mode == _Repetition.daily) _dailySection(),
            if (_mode == _Repetition.weekly) _weeklySection(),
            if (_mode == _Repetition.irregular) _irregularSection(),

            // POISSAOLON TYYPPI näkyy aina kun joku rivi/päivä on Poissa
            if (_hasAbsenceConfigured) ...[
              const SizedBox(height: 16),
              Text('Poissaolon tyyppi', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _absenceType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'OTHER_ABSENCE', child: Text('Poissaolo')),
                  DropdownMenuItem(
                      value: 'SICKLEAVE', child: Text('Sairaus')),
                ],
                onChanged: (v) => setState(
                  () => _absenceType = v ?? 'OTHER_ABSENCE',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mahdolliset olemassa olevat varaukset poistetaan ennen poissaolon merkitsemistä.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Saapuu')),
            ButtonSegment(value: true, label: Text('Poissa')),
          ],
          selected: {_dailyAbsent},
          onSelectionChanged: (s) =>
              setState(() => _dailyAbsent = s.first),
        ),
        const SizedBox(height: 12),
        if (!_dailyAbsent)
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'Alkaa',
                  value: _dailyStart,
                  onChanged: (v) => setState(() => _dailyStart = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  label: 'Päättyy',
                  value: _dailyEnd,
                  onChanged: (v) => setState(() => _dailyEnd = v),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _weeklySection() {
    const names = {1: 'Maanantai', 2: 'Tiistai', 3: 'Keskiviikko',
                   4: 'Torstai', 5: 'Perjantai'};
    // Vain ne viikonpäivät jotka esiintyvät valitulla päivämääräalueella
    final activeWeekdays = _eligibleDays().map((d) => d.weekday).toSet();
    final visible = activeWeekdays.isEmpty
        ? const [1, 2, 3, 4, 5]
        : ([1, 2, 3, 4, 5]..removeWhere((wd) => !activeWeekdays.contains(wd)));
    return Column(
      children: [
        for (int wd in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _weeklyEnabled[wd] ?? false,
                      onChanged: (v) => setState(
                        () => _weeklyEnabled[wd] = v ?? false,
                      ),
                    ),
                    Expanded(
                      child: Text(names[wd]!,
                          style: Theme.of(context).textTheme.labelLarge),
                    ),
                    if (_weeklyEnabled[wd] == true)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Saapuu')),
                          ButtonSegment(value: true, label: Text('Poissa')),
                        ],
                        selected: {_weeklyAbsent[wd] ?? false},
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (s) => setState(
                          () => _weeklyAbsent[wd] = s.first,
                        ),
                      ),
                  ],
                ),
                if (_weeklyEnabled[wd] == true && !(_weeklyAbsent[wd] ?? false))
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Row(
                      children: [
                        Expanded(
                          child: _TimeField(
                            label: 'Alkaa',
                            value: _weeklyStarts[wd]!,
                            onChanged: (v) => setState(
                              () => _weeklyStarts[wd] = v,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimeField(
                            label: 'Päättyy',
                            value: _weeklyEnds[wd]!,
                            onChanged: (v) => setState(
                              () => _weeklyEnds[wd] = v,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _capitalize(
                          DateFormat('EEEE d.M.', 'fi_FI').format(d),
                        ),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Saapuu')),
                        ButtonSegment(value: true, label: Text('Poissa')),
                      ],
                      selected: {_irregularAbsentDays.contains(d)},
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (s) => setState(() {
                        if (s.first) {
                          _irregularAbsentDays.add(d);
                        } else {
                          _irregularAbsentDays.remove(d);
                        }
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (!_irregularAbsentDays.contains(d))
                  Row(
                    children: [
                      Expanded(
                        child: _TimeField(
                          label: 'Alkaa',
                          value: _irregularStarts[d] ?? _dailyStart,
                          onChanged: (v) => setState(
                            () => _irregularStarts[d] = v,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeField(
                          label: 'Päättyy',
                          value: _irregularEnds[d] ?? _dailyEnd,
                          onChanged: (v) => setState(
                            () => _irregularEnds[d] = v,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (_irregularAbsentDays.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Poissaolon tyyppi (rastituille päiville)',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: _absenceType,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                  value: 'OTHER_ABSENCE', child: Text('Poissaolo')),
              DropdownMenuItem(value: 'SICKLEAVE', child: Text('Sairaus')),
            ],
            onChanged: (v) => setState(
              () => _absenceType = v ?? 'OTHER_ABSENCE',
            ),
          ),
        ],
      ],
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
          isDense: true,
        ),
        child: Text(_hhmm(value)),
      ),
    );
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
