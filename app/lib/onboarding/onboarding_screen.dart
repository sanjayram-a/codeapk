import 'package:flutter/material.dart';
import 'package:opencode_runtime/opencode_runtime.dart';

/// Disclosure + consent. Nothing is installed or started until the user continues.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.runtime,
    required this.onAccepted,
  });

  final RuntimeApi runtime;
  final VoidCallback onAccepted;

  static const title = 'A Linux environment on your phone';
  static const body =
      "OpenCode runs inside a private Linux environment in this app's own storage. The AI can run commands there "
      '— install packages, edit files and use the network — but it cannot see your other apps or files. '
      'Your prompts go to the AI provider you configure.';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool? _notifications;

  Future<void> _askNotifications() async {
    final granted = await widget.runtime.requestNotificationPermission();
    if (mounted) setState(() => _notifications = granted);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 24),
                        Icon(
                          Icons.terminal,
                          size: 56,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          OnboardingScreen.title,
                          style: text.headlineMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(OnboardingScreen.body, style: text.bodyLarge),
                        const SizedBox(height: 16),
                        Text(
                          'Setup downloads nothing: the Linux system ships inside the app and is unpacked once (about 400 MB of storage).',
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _notifications == true
                              ? null
                              : _askNotifications,
                          icon: Icon(
                            _notifications == true
                                ? Icons.check
                                : Icons.notifications_outlined,
                          ),
                          label: Text(
                            _notifications == true
                                ? 'Notifications allowed'
                                : 'Allow notifications',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 24),
                          child: Text(
                            _notifications == false
                                ? "No problem — OpenCode still works. You just won't see the “running” notification."
                                : 'Optional. Lets you see (and stop) the server while the app is in the background.',
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.onAccepted,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('I understand, continue'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
