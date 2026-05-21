import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/calendar_event.dart';
import '../api/models/reservations.dart';
import '../api/notifications_api.dart';
import '../state/app_state.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(calendarEventsProvider);
    final childrenAsync = ref.watch(reservationsProvider);
    final dstNotifs =
        ref.watch(dailyServiceTimeNotificationsProvider).asData?.value ??
            const <DailyServiceTimeNotification>[];

    return Column(
      children: [
        if (dstNotifs.isNotEmpty)
          _DailyServiceTimeBanner(notifications: dstNotifs),
        Expanded(child: _buildBody(context, ref, async, childrenAsync)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<CalendarEvent>> async,
    AsyncValue<ReservationsResponse> childrenAsync,
  ) {
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
            itemBuilder: (context, i) {
              final event = sorted[i];
              if (event.isDiscussion) {
                return _DiscussionCard(event: event, childNames: childNames);
              }
              return _EventCard(event: event, childNames: childNames);
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// DISCUSSION_SURVEY -kortti
// ---------------------------------------------------------------------------

class _DiscussionCard extends ConsumerStatefulWidget {
  const _DiscussionCard({required this.event, required this.childNames});

  final CalendarEvent event;
  final Map<String, String> childNames;

  @override
  ConsumerState<_DiscussionCard> createState() => _DiscussionCardState();
}

class _DiscussionCardState extends ConsumerState<_DiscussionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isPast = widget.event.period.end.isBefore(today);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      color: isPast ? theme.colorScheme.surfaceContainerLow : null,
      child: InkWell(
        onTap: widget.event.slotsByChild.isEmpty
            ? null
            : () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DateBlock(
                    date: widget.event.period.start,
                    rangeEnd: widget.event.period.end,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.forum_outlined, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.event.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isPast
                                      ? theme.colorScheme.onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                            if (widget.event.hasBookedTime)
                              Icon(Icons.check_circle,
                                  size: 18,
                                  color: theme.colorScheme.primary),
                          ],
                        ),
                        if (widget.event.hasBookedTime) ...[
                          const SizedBox(height: 4),
                          for (final entry
                              in widget.event.bookedTimes.entries)
                            for (final t in entry.value)
                              Text(
                                '${widget.childNames[entry.key] ?? "(lapsi)"}: '
                                '${DateFormat("d.M.").format(t.date)} '
                                'klo ${t.startHHmm}–${t.endHHmm}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        ] else if (!isPast) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Ei varattua aikaa – napauta varataksesi',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.event.slotsByChild.isNotEmpty)
                    Icon(
                      _expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _SlotList(event: widget.event, childNames: widget.childNames),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotList extends ConsumerWidget {
  const _SlotList({required this.event, required this.childNames});

  final CalendarEvent event;
  final Map<String, String> childNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    event.slotsByChild.forEach((eligibleChildId, slots) {
      final name = childNames[eligibleChildId] ?? '(lapsi)';
      widgets.add(
        Text(name,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            )),
      );
      widgets.add(const SizedBox(height: 6));

      // Onko lapsella jo varaus tässä tapahtumassa → älä näytä muita "Varaa"-nappeja
      final alreadyBooked =
          slots.any((s) => s.childId == eligibleChildId);

      // Ryhmittele slotit päivittäin
      final byDate = <DateTime, List<DiscussionTime>>{};
      for (final s in slots) {
        final day = DateTime(s.date.year, s.date.month, s.date.day);
        byDate.putIfAbsent(day, () => []).add(s);
      }

      for (final day in byDate.keys.toList()..sort()) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              DateFormat('EEEE d.M.yyyy', 'fi_FI').format(day),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        for (final slot in byDate[day]!) {
          final isMySlot = slot.childId == eligibleChildId;
          final isTaken = slot.childId != null && !isMySlot;
          widgets.add(
            _SlotTile(
              slot: slot,
              eligibleChildId: eligibleChildId,
              isMySlot: isMySlot,
              isTaken: isTaken,
              onBook: !alreadyBooked && slot.isAvailable && slot.isEditable
                  ? () => _book(context, ref, slot, eligibleChildId)
                  : null,
              onCancel: isMySlot && slot.isEditable
                  ? () => _cancel(context, ref, slot, eligibleChildId)
                  : null,
            ),
          );
        }
      }
      widgets.add(const SizedBox(height: 12));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Future<void> _book(BuildContext context, WidgetRef ref,
      DiscussionTime slot, String childId) async {
    try {
      await ref.read(calendarApiProvider).bookDiscussionTime(
            calendarEventTimeId: slot.id,
            childId: childId,
          );
      ref.invalidate(calendarEventsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Varaus epäonnistui: $e')),
        );
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref,
      DiscussionTime slot, String childId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Peruuta varaus?'),
        content: Text(
            '${DateFormat("d.M.yyyy").format(slot.date)} klo ${slot.startHHmm}–${slot.endHHmm}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ei')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Peruuta varaus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(calendarApiProvider).cancelDiscussionTime(
            calendarEventTimeId: slot.id,
            childId: childId,
          );
      ref.invalidate(calendarEventsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Peruutus epäonnistui: $e')),
        );
      }
    }
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.eligibleChildId,
    required this.isMySlot,
    required this.isTaken,
    required this.onBook,
    required this.onCancel,
  });

  final DiscussionTime slot;
  final String eligibleChildId;
  final bool isMySlot;
  final bool isTaken;
  final VoidCallback? onBook;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color bgColor;
    String label;
    if (isMySlot) {
      bgColor = theme.colorScheme.primaryContainer;
      label = '${slot.startHHmm}–${slot.endHHmm} (varattu)';
    } else if (isTaken) {
      bgColor = theme.colorScheme.surfaceContainerLow;
      label = '${slot.startHHmm}–${slot.endHHmm} (varattuna)';
    } else {
      bgColor = theme.colorScheme.surfaceContainerLow;
      label = '${slot.startHHmm}–${slot.endHHmm}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isMySlot
                    ? theme.colorScheme.onPrimaryContainer
                    : (isTaken ? theme.colorScheme.onSurfaceVariant : null),
              ),
            ),
          ),
          if (onBook != null)
            TextButton(
              onPressed: onBook,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Varaa'),
            )
          else if (onCancel != null)
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Peruuta'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tavallinen DAYCARE_EVENT -kortti (ennallaan)
// ---------------------------------------------------------------------------

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.childNames});

  final CalendarEvent event;
  final Map<String, String> childNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
  const _BookedTimes({required this.bookedTimes, required this.childNames});

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
            Icon(Icons.schedule, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              '$name: ${DateFormat("d.M.").format(t.date)} '
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
        crossAxisAlignment: CrossAxisAlignment.start, children: lines);
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
      return location != null && location.isNotEmpty
          ? '$name · $location'
          : name;
    }).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final s in entries)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

