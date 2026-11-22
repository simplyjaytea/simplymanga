import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';

import 'package:mangayomi/modules/audiobookshelf/audiobookshelf_shared.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_client.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_settings.dart';
import 'package:mangayomi/utils/platform_utils.dart';

/// Where the server address and API token are entered, tested and saved.
///
/// Shown as the Audiobookshelf tab's whole body before setup, and pushed from
/// the library's settings action afterwards. Every field and button here does
/// something; [closeOnSave] is what differs between the two uses.
class AudiobookshelfConnectionScreen extends ConsumerStatefulWidget {
  const AudiobookshelfConnectionScreen({super.key, this.closeOnSave = false});

  /// Pops after a successful save. A pushed settings page should return to the
  /// library; the initial setup page has nowhere to pop to.
  final bool closeOnSave;

  @override
  ConsumerState<AudiobookshelfConnectionScreen> createState() =>
      _AudiobookshelfConnectionScreenState();
}

class _AudiobookshelfConnectionScreenState
    extends ConsumerState<AudiobookshelfConnectionScreen> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _hydrated = false;
  bool _testing = false;
  bool _saving = false;
  String? _error;
  String? _connectedAs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hydrate(ref.read(absSettingsProvider).value);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _hydrate(AbsCredentials? credentials) {
    if (credentials == null || _hydrated) return;
    _hydrated = true;
    _url.text = credentials.baseUrl;
    _token.text = credentials.token;
  }

  bool get _canSubmit =>
      _url.text.trim().isNotEmpty &&
      _token.text.trim().isNotEmpty &&
      !_testing &&
      !_saving;

  AudiobookshelfClient? _client() {
    try {
      return ref.read(absClientFactoryProvider)(
        AbsCredentials(
          baseUrl: AudiobookshelfClient.normalizeBaseUrl(_url.text),
          token: _token.text.trim(),
        ),
      );
    } on ArgumentError catch (error) {
      setState(() {
        _error = error.message?.toString() ?? 'Enter a server URL.';
        _connectedAs = null;
      });
      return null;
    }
  }

  Future<void> _test() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _error = null;
      _connectedAs = null;
    });
    final client = _client();
    if (client == null) {
      setState(() => _testing = false);
      return;
    }
    try {
      await client.ping();
      final user = await client.me();
      if (!mounted) return;
      setState(() => _connectedAs = user.displayName);
    } on AbsException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(absSettingsProvider.notifier).save(_url.text, _token.text);
      if (!mounted) return;
      if (widget.closeOnSave && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message?.toString());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not save the settings: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(absSettingsProvider.notifier).clear();
    if (!mounted) return;
    _hydrated = false;
    _url.clear();
    _token.clear();
    setState(() {
      _error = null;
      _connectedAs = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The stored pair arrives after the first frame; fill the form once it
    // does, unless the reader has already typed over it.
    ref.listen(absSettingsProvider, (_, next) => _hydrate(next.value));
    final saved = ref.watch(absSettingsProvider).value;
    final tokens = context.shiori;

    return Scaffold(
      appBar: AppBar(title: const Text('Audiobookshelf')),
      body: ListView(
        padding: pageInsets(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShioriSpace.s16,
              ShioriSpace.s8,
              ShioriSpace.s16,
              ShioriSpace.s16,
            ),
            child: Text(
              'Connect to your Audiobookshelf server to stream its audiobooks '
              'here. The address and token stay on this device.',
              style: tokens.text.meta.copyWith(color: tokens.color.fgMuted),
            ),
          ),
          ShioriSettingsGroup(
            title: 'Server',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ShioriSpace.s16,
                  0,
                  ShioriSpace.s16,
                  ShioriSpace.s8,
                ),
                child: TextField(
                  key: const Key('abs-url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.10:13378',
                    helperText: 'http or https; no trailing slash needed',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ShioriSpace.s16,
                  0,
                  ShioriSpace.s16,
                  ShioriSpace.s8,
                ),
                child: TextField(
                  key: const Key('abs-token'),
                  controller: _token,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _test(),
                  decoration: const InputDecoration(
                    labelText: 'API token',
                    helperText: 'Audiobookshelf → Settings → Users → your user → API token',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ShioriSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: ShioriSpace.s8,
              children: [
                ShioriButton(
                  key: const Key('abs-test'),
                  label: 'Test connection',
                  icon: Symbols.wifi_tethering_rounded,
                  loading: _testing,
                  onPressed: _canSubmit ? _test : null,
                ),
                ShioriButton.secondary(
                  key: const Key('abs-save'),
                  label: 'Save & connect',
                  icon: Symbols.check_rounded,
                  loading: _saving,
                  onPressed: _canSubmit ? _save : null,
                ),
                if (saved != null)
                  ShioriButton.quiet(
                    key: const Key('abs-disconnect'),
                    label: 'Disconnect',
                    icon: Symbols.link_off_rounded,
                    destructive: true,
                    onPressed: _testing || _saving ? null : _disconnect,
                  ),
              ],
            ),
          ),
          if (_error != null)
            AbsNotice(
              key: const Key('abs-error'),
              icon: Symbols.error_rounded,
              color: tokens.color.error.foreground,
              message: _error!,
            ),
          if (_connectedAs != null)
            AbsNotice(
              key: const Key('abs-success'),
              icon: Symbols.check_circle_rounded,
              color: tokens.color.accentInk,
              message: 'Connected as $_connectedAs',
            ),
        ],
      ),
    );
  }
}
