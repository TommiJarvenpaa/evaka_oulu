import 'endpoints.dart';
import 'evaka_client.dart';
import 'json_utils.dart';
import 'models/message.dart';

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

  Future<ThreadsPage> getReceivedThreads({int page = 1}) async {
    final resp = await _client.dio.get(
      EvakaEndpoints.messagesReceived,
      queryParameters: {'page': page},
    );
    final data = asMap(resp.data);
    final threads = (data['data'] as List)
        .cast<Map<String, dynamic>>()
        .map(MessageThread.fromJson)
        .toList();
    return ThreadsPage(
      threads: threads,
      total: (data['total'] as num).toInt(),
      pages: (data['pages'] as num).toInt(),
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
      data: {
        'content': content,
        'recipientAccountIds': recipientAccountIds,
      },
    );
  }
}