/// Banner kun lapsen päivittäinen palveluaika on muuttunut backendissa.
/// Kuittaus poistaa ilmoituksen listalta.
class _DailyServiceTimeBanner extends ConsumerStatefulWidget {
  const _DailyServiceTimeBanner({required this.notifications});

  final List<DailyServiceTimeNotification> notifications;

  @override
  ConsumerState<_DailyServiceTimeBanner> createState() =>
      _DailyServiceTimeBannerState();
}

class _DailyServiceTimeBannerState
    extends ConsumerState<_DailyServiceTimeBanner> {
  bool _dismissing = false;

  Future<void> _dismiss() async {
    final ids = widget.notifications.map((n) => n.id).toList();
    setState(() => _dismissing = true);
    try {
      await ref
          .read(notificationsApiProvider)
          .dismissDailyServiceTimeNotifications(ids);
      ref.invalidate(dailyServiceTimeNotificationsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kuittaus epäonnistui: $e')),
      );
    } finally {
      if (mounted) setState(() => _dismissing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.notifications.length;
    // Etsi aikaisin dateFrom
    final earliest = widget.notifications
        .map((n) => n.dateFrom)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final dateText = earliest.isEmpty
        ? ''
        : ' alkaen ${DateFormat('d.M.yyyy').format(earliest.first)}';
    final mainText = count == 1
        ? 'Lapsesi päivittäinen palveluaika on muuttunut$dateText'
        : 'Lapsien päivittäiset palveluajat ovat muuttuneet$dateText ($count kpl)';
    final hasDeletedReservations =
        widget.notifications.any((n) => n.hasDeletedReservations);

    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.schedule,
              size: 20,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  if (hasDeletedReservations) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Osa varauksistasi on poistettu uuden palveluajan vuoksi.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: _dismissing ? null : _dismiss,
              child: _dismissing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kuittaa'),
            ),
          ],
        ),
      ),
    );
  }
}
