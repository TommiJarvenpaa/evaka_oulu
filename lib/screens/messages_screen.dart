import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/models/message.dart';
import '../main.dart' show AppColors;
import '../state/app_state.dart';
import 'compose_message_screen.dart';
import 'message_thread_screen.dart';

/// 0 = Saapuneet, 1 = Lähetetyt
final inboxFilterProvider = StateProvider<int>((ref) => 0);

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(inboxFilterProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Saapuneet'),
                  icon: Icon(Icons.inbox),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Lähetetyt'),
                  icon: Icon(Icons.send),
                ),
              ],
              selected: {filter},
              onSelectionChanged: (s) =>
                  ref.read(inboxFilterProvider.notifier).state = s.first,
            ),
          ),
          Expanded(child: filter == 1 ? const _SentList() : const _InboxList()),
        ],
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

/// Saapuneet-välilehti: infinite scroll. Tarkkailee scroll-positiota ja
/// lataa lisää sivuja kun loppu lähestyy. Notifier hoitaa dedupin
/// (`loadingMore`-lippu) joten samat sivut eivät lataudu kahteen kertaan.
class _InboxList extends ConsumerStatefulWidget {
  const _InboxList();

  @override
  ConsumerState<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends ConsumerState<_InboxList> {
  final ScrollController _scrollController = ScrollController();

  /// Liipaisuetäisyys: kun käyttäjä on alle 300 px listan lopusta, pyydä lisää.
  static const double _loadMoreThresholdPx = 300;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThresholdPx) {
      ref.read(receivedThreadsProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    await ref.read(receivedThreadsProvider.notifier).refresh();
    ref.invalidate(messagesUnreadCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(receivedThreadsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ListError(
        message: 'Viestien haku epäonnistui:\n$e',
        onRetry: () => ref.invalidate(receivedThreadsProvider),
      ),
      data: (state) {
        if (state.threads.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: const [
                SizedBox(height: 200),
                Center(child: Text('Ei viestejä.')),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            // +1 = footer-rivi joko spinneriä (loadingMore) tai "ei enempää"
            itemCount:
                state.threads.length +
                (state.hasMore || state.loadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= state.threads.length) {
                return _LoadMoreFooter(loading: state.loadingMore);
              }
              return _ThreadTile(thread: state.threads[i]);
            },
          ),
        );
      },
    );
  }
}

/// Lähetetyt-välilehti: ei infinite scrollia. Provider hakee 10 sivua
/// kerralla ja suodattaa client-puolella, tuloksena on yksi staattinen lista.
class _SentList extends ConsumerWidget {
  const _SentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sentThreadsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ListError(
        message: 'Viestien haku epäonnistui:\n$e',
        onRetry: () => ref.invalidate(sentThreadsProvider),
      ),
      data: (page) {
        if (page.threads.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(sentThreadsProvider);
              await ref.read(sentThreadsProvider.future);
            },
            child: ListView(
              children: const [
                SizedBox(height: 200),
                Center(child: Text('Ei lähetettyjä viestejä.')),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(sentThreadsProvider);
            await ref.read(sentThreadsProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            itemCount: page.threads.length,
            itemBuilder: (context, i) =>
                _ThreadTile(thread: page.threads[i], isSent: true),
          ),
        );
      },
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _ListError extends StatelessWidget {
  const _ListError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Yritä uudelleen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.thread, this.isSent = false});

  final MessageThread thread;

  /// Lähetetyt-näkymässä: ei swipe-arkistointia, ei "lukematon"-korostusta
  /// (omat lähetetyt ovat aina luettuja itselle).
  final bool isSent;

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
    final hasUnread = !isSent && thread.hasUnread;

    final card = Card(
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
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
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
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
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
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );

    // Lähetetyt-näkymässä ei tarjota arkistointia (eVakassa arkistointi on
    // saapuneille); palautetaan pelkkä kortti
    if (isSent) return card;

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
        // Poista pelkästään tämä säie listalta — ei full reloadia, jotta
        // käyttäjän scroll-positio säilyy.
        ref.read(receivedThreadsProvider.notifier).removeThread(thread.id);
        ref.invalidate(messagesUnreadCountProvider);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.primary,
        child: const Icon(Icons.archive, color: Colors.white),
      ),
      child: card,
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
