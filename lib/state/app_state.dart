import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/attachments_api.dart';
import '../api/calendar_api.dart';
import '../api/evaka_client.dart';
import '../api/messages_api.dart';
import '../api/models/calendar_event.dart';
import '../api/models/questionnaire.dart';
import '../api/models/recipients.dart';
import '../api/models/reservations.dart';
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

final messagesPageProvider = StateProvider<int>((ref) => 1);

final receivedThreadsProvider =
    FutureProvider<ThreadsPage>((ref) async {
  final page = ref.watch(messagesPageProvider);
  return ref.watch(messagesApiProvider).getReceivedThreads(page: page);
});

final messagesUnreadCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(messagesApiProvider).getUnreadCount();
});

final messageRecipientsProvider =
    FutureProvider<MessageRecipientsResponse>((ref) async {
  return ref.watch(messagesApiProvider).getRecipients();
});

final reservationsApiProvider = Provider<ReservationsApi>((ref) {
  return ReservationsApi(ref.watch(evakaClientProvider));
});

final reservationsProvider =
    FutureProvider<ReservationsResponse>((ref) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final to = from.add(const Duration(days: 60));
  return ref.watch(reservationsApiProvider).getReservations(from: from, to: to);
});

final calendarApiProvider = Provider<CalendarApi>((ref) {
  return CalendarApi(ref.watch(evakaClientProvider));
});

final calendarEventsProvider =
    FutureProvider<List<CalendarEvent>>((ref) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 180));
  return ref
      .watch(calendarApiProvider)
      .getEvents(start: today, end: end);
});

final questionnaireApiProvider = Provider<QuestionnaireApi>((ref) {
  return QuestionnaireApi(ref.watch(evakaClientProvider));
});

final activeQuestionnairesProvider =
    FutureProvider<List<HolidayQuestionnaire>>((ref) async {
  return ref.watch(questionnaireApiProvider).getActiveQuestionnaires();
});
