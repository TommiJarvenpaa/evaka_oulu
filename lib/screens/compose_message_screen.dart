import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/recipients.dart';
import '../state/app_state.dart';

/// Uuden viestisäikeen luonti. Käyttäjä:
/// 1. Valitsee yhden tai useamman lapsen (joiden kautta vastaanottajat löytyy)
/// 2. Valitsee message-accountit valittujen lasten newMessage-joukosta
/// 3. Kirjoittaa otsikon ja sisällön
/// 4. Liittää tiedostoja (lähetetään orpoina liitteinä, sidotaan POST:n yhteydessä)
/// 5. Lähettää → POST /api/citizen/messages
class ComposeMessageScreen extends ConsumerStatefulWidget {
  const ComposeMessageScreen({super.key});

  @override
  ConsumerState<ComposeMessageScreen> createState() =>
      _ComposeMessageScreenState();
}

class _ComposeMessageScreenState extends ConsumerState<ComposeMessageScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final Set<String> _selectedChildIds = {};
  final Set<String> _selectedAccountIds = {};

  /// uploadId → (alkuperäinen tiedostonimi, koko tavuissa)
  final Map<String, ({String name, int sizeBytes})> _uploadedAttachments = {};

  bool _uploadingAttachment = false;
  bool _sending = false;
  String? _sendError;

  /// Kun true, PopScope sallii pop-pyynnön ilman hylkäys-vahvistusta.
  /// Asetetaan trueksi onnistuneen lähetyksen jälkeen ja kun käyttäjä
  /// vahvistaa luonnoksen hylkäyksen.
  bool _bypassPopScope = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  /// Lasten lista lapsi-id → näyttönimi reservations-providerista.
  Map<String, String> _childNames() {
    final children =
        ref.watch(reservationsProvider).asData?.value.children ?? const [];
    return {for (final c in children) c.id: c.displayName};
  }

  /// Vastaanottaja-accountit jotka ovat saatavilla valittujen lasten kautta.
  List<MessageAccountWithPresence> _availableAccounts(
    MessageRecipientsResponse recipients,
  ) {
    if (_selectedChildIds.isEmpty) return const [];

    // Yhdistä newMessage-joukot kaikista valituista lapsista.
    final allowedIds = <String>{};
    for (final access in recipients.childrenToMessageAccounts) {
      if (access.childId == null) continue;
      if (_selectedChildIds.contains(access.childId)) {
        allowedIds.addAll(access.newMessageAccountIds);
      }
    }

    return recipients.messageAccounts
        .where((a) => allowedIds.contains(a.account.id))
        .toList()
      ..sort((a, b) => a.account.name.compareTo(b.account.name));
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) {
      _snack('Tiedoston polku puuttuu, valitse toinen tiedosto');
      return;
    }

    setState(() => _uploadingAttachment = true);
    try {
      final id = await ref
          .read(attachmentsApiProvider)
          .uploadMessageAttachment(filePath: path, filename: picked.name);
      if (!mounted) return;
      setState(() {
        _uploadedAttachments[id] = (name: picked.name, sizeBytes: picked.size);
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Liitteen lähetys epäonnistui: $e');
    } finally {
      if (mounted) setState(() => _uploadingAttachment = false);
    }
  }

  Future<void> _removeAttachment(String id) async {
    final removed = _uploadedAttachments.remove(id);
    setState(() {});
    try {
      await ref.read(attachmentsApiProvider).deleteAttachment(id);
    } catch (_) {
      // Hiljainen: jos poisto ei mene läpi, liite jää orvoksi backendiin,
      // mutta käyttäjän UX ei kärsi. eVakassa on cleanup-job orvoille.
      if (removed != null && mounted) {
        _snack('Liite poistettu paikallisesti, palvelin ei kuitannut.');
      }
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountIds.isEmpty) {
      setState(() => _sendError = 'Valitse vähintään yksi vastaanottaja');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(messagesApiProvider)
          .createThread(
            title: _titleController.text.trim(),
            content: _contentController.text.trim(),
            recipientAccountIds: _selectedAccountIds.toList(),
            childIds: _selectedChildIds.toList(),
            attachmentIds: _uploadedAttachments.keys.toList(),
          );
      if (!mounted) return;
      ref.invalidate(receivedThreadsProvider);
      ref.invalidate(messagesUnreadCountProvider);
      // Salli pop: PopScope hyväksyy nyt pop-pyynnön
      setState(() => _bypassPopScope = true);
      navigator.pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Viesti lähetetty')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = 'Lähetys epäonnistui: $e';
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirmDiscard() async {
    final hasContent =
        _titleController.text.trim().isNotEmpty ||
        _contentController.text.trim().isNotEmpty ||
        _uploadedAttachments.isNotEmpty;
    if (!hasContent) return true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hylätäänkö luonnos?'),
        content: const Text(
          'Kirjoittamasi viesti ja lisätyt liitteet menetetään.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Peruuta'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hylkää'),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    // Siivoa orvot liitteet kun käyttäjä hylkää luonnoksen
    for (final id in _uploadedAttachments.keys.toList()) {
      try {
        await ref.read(attachmentsApiProvider).deleteAttachment(id);
      } catch (_) {
        // ignore — palvelimen cleanup hoitaa
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recipientsAsync = ref.watch(messageRecipientsProvider);
    final childNames = _childNames();

    return PopScope(
      canPop: _bypassPopScope,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (!mounted) return;
          setState(() => _bypassPopScope = true);
          // Käytetään State.context (this.context) jotta `mounted`-tarkistus
          // suojaa contextia — captured `context` build-parametrista olisi
          // analysaattorin silmissä eri muuttuja.
          Navigator.of(this.context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Uusi viesti'),
          actions: [
            if (_sending)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Lähetä',
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
          ],
        ),
        body: recipientsAsync.when(
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
                    'Vastaanottajien haku epäonnistui:\n$e',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(messageRecipientsProvider),
                    child: const Text('Yritä uudelleen'),
                  ),
                ],
              ),
            ),
          ),
          data: (recipients) {
            final availableAccounts = _availableAccounts(recipients);
            // Lapset jotka voivat vastaanottaa uutta viestiä
            final availableChildIds = {
              for (final a in recipients.childrenToMessageAccounts)
                if (a.childId != null && a.newMessageAccountIds.isNotEmpty)
                  a.childId!,
            };

            // Karsitaan poistuneet lapset valinnasta
            _selectedChildIds.removeWhere(
              (id) => !availableChildIds.contains(id),
            );
            // Karsitaan account-valinta jos lapsi poistui ja account ei enää saatavilla
            final stillValidIds = availableAccounts
                .map((a) => a.account.id)
                .toSet();
            _selectedAccountIds.removeWhere(
              (id) => !stillValidIds.contains(id),
            );

            if (availableChildIds.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ei lapsia joille voi lähettää viestin. '
                    'Jos lapsen sijoitus on aktiivinen mutta tämä ei toimi, '
                    'ota yhteyttä päiväkotiin.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text('Lapsi', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final id in availableChildIds)
                        FilterChip(
                          label: Text(childNames[id] ?? 'Lapsi'),
                          selected: _selectedChildIds.contains(id),
                          onSelected: _sending
                              ? null
                              : (sel) => setState(() {
                                  if (sel) {
                                    _selectedChildIds.add(id);
                                  } else {
                                    _selectedChildIds.remove(id);
                                  }
                                  // Karsi account-valinta jos lapsi poistui
                                  final newAvailable = _availableAccounts(
                                    recipients,
                                  ).map((a) => a.account.id).toSet();
                                  _selectedAccountIds.removeWhere(
                                    (id) => !newAvailable.contains(id),
                                  );
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Vastaanottaja', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  if (_selectedChildIds.isEmpty)
                    Text(
                      'Valitse ensin lapsi',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else if (availableAccounts.isEmpty)
                    Text(
                      'Ei vastaanottajia näille lapsille',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final a in availableAccounts)
                          CheckboxListTile(
                            value: _selectedAccountIds.contains(a.account.id),
                            onChanged: _sending
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      _selectedAccountIds.add(a.account.id);
                                    } else {
                                      _selectedAccountIds.remove(a.account.id);
                                    }
                                  }),
                            title: Text(a.account.name),
                            subtitle: Text(
                              _accountTypeLabel(a.account.type) +
                                  _outOfOfficeSuffix(a.outOfOffice),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _titleController,
                    enabled: !_sending,
                    decoration: const InputDecoration(
                      labelText: 'Otsikko',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Otsikko vaaditaan'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contentController,
                    enabled: !_sending,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Viesti',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Viestin sisältö vaaditaan'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Liitteet',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      TextButton.icon(
                        icon: _uploadingAttachment
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.attach_file),
                        label: const Text('Lisää'),
                        onPressed: (_sending || _uploadingAttachment)
                            ? null
                            : _pickAndUpload,
                      ),
                    ],
                  ),
                  if (_uploadedAttachments.isEmpty)
                    Text(
                      'Ei liitteitä',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final entry in _uploadedAttachments.entries)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.insert_drive_file),
                            title: Text(
                              entry.value.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(_formatBytes(entry.value.sizeBytes)),
                            trailing: IconButton(
                              tooltip: 'Poista',
                              icon: const Icon(Icons.close),
                              onPressed: _sending
                                  ? null
                                  : () => _removeAttachment(entry.key),
                            ),
                          ),
                      ],
                    ),
                  if (_sendError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _sendError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _accountTypeLabel(String type) {
  switch (type) {
    case 'MUNICIPAL':
      return 'Kunta';
    case 'GROUP':
      return 'Ryhmä';
    case 'PERSONAL':
      return 'Henkilökunta';
    case 'SERVICE_WORKER':
      return 'Palveluohjaaja';
    case 'CITIZEN':
      return 'Huoltaja';
    default:
      return type;
  }
}

String _outOfOfficeSuffix(({DateTime start, DateTime end})? ooo) {
  if (ooo == null) return '';
  return ' · Poissa ${ooo.start.day}.${ooo.start.month}.–${ooo.end.day}.${ooo.end.month}.';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kt';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mt';
}
