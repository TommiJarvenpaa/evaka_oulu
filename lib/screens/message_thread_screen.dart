import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../api/models/message.dart';
import '../state/app_state.dart';

class MessageThreadScreen extends ConsumerStatefulWidget {
  const MessageThreadScreen({super.key, required this.thread});

  final MessageThread thread;

  @override
  ConsumerState<MessageThreadScreen> createState() =>
      _MessageThreadScreenState();
}

class _MessageThreadScreenState extends ConsumerState<MessageThreadScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.thread.hasUnread) {
      _markRead();
    }
  }

  Future<void> _markRead() async {
    try {
      await ref
          .read(messagesApiProvider)
          .markThreadRead(widget.thread.id);
      if (!mounted) return;
      ref.invalidate(receivedThreadsProvider);
      ref.invalidate(messagesUnreadCountProvider);
    } catch (_) {
      // Hiljainen: merkintä yritetään uudelleen seuraavalla avauksella
    }
  }

  Future<void> _archive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arkistoidaanko keskustelu?'),
        content: Text('"${widget.thread.title}" siirtyy arkistoon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Peruuta'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Arkistoi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await ref.read(messagesApiProvider).archiveThread(widget.thread.id);
      if (!mounted) return;
      ref.invalidate(receivedThreadsProvider);
      ref.invalidate(messagesUnreadCountProvider);
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Keskustelu arkistoitu')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Arkistointi epäonnistui: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final messages = [...thread.messages]
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          thread.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Arkistoi',
            icon: const Icon(Icons.archive_outlined),
            onPressed: _archive,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: messages.length,
              separatorBuilder: (_, _) => const Divider(height: 24),
              itemBuilder: (context, i) => _MessageTile(message: messages[i]),
            ),
          ),
          // Näytä reply-composer vain jos tiedämme lähettäjän (eli joku muu kuin me)
          if (thread.messageType == 'MESSAGE')
            _ReplyComposer(thread: thread),
        ],
      ),
      ),
    );
  }
}

class _ReplyComposer extends ConsumerStatefulWidget {
  const _ReplyComposer({required this.thread});

  final MessageThread thread;

  @override
  ConsumerState<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends ConsumerState<_ReplyComposer> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    setState(() => _sending = true);
    try {
      final myId = await ref.read(myMessageAccountIdProvider.future);
      final recipients = _resolveRecipients(myId);
      if (recipients.isEmpty) {
        throw Exception('Vastaanottajaa ei löytynyt');
      }
      await ref.read(messagesApiProvider).replyToThread(
            threadId: widget.thread.id,
            content: content,
            recipientAccountIds: recipients,
          );
      _controller.clear();
      if (!mounted) return;
      setState(() => _expanded = false);
      ref.invalidate(receivedThreadsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vastaus lähetetty')),
      );
      // Vieritetään takaisin listaan — thread avautuu uudelleen refreshin jälkeen
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lähetys epäonnistui: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  List<String> _resolveRecipients(String myAccountId) {
    // eVakan citizen-frontendin logiikkaa mukaillen:
    // - ensimmäisen viestin lähettäjä (jos ei me)
    // - plus ensimmäisen viestin vastaanottajat (paitsi me)
    final sorted = [...widget.thread.messages]
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final first = sorted.first;
    final ids = <String>{};
    if (first.sender.id != myAccountId) ids.add(first.sender.id);
    for (final r in first.recipients) {
      if (r.id != myAccountId) ids.add(r.id);
    }
    return ids.toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_expanded) {
      return Material(
        elevation: 2,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.reply),
                label: const Text('Vastaa'),
                onPressed: () => setState(() => _expanded = true),
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                maxLines: 4,
                autofocus: true,
                enabled: !_sending,
                decoration: InputDecoration(
                  hintText: 'Kirjoita vastaus…',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _sending
                          ? null
                          : () => setState(() => _expanded = false),
                      child: const Text('Peruuta'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: _sending
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Lähetä'),
                      onPressed: _sending ? null : _send,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageTile extends ConsumerWidget {
  const _MessageTile({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final senderName = message.sender.name.isEmpty
        ? '(tuntematon)'
        : message.sender.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  senderName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                DateFormat('d.M.yyyy HH:mm').format(message.sentAt),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            message.content,
            style: theme.textTheme.bodyMedium,
          ),
          if (message.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Liitteet:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            ...message.attachments.map(
              (a) => _AttachmentTile(attachment: a),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentTile extends ConsumerStatefulWidget {
  const _AttachmentTile({required this.attachment});

  final Attachment attachment;

  @override
  ConsumerState<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends ConsumerState<_AttachmentTile> {
  bool _loading = false;

  Future<void> _openAttachment() async {
    setState(() => _loading = true);
    try {
      final path = await ref
          .read(attachmentsApiProvider)
          .download(widget.attachment);
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Avaus epäonnistui: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lataus epäonnistui: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: _loading ? null : _openAttachment,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.attach_file,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.attachment.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
