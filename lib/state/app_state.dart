import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/attachments_api.dart';
import '../api/calendar_api.dart';
import '../api/evaka_client.dart';
import '../api/messages_api.dart';
import '../api/models/calendar_event.dart';
import '../api/models/message.dart';
import '../api/models/questionnaire.dart';
import '../api/models/recipients.dart';
import '../api/models/reservations.dart';
import '../api/notifications_api.dart';
import '../api/questionnaire_api.dart';
import '../api/reservations_api.dart';
import '../auth/auth_service.dart';
import '../auth/secure_storage.dart';

final evakaClientProvider = Provider<EvakaClient>((ref) {
  return EvakaClient.create(ref.watch(secureStorageProvider));
});

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage();
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(evakaClientProvider),
    ref.watch(secureStorageProvider),
  );
});

final authStatusProvider = FutureProvider<AuthStatus>((ref) async {
  return ref.watch(authServiceProvider).restore();
});

final messagesApiProvider = Provider<MessagesApi>((ref) {
  return MessagesApi(ref.watch(evakaClientProvider));
});

final attachmentsApiProvider = Provider<AttachmentsApi>((ref) {
  return AttachmentsApi(ref.watch(evakaClientProvider));
});

final myMessageAccountIdProvider = FutureProvider<String>((ref) async {
  return ref.watch(messagesApiProvider).getMyAccountId();
});

/// Tilakomponentit infinite-scroll-listalle. Pidetään muistissa kaikki
/// tähän asti ladatut säikeet + tieto siitä onko lisää sivuja saatavilla.
class ReceivedThreadsState {
  const ReceivedThreadsState({
    required this.threads,
    required this.currentPage,
    required this.totalPages,
    required this.total,
    this.loadingMore = false,
  });

  final List<MessageThread> threads;
  final int currentPage;
  final int totalPages;
  final int total;
  final bool loadingMore;

  bool get hasMore => currentPage < totalPages;

  ReceivedThreadsState copyWith({
    List<MessageThread>? threads,
    int? currentPage,
    int? totalPages,
    int? total,
    bool? loadingMore,
  }) => ReceivedThreadsState(
    threads: threads ?? this.threads,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

class ReceivedThreadsNotifier extends AsyncNotifier<ReceivedThreadsState> {
  @override
  Future<ReceivedThreadsState> build() async {
    final first = await ref
        .read(messagesApiProvider)
        .getReceivedThreads(page: 1);
    return ReceivedThreadsState(
      threads: first.threads,
      currentPage: 1,
      totalPages: first.pages,
      total: first.total,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.hasMore) return;
    if (current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final nextPage = current.currentPage + 1;
      final next = await ref
          .read(messagesApiProvider)
          .getReceivedThreads(page: nextPage);
      state = AsyncData(
        current.copyWith(
          threads: [...current.threads, ...next.threads],
          currentPage: nextPage,
          totalPages: next.pages,
          total: next.total,
          loadingMore: false,
        ),
      );
    } catch (e) {
      // Lopeta lataus-tila; säilytä jo ladatut säikeet. Käyttäjä voi yrittää
      // uudelleen rullaamalla loppuun tai pull-to-refreshilla.
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Poista yksittäinen säie listalta ilman uudelleenhakua (esim. arkistoinnin
  /// jälkeen). Säilyttää käyttäjän scroll-position.
  void removeThread(String threadId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final filtered = current.threads.where((t) => t.id != threadId).toList();
    state = AsyncData(
      current.copyWith(
        threads: filtered,
        total: (current.total - 1).clamp(0, 1 << 31),
      ),
    );
  }
}

final receivedThreadsProvider =
    AsyncNotifierProvider<ReceivedThreadsNotifier, ReceivedThreadsState>(
      ReceivedThreadsNotifier.new,
    );

/// Lähetetyt-näkymä: Oulun eVaka ei tarjoa erillistä `/messages/sent`-
/// endpointtia (lisätty Espoon masteriin forkin erkanemisen jälkeen). Toteutus
/// hakee korkeintaan [_kSentScanPages] sivua received-listasta ja suodattaa
/// säikeet joissa käyttäjä on lähettäjänä jossakin viestissä. Tämä riittää
/// useimmille käyttäjille — yli ~100 säikeen historiaa ei näytetä.
const int _kSentScanPages = 10;

final sentThreadsProvider = FutureProvider<ThreadsPage>((ref) async {
  final api = ref.watch(messagesApiProvider);
  final myAccountId = await ref.watch(myMessageAccountIdProvider.future);

  final allThreads = <MessageThread>[];
  int pageNum = 1;
  int totalPages = 1;
  while (pageNum <= totalPages && pageNum <= _kSentScanPages) {
    final result = await api.getReceivedThreads(page: pageNum);
    totalPages = result.pages;
    allThreads.addAll(result.threads);
    pageNum++;
  }

  // Säikeet joissa minä olen lähettäjänä jossakin viestissä
  final sent = allThreads
      .where((t) => t.messages.any((m) => m.sender.id == myAccountId))
      .toList();

  return ThreadsPage(threads: sent, total: sent.length, pages: 1, page: 1);
});

final messagesUnreadCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(messagesApiProvider).getUnreadCount();
});

final messageRecipientsProvider = FutureProvider<MessageRecipientsResponse>((
  ref,
) async {
  return ref.watch(messagesApiProvider).getRecipients();
});

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  return NotificationsApi(ref.watch(evakaClientProvider));
});

final applicationNotificationCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(notificationsApiProvider).getApplicationNotificationCount();
});

final expiringIncomeProvider = FutureProvider<List<DateTime>>((ref) async {
  return ref.watch(notificationsApiProvider).getExpiringIncomeDates();
});

final dailyServiceTimeNotificationsProvider =
    FutureProvider<List<DailyServiceTimeNotification>>((ref) async {
      return ref
          .watch(notificationsApiProvider)
          .getDailyServiceTimeNotifications();
    });

final reservationsApiProvider = Provider<ReservationsApi>((ref) {
  return ReservationsApi(ref.watch(evakaClientProvider));
});

final reservationsProvider = FutureProvider<ReservationsResponse>((ref) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final to = from.add(const Duration(days: 60));
  return ref.watch(reservationsApiProvider).getReservations(from: from, to: to);
});

/// Menneiden päivien toteutuneet hoitoajat — autoDispose, koska tätä avataan
/// erillisestä historianäkymästä eikä tarvitse pitää muistissa kun se on
/// suljettu. Hakee 90 päivää taaksepäin tähän päivään asti.
final attendanceHistoryProvider =
    FutureProvider.autoDispose<ReservationsResponse>((ref) async {
  final now = DateTime.now();
  final to = DateTime(now.year, now.month, now.day);
  final from = to.subtract(const Duration(days: 90));
  return ref.watch(reservationsApiProvider).getReservations(from: from, to: to);
});

final calendarApiProvider = Provider<CalendarApi>((ref) {
  return CalendarApi(ref.watch(evakaClientProvider));
});

final calendarEventsProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 180));
  return ref.watch(calendarApiProvider).getEvents(start: today, end: end);
});

final questionnaireApiProvider = Provider<QuestionnaireApi>((ref) {
  return QuestionnaireApi(ref.watch(evakaClientProvider));
});

final activeQuestionnairesProvider = FutureProvider<List<HolidayQuestionnaire>>(
  (ref) async {
    return ref.watch(questionnaireApiProvider).getActiveQuestionnaires();
  },
);
