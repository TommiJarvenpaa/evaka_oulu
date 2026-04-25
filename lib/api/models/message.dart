class MessageThread {
  MessageThread({
    required this.id,
    required this.title,
    required this.urgent,
    required this.sensitive,
    required this.type,
    required this.messageType,
    required this.messages,
  });

  final String id;
  final String title;
  final bool urgent;
  final bool sensitive;
  final String type;
  final String messageType;
  final List<Message> messages;

  int get unreadCount => messages.where((m) => m.readAt == null).length;
  bool get hasUnread => unreadCount > 0;

  DateTime get latestSentAt => messages
      .map((m) => m.sentAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  Message get latestMessage => messages.reduce(
    (a, b) => a.sentAt.isAfter(b.sentAt) ? a : b,
  );

  factory MessageThread.fromJson(Map<String, dynamic> json) {
    final messages = (json['messages'] as List)
        .cast<Map<String, dynamic>>()
        .map(Message.fromJson)
        .toList();
    return MessageThread(
      id: json['id'] as String,
      title: (json['title'] ?? '') as String,
      urgent: (json['urgent'] ?? false) as bool,
      sensitive: (json['sensitive'] ?? false) as bool,
      type: (json['type'] ?? '') as String,
      messageType: (json['messageType'] ?? '') as String,
      messages: messages,
    );
  }
}

class Message {
  Message({
    required this.id,
    required this.threadId,
    required this.sender,
    required this.recipients,
    required this.sentAt,
    required this.content,
    required this.readAt,
    required this.attachments,
  });

  final String id;
  final String threadId;
  final MessageSender sender;
  final List<MessageSender> recipients;
  final DateTime sentAt;
  final String content;
  final DateTime? readAt;
  final List<Attachment> attachments;

  bool get isUnread => readAt == null;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      sender: MessageSender.fromJson(json['sender'] as Map<String, dynamic>),
      recipients: (json['recipients'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MessageSender.fromJson)
          .toList(),
      sentAt: DateTime.parse(json['sentAt'] as String),
      content: (json['content'] ?? '') as String,
      readAt: json['readAt'] == null
          ? null
          : DateTime.parse(json['readAt'] as String),
      attachments: (json['attachments'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Attachment.fromJson)
          .toList(),
    );
  }
}

class MessageSender {
  MessageSender({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;

  /// "MUNICIPAL" | "PERSONAL" | "GROUP" | "CITIZEN"
  final String type;

  factory MessageSender.fromJson(Map<String, dynamic> json) {
    return MessageSender(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      type: (json['type'] ?? '') as String,
    );
  }
}

class Attachment {
  Attachment({
    required this.id,
    required this.name,
    required this.contentType,
  });

  final String id;
  final String name;
  final String contentType;

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      contentType: (json['contentType'] ?? '') as String,
    );
  }
}
