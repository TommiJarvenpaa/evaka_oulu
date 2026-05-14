/// Vastaanottajalistauksen mallit. eVakan citizen-API palauttaa kaksi listaa:
/// 1. `messageAccounts` — kaikki message-accountit joille käyttäjä voi
///    *lähettää* viestin (yhdistettynä metatieto kuten poissaoloaika)
/// 2. `childrenToMessageAccounts` — per lapsi lista accountIdeistä joille
///    voi lähettää uuden viestin (`newMessage`) ja joille voi vastata (`reply`)
///
/// UI:n logiikka: käyttäjä valitsee lapsen → näytetään ne accountit jotka
/// löytyvät kyseisen lapsen `newMessage`-joukosta.
class MessageRecipientsResponse {
  MessageRecipientsResponse({
    required this.messageAccounts,
    required this.childrenToMessageAccounts,
  });

  final List<MessageAccountWithPresence> messageAccounts;
  final List<ChildMessageAccountAccess> childrenToMessageAccounts;

  factory MessageRecipientsResponse.fromJson(Map<String, dynamic> json) {
    return MessageRecipientsResponse(
      messageAccounts: (json['messageAccounts'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MessageAccountWithPresence.fromJson)
          .toList(),
      childrenToMessageAccounts:
          (json['childrenToMessageAccounts'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .map(ChildMessageAccountAccess.fromJson)
              .toList(),
    );
  }
}

class MessageAccountWithPresence {
  MessageAccountWithPresence({
    required this.account,
    required this.outOfOffice,
  });

  final MessageAccount account;

  /// null = paikalla, muuten poissaolojakso
  final ({DateTime start, DateTime end})? outOfOffice;

  factory MessageAccountWithPresence.fromJson(Map<String, dynamic> json) {
    final ooo = json['outOfOffice'] as Map<String, dynamic>?;
    return MessageAccountWithPresence(
      account: MessageAccount.fromJson(json['account'] as Map<String, dynamic>),
      outOfOffice: ooo == null
          ? null
          : (
              start: DateTime.parse(ooo['start'] as String),
              end: DateTime.parse(ooo['end'] as String),
            ),
    );
  }
}

class MessageAccount {
  MessageAccount({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String name;

  /// "PERSONAL" | "GROUP" | "MUNICIPAL" | "SERVICE_WORKER"
  final String type;

  factory MessageAccount.fromJson(Map<String, dynamic> json) {
    return MessageAccount(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      type: (json['type'] ?? '') as String,
    );
  }
}

/// Per lapsi: mille accounteille voi lähettää uuden viestin / vastata.
class ChildMessageAccountAccess {
  ChildMessageAccountAccess({
    required this.childId,
    required this.newMessageAccountIds,
    required this.replyAccountIds,
  });

  /// null = ei lapsikohtainen (esim. kunnan yhteiset accountit)
  final String? childId;
  final Set<String> newMessageAccountIds;
  final Set<String> replyAccountIds;

  factory ChildMessageAccountAccess.fromJson(Map<String, dynamic> json) {
    return ChildMessageAccountAccess(
      childId: json['childId'] as String?,
      newMessageAccountIds: ((json['newMessage'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      replyAccountIds:
          ((json['reply'] as List?) ?? const []).cast<String>().toSet(),
    );
  }
}
