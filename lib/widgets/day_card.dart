import 'package:flutter/material.dart';

import '../main.dart' show AppColors;

/// Yhden päivän/viikonpäivän tila massailmoituksessa ja yhden päivän
/// muokkauksessa.
enum DayKind { present, poissa, sairas, tyhja }

class DaySpec {
  const DaySpec({
    this.kind = DayKind.present,
    this.start = const TimeOfDay(hour: 7, minute: 0),
    this.end = const TimeOfDay(hour: 17, minute: 0),
  });

  final DayKind kind;
  final TimeOfDay start;
  final TimeOfDay end;

  DaySpec copyWith({DayKind? kind, TimeOfDay? start, TimeOfDay? end}) =>
      DaySpec(
        kind: kind ?? this.kind,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}

String dayKindLabel(DayKind k) {
  switch (k) {
    case DayKind.present:
      return 'Saapuu';
    case DayKind.poissa:
      return 'Poissaolo';
    case DayKind.sairas:
      return 'Sairaus';
    case DayKind.tyhja:
      return 'Tyhjä';
  }
}

({Color bg, Color fg, IconData icon}) dayKindStyle(DayKind k) {
  switch (k) {
    case DayKind.present:
      return (
        bg: AppColors.primaryContainer,
        fg: AppColors.primary,
        icon: Icons.check_circle,
      );
    case DayKind.poissa:
      return (
        bg: const Color(0xFFFEE2E2),
        fg: const Color(0xFFDC2626),
        icon: Icons.event_busy,
      );
    case DayKind.sairas:
      return (
        bg: const Color(0xFFFEF3C7),
        fg: const Color(0xFFD97706),
        icon: Icons.healing,
      );
    case DayKind.tyhja:
      return (
        bg: const Color(0xFFF4F6F7),
        fg: const Color(0xFF6B7280),
        icon: Icons.do_not_disturb_alt,
      );
  }
}

/// Avaa bottom-sheet jossa käyttäjä valitsee mihin tilaan päivä siirtyy
/// kun Switch on OFF. Palauttaa null jos käyttäjä peruu.
Future<DayKind?> showDayOffPicker(BuildContext context) {
  return showModalBottomSheet<DayKind>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final k in [DayKind.poissa, DayKind.sairas, DayKind.tyhja])
            _OffOption(kind: k, onTap: () => Navigator.pop(ctx, k)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _OffOption extends StatelessWidget {
  const _OffOption({required this.kind, required this.onTap});
  final DayKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = dayKindStyle(kind);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: style.bg,
        child: Icon(style.icon, color: style.fg),
      ),
      title: Text(dayKindLabel(kind)),
      onTap: onTap,
    );
  }
}

/// Yhtenäinen päiväkortti.
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    this.shortBadge,
    required this.title,
    this.subtitle,
    required this.spec,
    required this.onChanged,
    this.body,
    this.timesEditable = true,
  });

  /// Lyhyt tunnus vasempaan palikkaan (esim. "Ma", "Ti", "12"). Null jos ei näytetä.
  final String? shortBadge;

  /// Päärivi: päivän nimi tai päivämäärä.
  final String title;

  /// Mahdollinen aliotsikko (esim. ryhmän nimi).
  final String? subtitle;

  final DaySpec spec;
  final ValueChanged<DaySpec> onChanged;

  /// Vaihtoehtoinen sisältö (esim. lapset checkboxeilla yksittäispäivän
  /// muokkauksessa). Renderöidään sekä Saapuu- että OFF-tiloissa kun annettu.
  final Widget? body;

  /// Sallitaanko aikojen muokkaus (false = vain poissaolomerkintä).
  final bool timesEditable;

  Future<void> _onSwitchChanged(BuildContext context, bool v) async {
    if (v) {
      if (!timesEditable) return; // ei voi palauttaa present-tilaan lukitulla päivällä
      onChanged(spec.copyWith(kind: DayKind.present));
    } else {
      final picked = await showDayOffPicker(context);
      if (picked != null) onChanged(spec.copyWith(kind: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPresent = spec.kind == DayKind.present;
    final style = dayKindStyle(spec.kind);

    final cardBg = isPresent ? Colors.white : style.bg.withValues(alpha: 0.35);
    final borderColor = isPresent
        ? const Color(0xFFE5E7EB)
        : style.fg.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                if (shortBadge != null) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: style.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      shortBadge!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: style.fg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isPresent)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: style.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        dayKindLabel(spec.kind),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: style.fg,
                        ),
                      ),
                    ),
                  ),
                Switch(
                  value: isPresent,
                  activeThumbColor: AppColors.primary,
                  // lukittu+poissa: täysin disabloitu; lukittu+present: voi merkitä poissa
                  onChanged: (!timesEditable && !isPresent)
                      ? null
                      : (v) => _onSwitchChanged(context, v),
                ),
              ],
            ),
          ),
          if (body != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: body!,
            ),
          if (isPresent && body == null && timesEditable)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _TimePickerRow(
                start: spec.start,
                end: spec.end,
                onStartChanged: (v) =>
                    onChanged(spec.copyWith(start: v)),
                onEndChanged: (v) =>
                    onChanged(spec.copyWith(end: v)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimePickerRow extends StatelessWidget {
  const _TimePickerRow({
    required this.start,
    required this.end,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  final TimeOfDay start;
  final TimeOfDay end;
  final ValueChanged<TimeOfDay> onStartChanged;
  final ValueChanged<TimeOfDay> onEndChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TimePickerField(
            label: 'Alkaa',
            value: start,
            onChanged: onStartChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TimePickerField(
            label: 'Päättyy',
            value: end,
            onChanged: onEndChanged,
          ),
        ),
      ],
    );
  }
}

class TimePickerField extends StatelessWidget {
  const TimePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  static String hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

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
        child: Text(hhmm(value)),
      ),
    );
  }
}
