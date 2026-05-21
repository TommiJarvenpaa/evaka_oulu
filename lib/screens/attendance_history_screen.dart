import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/reservations.dart';
import '../state/app_state.dart';
import '../widgets/child_image.dart';

/// Read-only näkymä menneille hoitoajoille. Hakee `attendanceHistoryProvider`:n
/// kautta (autoDispose) eikä jaa cachea pää-läsnäolonäkymän kanssa.
class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attendanceHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Hoitoaikahistoria')),
      body: SafeArea(
        top: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Historian haku epäonnistui:\n$e',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(attendanceHistoryProvider),
                    child: const Text('Yritä uudelleen'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(attendanceHistoryProvider);
              await ref.read(attendanceHistoryProvider.future);
            },
            child: _HistoryList(data: data),
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.data});
  final ReservationsResponse data;

  @override
  Widget build(BuildContext context) {
    final childrenById = {for (final c in data.children) c.id: c};

    final daysWithAttendance =
        data.days.where((d) => d.children.any((c) => c.hasAttendance)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    if (daysWithAttendance.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Ei toteutuneita hoitoaikoja tällä ajanjaksolla.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: daysWithAttendance.length,
      itemBuilder: (context, i) {
        final day = daysWithAttendance[i];
        return _HistoryDayCard(day: day, childrenById: childrenById);
      },
    );
  }
}

class _HistoryDayCard extends StatelessWidget {
  const _HistoryDayCard({required this.day, required this.childrenById});
  final ReservationDay day;
  final Map<String, ReservationChild> childrenById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = DateFormat('EEEE', 'fi_FI').format(day.date);
    final dateStr = DateFormat('d.M.yyyy').format(day.date);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_capitalize(weekday)} $dateStr',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            for (final cd in day.children)
              if (cd.hasAttendance)
                _HistoryChildRow(child: childrenById[cd.childId], childDay: cd),
          ],
        ),
      ),
    );
  }
}

class _HistoryChildRow extends StatelessWidget {
  const _HistoryChildRow({required this.child, required this.childDay});
  final ReservationChild? child;
  final ReservationChildDay childDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = child?.displayName ?? '(lapsi)';
    final attendanceText = _attendanceLabel(childDay.attendances);
    final reservationText = _reservationLabel(childDay.reservations);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChildImage(
            imageId: child?.imageId,
            fallbackLetter: name.isNotEmpty ? name[0] : '?',
            radius: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.bodyMedium),
                if (reservationText.isNotEmpty)
                  Text(
                    'Varattu: $reservationText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  'Toteutunut: $attendanceText',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _trimSeconds(String t) => t.length >= 5 ? t.substring(0, 5) : t;

String _attendanceLabel(List<Attendance> attendances) {
  if (attendances.isEmpty) return '';
  return attendances
      .map((a) {
        final start = _trimSeconds(a.startTime);
        final end = a.endTime == null ? '' : _trimSeconds(a.endTime!);
        return a.isOngoing ? '$start – (paikalla)' : '$start – $end';
      })
      .join(', ');
}

String _reservationLabel(List<Reservation> reservations) {
  if (reservations.isEmpty) return '';
  return reservations
      .map((r) {
        if (r.type == 'TIMES' && r.start != null && r.end != null) {
          return '${_trimSeconds(r.start!)}–${_trimSeconds(r.end!)}';
        }
        return '—';
      })
      .join(', ');
}
