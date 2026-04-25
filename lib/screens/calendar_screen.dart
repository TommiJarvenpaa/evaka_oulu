import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/calendar_event.dart';
import '../state/app_state.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(calendarEventsProvider);
    final childrenAsync = ref.watch(reservationsProvider);

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
              Text('Kalenterin haku epäonnistui:\n$e',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(calendarEventsProvider),
                child: const Text('Yritä uudelleen'),
              ),
            ],
          ),
        ),
      ),
      data: (events) {
        if (events.isEmpty) {
          return const Center(child: Text('Ei tulevia tapahtumia.'));
        }

        final childrenList = childrenAsync.asData?.value.children ?? const [];
        final childNames = <String, String>{
          for (final c in childrenList) c.id: c.displayName,
        };

        final sorted = [...events]
          ..sort((a, b) => a.period.start.compareTo(b.period.start));

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(calendarEventsProvider);
            await ref.read(calendarEventsProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: sorted.length,
            itemBuilder: (context, i) => _EventCard(
              event: sorted[i],
              childNames: childNames,
            ),
          ),
        );
      },
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.childNames});

  final CalendarEvent event;
  final Map<String, String> childNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Käytä varatun ajan päivämäärää jos tämä on DISCUSSION_SURVEY jolle on
    // varattu aika. Muuten näytä period.start.
    final displayDate = _primaryDate(event);
    final isPast = displayDate.isBefore(today);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      color: isPast ? theme.colorScheme.surfaceContainerLow : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateBlock(
                  date: displayDate,
                  rangeEnd: event.period.end,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isPast
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                      if (event.hasBookedTime) ...[
                        const SizedBox(height: 2),
                        _BookedTimes(
                          bookedTimes: event.bookedTimes,
                          childNames: childNames,
                        ),
                      ],
                      const SizedBox(height: 4),
                      _Attendees(
                        attending: event.attendingChildren,
                        childNames: childNames,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(event.description, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  DateTime _primaryDate(CalendarEvent event) {
    if (event.hasBookedTime) {
      // Käytä aikaisinta varattua päivää
      final allDates = event.bookedTimes.values
          .expand((list) => list.map((t) => t.date));
      if (allDates.isNotEmpty) {
        return allDates.reduce((a, b) => a.isBefore(b) ? a : b);
      }
    }
    return event.period.start;
  }
}

class _BookedTimes extends StatelessWidget {
  const _BookedTimes({
    required this.bookedTimes,
    required this.childNames,
  });

  final Map<String, List<DiscussionTime>> bookedTimes;
  final Map<String, String> childNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final lines = <Widget>[];
    bookedTimes.forEach((childId, times) {
      final name = childNames[childId] ?? '(lapsi)';
      for (final t in times) {
        lines.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              '$name: ${DateFormat('d.M.').format(t.date)} '
              'klo ${t.startHHmm}–${t.endHHmm}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ));
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date, required this.rangeEnd});

  final DateTime date;
  final DateTime rangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sameDay = date.year == rangeEnd.year &&
        date.month == rangeEnd.month &&
        date.day == rangeEnd.day;

    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('MMM', 'fi_FI').format(date).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${date.day}',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          if (!sameDay && date.isBefore(rangeEnd))
            Text(
              '– ${rangeEnd.day}.${rangeEnd.month}.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
        ],
      ),
    );
  }
}

class _Attendees extends StatelessWidget {
  const _Attendees({required this.attending, required this.childNames});

  final Map<String, List<AttendingChild>> attending;
  final Map<String, String> childNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (attending.isEmpty) return const SizedBox.shrink();

    final entries = attending.entries.map((e) {
      final name = childNames[e.key] ?? '(lapsi)';
      final firstAttending = e.value.isNotEmpty ? e.value.first : null;
      final location = firstAttending?.groupName ?? firstAttending?.unitName;
      if (location != null && location.isNotEmpty) {
        return '$name · $location';
      }
      return name;
    }).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final s in entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              s,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
      ],
    );
  }
}
