/// Kaikki eVaka-API-reitit yhdessä paikassa.
///
/// Todennettu Firefox DevToolsin HAR-viennillä 2026-04-24 (session-1.har)
/// muut paitsi viestin lähetys ja poissaolo, jotka on päätelty Espoon
/// repon pohjalta ja merkitty `// TODO:` -kommentilla.
class EvakaEndpoints {
  EvakaEndpoints._();

  static const String baseUrl = 'https://varhaiskasvatus.ouka.fi';

  // --- Autentikointi ---
  static const String weakLogin = '/api/citizen/auth/weak-login';
  static const String authStatus = '/api/citizen/auth/status';
  static const String logout = '/api/citizen/auth/logout';

  // --- Perustiedot ---
  static const String children = '/api/citizen/children';

  // --- Viestit ---
  // HUOM: Oulun eVaka-fork ei sisällä /messages/sent-endpointtia (lisätty
  // Espoon masteriin Oulun forkin jälkeen). Lähetetyt-näkymä toteutetaan
  // client-puolella suodattamalla received-listasta.
  static const String messagesMyAccount = '/api/citizen/messages/my-account';
  static const String messagesRecipients = '/api/citizen/messages/recipients';
  static const String messagesReceived = '/api/citizen/messages/received';
  static const String messagesUnreadCount =
      '/api/citizen/messages/unread-count';
  static const String messagesNew = '/api/citizen/messages';
  static String markThreadRead(String threadId) =>
      '/api/citizen/messages/threads/$threadId/read';
  static String replyToThread(String threadId) =>
      '/api/citizen/messages/reply-to/$threadId';
  static String archiveThread(String threadId) =>
      '/api/citizen/messages/threads/$threadId/archive';

  // --- Viestin liitteet ---
  static const String messageAttachmentUpload =
      '/api/citizen/attachments/messages';
  static String attachmentDelete(String id) => '/api/citizen/attachments/$id';

  // Lapsen kuva
  static String childImage(String imageId) =>
      '/api/citizen/child-images/$imageId';

  // --- Varaukset (reservations) ---
  static const String reservations = '/api/citizen/reservations';
  static const String absences = '/api/citizen/absences';
  static const String preschoolOperationalDates =
      '/api/citizen/preschool-operational-dates';

  // --- Kalenteri ---
  static const String calendarEvents = '/api/citizen/calendar-events';
  static const String calendarEventReservation =
      '/api/citizen/calendar-event/reservation';

  // --- Liitteet ---
  static String attachmentDownload(String id, String filename) =>
      '/api/citizen/attachments/$id/download/${Uri.encodeComponent(filename)}';

  // --- Loma-ajat ---
  static const String holidayPeriod = '/api/citizen/holiday-period';
  static const String holidayPeriodQuestionnaire =
      '/api/citizen/holiday-period/questionnaire';
  static String questionnaireOpenRange(String id) =>
      '/api/citizen/holiday-period/questionnaire/open-range/$id';
  static String questionnaireFixedPeriod(String id) =>
      '/api/citizen/holiday-period/questionnaire/fixed-period/$id';

  // --- Etusivun badget ---
  static const String pedagogicalDocumentsUnreadCount =
      '/api/citizen/pedagogical-documents/unread-count';
  static const String childDocumentsUnreadCount =
      '/api/citizen/child-documents/unread-count';
  static const String childDocumentsUnanswered =
      '/api/citizen/child-documents/unanswered';
  static const String applicationNotifications =
      '/api/citizen/applications/by-guardian/notifications';
  static const String dailyServiceTimeNotifications =
      '/api/citizen/daily-service-time-notifications';
  static const String dailyServiceTimeNotificationsDismiss =
      '/api/citizen/daily-service-time-notifications/dismiss';
  static const String incomeExpiring = '/api/citizen/income/expiring';
}
