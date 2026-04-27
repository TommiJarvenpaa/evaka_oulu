import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models/questionnaire.dart';
import '../state/app_state.dart';

class QuestionnaireScreen extends ConsumerStatefulWidget {
  const QuestionnaireScreen({super.key, required this.questionnaire});

  final HolidayQuestionnaire questionnaire;

  @override
  ConsumerState<QuestionnaireScreen> createState() =>
      _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends ConsumerState<QuestionnaireScreen> {
  late Map<String, List<({DateTime start, DateTime end})>> _answers;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _answers = {};
    // Täytä aiemmilla vastauksilla jos on
    widget.questionnaire.previousAnswers.forEach((childId, ranges) {
      _answers[childId] =
          ranges.map((r) => (start: r.start, end: r.end)).toList();
    });
    // Varmista että kaikille eligible-lapsille on lista (tyhjä jos ei vastattu)
    for (final childId in widget.questionnaire.eligibleChildren.keys) {
      _answers.putIfAbsent(childId, () => []);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(questionnaireApiProvider).answerOpenRange(
            questionnaireId: widget.questionnaire.questionnaire.id,
            answers: _answers,
          );
      ref.invalidate(activeQuestionnairesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = 'Lähetys epäonnistui: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questionnaire.questionnaire;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(q.titleFi.isNotEmpty ? q.titleFi : 'Poissaolokysely'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (q.descriptionFi.isNotEmpty) ...[
              Text(q.descriptionFi, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
            ],
            if (q.descriptionLinkFi.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Lisätietoja'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => launchUrl(Uri.parse(q.descriptionLinkFi),
                    mode: LaunchMode.externalApplication),
              ),
            const SizedBox(height: 4),
            Text(
              'Kysely avoinna: ${_fmtDate(q.active.start)} – ${_fmtDate(q.active.end)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            for (final entry in widget.questionnaire.eligibleChildren.entries)
              _ChildRangeCard(
                childId: entry.key,
                allowedRanges: entry.value,
                questionnaire: q,
                ranges: _answers[entry.key] ?? [],
                onChanged: (ranges) =>
                    setState(() => _answers[entry.key] = ranges),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tallenna vastaukset'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildRangeCard extends ConsumerWidget {
  const _ChildRangeCard({
    required this.childId,
    required this.allowedRanges,
    required this.questionnaire,
    required this.ranges,
    required this.onChanged,
  });

  final String childId;
  final List<QuestionnaireRange> allowedRanges;
  final QuestionnaireDetails questionnaire;
  final List<({DateTime start, DateTime end})> ranges;
  final ValueChanged<List<({DateTime start, DateTime end})>> onChanged;

  String _childName(WidgetRef ref) {
    final reservations = ref.watch(reservationsProvider).asData?.value;
    if (reservations == null) return '(lapsi)';
    final child = reservations.children
        .where((c) => c.id == childId)
        .firstOrNull;
    return child?.displayName ?? '(lapsi)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = _childName(ref);
    final allowed = allowedRanges.isNotEmpty
        ? allowedRanges.first
        : QuestionnaireRange(
            start: questionnaire.period.start,
            end: questionnaire.period.end,
          );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            )),
            Text(
              'Ilmoita poissaolojaksot välillä '
              '${_fmtDate(allowed.start)} – ${_fmtDate(allowed.end)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < ranges.length; i++)
              _RangeRow(
                range: ranges[i],
                allowed: allowed,
                onChanged: (r) {
                  final updated = [...ranges];
                  updated[i] = r;
                  onChanged(updated);
                },
                onRemove: () {
                  final updated = [...ranges]..removeAt(i);
                  onChanged(updated);
                },
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Lisää jakso'),
              onPressed: () {
                onChanged([
                  ...ranges,
                  (start: allowed.start, end: allowed.end),
                ]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.range,
    required this.allowed,
    required this.onChanged,
    required this.onRemove,
  });

  final ({DateTime start, DateTime end}) range;
  final QuestionnaireRange allowed;
  final ValueChanged<({DateTime start, DateTime end})> onChanged;
  final VoidCallback onRemove;

  Future<void> _pickDate(
    BuildContext context, {
    required bool isStart,
  }) async {
    final initial = isStart ? range.start : range.end;
    final first = isStart ? allowed.start : range.start;
    final last = allowed.end;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first)
          ? first
          : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
      locale: const Locale('fi', 'FI'),
    );
    if (picked == null) return;

    if (isStart) {
      final end = picked.isAfter(range.end) ? picked : range.end;
      onChanged((start: picked, end: end));
    } else {
      onChanged((start: range.start, end: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                textStyle: theme.textTheme.bodyMedium,
              ),
              onPressed: () => _pickDate(context, isStart: true),
              child: Text(_fmtDate(range.start)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('–'),
          ),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                textStyle: theme.textTheme.bodyMedium,
              ),
              onPressed: () => _pickDate(context, isStart: false),
              child: Text(_fmtDate(range.end)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            tooltip: 'Poista jakso',
          ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) => DateFormat('d.M.yyyy').format(d);
