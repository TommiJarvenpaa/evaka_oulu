import 'package:dio/dio.dart';

import 'endpoints.dart';
import 'evaka_client.dart';
import 'json_utils.dart';
import 'models/message.dart';
import 'models/recipients.dart';

class ThreadsPage {
  ThreadsPage({
    required this.threads,
    required this.total,
    required this.pages,
    required this.page,
  });

  final List<MessageThread> threads;
  final int total;
  final int pages;
  final int page;
}

class MessagesApi {
  MessagesApi(this._client);

  final EvakaClient _client;

  static const int _kPageSize = 10;

  Future<ThreadsPage> getReceivedThreads({int page = 1}) async {
    final resp = await _client.dio.get(
      EvakaEndpoints.messagesReceived,
      queryParameters: {'page': page, 'pageSize': _kPageSize},
    );
    return _parseThreadsPage(resp.data, page);
  }

  ThreadsPage _parseThreadsPage(dynamic raw, int page) {
    final data = asMap(raw);

    // Defensiivinen parsinta: backendin vastaus voi olla 400/404-virhe JSON-
    // muodossa (esim. {"error": "...", "status": 400}) jolloin "data"-kenttää
    // ei ole. Heitetään silloin selkeä virhe sen sijaan että ColdCast-crashaisi.
    final dataRaw = data['data'];
    if (dataRaw is! List) {
      // Yritetään lukea backendin oma virhekenttä jos olemassa
      final err = data['error'] ?? data['message'] ?? data['status'];
      throw FormatException(
        err == null
            ? 'Odotettiin "data"-listaa, sai ${dataRaw.runtimeType}'
            : 'Palvelinvirhe: $err',
      );
    }
    final threads = dataRaw
        .cast<Map<String, dynamic>>()
        .map(MessageThread.fromJson)
        .toList();
    return ThreadsPage(
      threads: threads,
      total: (data['total'] as num?)?.toInt() ?? threads.length,
      pages: (data['pages'] as num?)?.toInt() ?? 1,
      page: page,
    );
  }

  Future<int> getUnreadCount() async {
    final resp = await _client.dio.get(EvakaEndpoints.messagesUnreadCount);
    final raw = resp.data;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.parse(raw.trim());
    throw FormatException('Odotettiin lukua, saatiin ${raw.runtimeType}');
  }

  Future<void> markThreadRead(String threadId) async {
    await _client.dio.put(EvakaEndpoints.markThreadRead(threadId));
  }

  Future<void> archiveThread(String threadId) async {
    // eVaka backend käyttää PUT:ia arkistointiin
    await _client.dio.put(EvakaEndpoints.archiveThread(threadId));
  }

  Future<String> getMyAccountId() async {
    final resp = await _client.dio.get(EvakaEndpoints.messagesMyAccount);
    return asMap(resp.data)['accountId'] as String;
  }

  Future<void> replyToThread({
    required String threadId,
    required String content,
    required List<String> recipientAccountIds,
  }) async {
    await _client.dio.post(
      EvakaEndpoints.replyToThread(threadId),
      data: {'content': content, 'recipientAccountIds': recipientAccountIds},
    );
  }

  Future<MessageRecipientsResponse> getRecipients() async {
    final resp = await _client.dio.get(EvakaEndpoints.messagesRecipients);
    return MessageRecipientsResponse.fromJson(asMap(resp.data));
  }

  /// Luo uusi viestisäie. Palauttaa luodun säikeen id:n.
  ///
  /// Citizen-puolen `CitizenMessageBody` ei tue `urgent`/`sensitive`-lippuja —
  /// vain henkilöstö voi merkitä lähettämänsä viestin näiksi.
  Future<String> createThread({
    required String title,
    required String content,
    required List<String> recipientAccountIds,
    required List<String> childIds,
    List<String> attachmentIds = const [],
  }) async {
    final resp = await _client.dio.post(
      EvakaEndpoints.messagesNew,
      data: {
        'title': title,
        'content': content,
        'recipients': recipientAccountIds,
        'children': childIds,
        'attachmentIds': attachmentIds,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final data = resp.data;
    if (data is String) return data;
    if (data is Map && data['id'] is String) return data['id'] as String;
    // Joissain versioissa palautuu pelkkä id stringinä quoteilla
    return data.toString();
  }
}
