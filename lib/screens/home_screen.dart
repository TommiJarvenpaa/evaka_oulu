import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/questionnaire.dart';
import '../state/app_state.dart';
import 'attendance_screen.dart';
import 'calendar_screen.dart';
import 'messages_screen.dart';
import 'questionnaire_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  static const _tabs = [MessagesScreen(), AttendanceScreen(), CalendarScreen()];

  @override
  Widget build(BuildContext context) {
    final questionnairesAsync = ref.watch(activeQuestionnairesProvider);
    final activeQuestionnaires =
        questionnairesAsync.asData?.value
            .where((q) => q.hasActiveQuestionnaire)
            .toList() ??
        [];

    // Etusivun bannerit — näytetään aina kun on dataa, tab-riippumattomasti
    final expiringIncome =
        ref.watch(expiringIncomeProvider).asData?.value ?? const <DateTime>[];
    final appNotifCount =
        ref.watch(applicationNotificationCountProvider).asData?.value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('eVaka Oulu'),
        actions: [
          IconButton(
            tooltip: 'Kirjaudu ulos',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authServiceProvider).logout();
              ref.invalidate(authStatusProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          for (final q in activeQuestionnaires)
            _QuestionnaireBanner(questionnaire: q),
          if (expiringIncome.isNotEmpty)
            _IncomeExpiringBanner(dates: expiringIncome),
          if (appNotifCount > 0)
            _ApplicationNotificationsBanner(count: appNotifCount),
          Expanded(child: _tabs[_index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mail_outline),
            selectedIcon: Icon(Icons.mail),
            label: 'Viestit',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: 'Läsnäolo',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Kalenteri',
          ),
        ],
      ),
    );
  }
}

/// Yleinen banner-pohja jonka muut käyttävät — ikoni, teksti, väri.
/// Toistaiseksi vain informatiivinen, ei navigointia: kohdenäyttöjä
/// (Tulotiedot, Hakemukset) ei vielä ole.
class _HomeBanner extends StatelessWidget {
  const _HomeBanner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeExpiringBanner extends StatelessWidget {
  const _IncomeExpiringBanner({required this.dates});

  final List<DateTime> dates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Näytetään aikaisin vanheneva
    final earliest = [...dates]..sort();
    final d = earliest.first;
    final formatted = DateFormat('d.M.yyyy').format(d);
    final text = dates.length > 1
        ? 'Tulotiedot vanhenevat ($formatted alkaen, ${dates.length} kpl)'
        : 'Tulotiedot vanhenevat $formatted';
    return _HomeBanner(
      icon: Icons.payments_outlined,
      text: text,
      background: theme.colorScheme.tertiaryContainer,
      foreground: theme.colorScheme.onTertiaryContainer,
      // Ei navigointia — tulotiedot-näyttöä ei vielä ole. Banner toimii muistutuksena.
    );
  }
}

class _ApplicationNotificationsBanner extends StatelessWidget {
  const _ApplicationNotificationsBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = count == 1
        ? 'Hakemuksessasi on uutta tietoa'
        : 'Hakemuksissasi on $count uutta tietoa';
    return _HomeBanner(
      icon: Icons.assignment_outlined,
      text: text,
      background: theme.colorScheme.secondaryContainer,
      foreground: theme.colorScheme.onSecondaryContainer,
      // Hakemukset-näyttöä ei vielä ole; ei navigointia.
    );
  }
}

class _QuestionnaireBanner extends StatelessWidget {
  const _QuestionnaireBanner({required this.questionnaire});

  final HolidayQuestionnaire questionnaire;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = questionnaire.questionnaire;
    final hasAnswered = questionnaire.previousAnswers.isNotEmpty;

    return Material(
      color: hasAnswered
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QuestionnaireScreen(questionnaire: questionnaire),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                hasAnswered ? Icons.check_circle_outline : Icons.campaign,
                size: 20,
                color: hasAnswered
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q.titleFi.isNotEmpty ? q.titleFi : 'Poissaolokysely',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hasAnswered
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: hasAnswered
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onErrorContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
