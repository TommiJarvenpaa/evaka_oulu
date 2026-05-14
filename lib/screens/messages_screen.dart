import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/messages_api.dart';
import '../api/models/message.dart';
import '../main.dart' show AppColors;
import '../state/app_state.dart';
import 'compose_message_screen.dart';
import 'message_thread_screen.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threadsAsync = ref.watch(receivedThreadsProvider);

    return Scaffold(
      // Käytämme Scaffoldia jotta saamme FAB:in tabin sisälle
      backgroundColor: Colors.transparent,
      body: threadsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Viestien haku epäonnistui:\n$e',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(receivedThreadsProvider),
                  child: const Text('Yritä uudelleen'),
                ),
              ],
            ),
          ),
        ),
        data: (page) {
          if (page.threads.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(receivedThreadsProvider);
                ref.invalidate(messagesUnreadCountProvider);
                await ref.read(receivedThreadsProvider.future);
              },
              child: ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text('Ei viestejä.')),
                ],
              ),
            );
          }
          return Column(
            children: [
              if (page.pages > 1) _PaginationBar(page: page),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(receivedThreadsProvider);
                    ref.invalidate(messagesUnreadCountProvider);
                    await ref.read(receivedThreadsProvider.future);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                    itemCount: page.threads.length,
                    itemBuilder: (context, i) =>
                        _ThreadTile(thread: page.threads[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit),
        label: const Text('Uusi viesti'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ComposeMessageScreen()),
          );
        },
      ),
    );
  }
}

class _PaginationBar extends ConsumerWidget {
  const _PaginationBar({required this.page});

  final ThreadsPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canPrev = page.page > 1;
    final canNext = page.page < page.pages;

    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.chevron_left),
                onPressed: canPrev
                    ? () => ref.read(messagesPageProvider.notifier).state--
                    : null,
                tooltip: 'Edellinen',
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sivu ${page.page} / ${page.pages}',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '${page.total} viestiä yhteensä',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.chevron_right),
                onPressed: canNext
                    ? () => ref.read(messagesPageProvider.notifier).state++
                    : null,
                tooltip: 'Seuraava',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.thread});

  final MessageThread thread;

  Future<bool?> _confirmArchive(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arkistoidaanko keskustelu?'),
        content: Text('"${thread.title}" siirtyy arkistoon.'),
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
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final latest = thread.latestMessage;
    final senderName = latest.sender.name.isEmpty
        ? '(tuntematon)'
        : latest.sender.name;

    return Dismissible(
      key: ValueKey('thread_${thread.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final ok = await _confirmArchive(context);
        if (ok != true) return false;
        try {
          await ref.read(messagesApiProvider).archiveThread(thread.id);
          return true;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Arkistointi epäonnistui: $e')),
            );
          }
          return false;
        }
      },
      onDismissed: (_) {
        ref.invalidate(receivedThreadsProvider);
        ref.invalidate(messagesUnreadCountProvider);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.primary,
        child: const Icon(Icons.archive, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _avatarColor(latest.sender.type, theme),
            child: Icon(_avatarIcon(latest.sender.type), color: Colors.white),
          ),
          title: Row(
            children: [
              if (thread.urgent) ...[
                const Icon(Icons.priority_high, color: Colors.red, size: 18),
                const SizedBox(width: 4),
              ],
              if (thread.sensitive) ...[
                Icon(
                  Icons.lock_outline,
                  color: theme.colorScheme.error,
                  size: 16,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  thread.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: thread.hasUnread
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: thread.hasUnread
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              if (thread.sensitive)
                Text(
                  'Arkaluonteinen viesti',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Text(
                  latest.content.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              Text(
                _formatDate(thread.latestSentAt),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              if (thread.hasUnread)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${thread.unreadCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
            ],
          ),
          isThreeLine: true,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MessageThreadScreen(thread: thread),
              ),
            );
          },
        ),
      ),
    );
  }
}

Color _avatarColor(String senderType, ThemeData theme) {
  switch (senderType) {
    case 'MUNICIPAL':
      return AppColors.senderMunicipal;
    case 'GROUP':
      return AppColors.senderGroup;
    case 'PERSONAL':
      return AppColors.senderPersonal;
    case 'CITIZEN':
      return AppColors.senderCitizen;
    default:
      return Colors.grey;
  }
}

IconData _avatarIcon(String senderType) {
  switch (senderType) {
    case 'MUNICIPAL':
      return Icons.account_balance;
    case 'GROUP':
      return Icons.groups;
    case 'PERSONAL':
      return Icons.person;
    case 'CITIZEN':
      return Icons.person_outline;
    default:
      return Icons.mail;
  }
}

String _formatDate(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(dt.year, dt.month, dt.day);
  final daysAgo = today.difference(thatDay).inDays;

  if (daysAgo == 0) return DateFormat('HH:mm').format(dt);
  if (daysAgo == 1) return 'eilen';
  if (daysAgo < 7) return '$daysAgo pv';
  if (dt.year == now.year) return DateFormat('d.M.').format(dt);
  return DateFormat('d.M.yyyy').format(dt);
}
