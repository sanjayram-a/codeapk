import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:opencode_runtime/opencode_runtime.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../api/opencode_api.dart';
import '../server_guard.dart';
import 'chat_session.dart';
import 'phone_layout_fixes.dart';

/// The OpenCode web UI (chat with markdown, code, diffs, tool calls, permissions, model picker) opened on one
/// session. The WebView only ever talks to our own server, and answers its Basic-auth challenge itself.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.chat, required this.session});

  final ChatSession chat;
  final SessionInfo session;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  WebViewController? _web;
  int _generation = -1;
  int _loadingPercent = 0;

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_onChat);
    widget.chat.ensureRunning();
    _onChat(initial: true);
  }

  @override
  void dispose() {
    widget.chat.removeListener(_onChat);
    super.dispose();
  }

  /// A restart can change the port and password: build a new WebView controller for the new server.
  void _onChat({bool initial = false}) {
    final base = widget.chat.base;
    final password = widget.chat.password;
    if (base == null || password == null) return;
    if (_generation == widget.chat.generation && _web != null) return;
    _generation = widget.chat.generation;
    final port = base.port;
    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => controller.runJavaScript(phoneLayoutFixesJs),
        onPageFinished: (_) => controller.runJavaScript(phoneLayoutFixesJs),
        onProgress: (p) {
          if (mounted) setState(() => _loadingPercent = p);
        },
        // The server answers 401 with a Basic challenge; answering it lets every request carry the password.
        onHttpAuthRequest: (req) => shouldAnswerAuth(host: req.host, realm: req.realm)
            ? req.onProceed(WebViewCredential(user: 'opencode', password: password))
            : req.onCancel(),
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri != null && isOwnServer(uri, port)) return NavigationDecision.navigate;
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(chatUrl(base, widget.session));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // Debug builds, or release built with --dart-define=WEBVIEW_DEBUG=true: lets chrome://inspect attach.
      AndroidWebViewController.enableDebugging(kDebugMode || const bool.fromEnvironment('WEBVIEW_DEBUG'));
      // Without this the web UI's attach ("+") button asks Android for a file chooser and nothing answers.
      platform.setOnShowFileSelector(_pickFiles);
    }
    if (initial) {
      _web = controller;
    } else if (mounted) {
      setState(() => _web = controller);
    }
  }

  /// Answers the web page's file chooser with the system picker. Returns content/file URIs the WebView can read.
  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    if (params.mode == FileSelectorMode.save) return const [];
    final imagesOnly = params.acceptTypes.isNotEmpty && params.acceptTypes.every((t) => t.startsWith('image/'));
    final type = imagesOnly ? FileType.image : FileType.any;
    try {
      if (params.mode == FileSelectorMode.openMultiple) {
        final files = await FilePicker.pickFiles(type: type);
        return [for (final f in files) f.uri.toString()];
      }
      final file = await FilePicker.pickFile(type: type);
      return file == null ? const [] : [file.uri.toString()];
    } catch (_) {
      return const []; // cancelled or picker unavailable: the page treats an empty list as "no file chosen"
    }
  }

  Future<bool> _goBackInWeb() async {
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (!await _goBackInWeb()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.session.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: _web == null ? null : () => _web!.reload(),
            ),
          ],
          bottom: _web != null && _loadingPercent < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _loadingPercent == 0 ? null : _loadingPercent / 100),
                )
              : null,
        ),
        body: ListenableBuilder(
          listenable: widget.chat,
          builder: (context, _) {
            final snap = widget.chat.snapshot;
            if (_web != null && snap.isRunning) return WebViewWidget(controller: _web!);
            if (snap.status == ServerStatus.failed) {
              return _FailedView(snap: snap, onRetry: widget.chat.retry);
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.snap, required this.onRetry});

  final ServerSnapshot snap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('The server could not start', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(snap.error ?? 'Unknown error'),
        const SizedBox(height: 12),
        if ((snap.logTail ?? '').isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SelectableText(snap.logTail!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
