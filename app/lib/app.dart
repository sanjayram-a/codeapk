import 'package:flutter/material.dart';

import 'app_deps.dart';
import 'onboarding/onboarding_screen.dart';
import 'setup/setup_controller.dart';
import 'setup/setup_screen.dart';
import 'shell/home_shell.dart';

class OpencodeApp extends StatelessWidget {
  const OpencodeApp({super.key, required this.deps});

  final AppDeps deps;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F6BE0);
    return MaterialApp(
      title: 'OpenCode',
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: AppGate(deps: deps),
    );
  }
}

/// consent → setup → home. Nothing is installed or started before the user has agreed.
class AppGate extends StatefulWidget {
  const AppGate({super.key, required this.deps});

  final AppDeps deps;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  late final SetupController _setup = SetupController(widget.deps.runtime)..addListener(_onSetup);
  late bool _consented = widget.deps.settings.consentAccepted;

  @override
  void initState() {
    super.initState();
    if (_consented) _setup.run();
  }

  void _onSetup() {
    if (mounted) setState(() {});
  }

  Future<void> _accept() async {
    await widget.deps.settings.acceptConsent();
    if (!mounted) return;
    setState(() => _consented = true);
    _setup.run();
  }

  /// After "reset environment": back through setup, which unpacks a fresh system.
  void _afterReset() => _setup.run();

  @override
  void dispose() {
    _setup.removeListener(_onSetup);
    _setup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_consented) {
      return OnboardingScreen(runtime: widget.deps.runtime, onAccepted: _accept);
    }
    if (_setup.phase != SetupPhase.ready) return SetupScreen(controller: _setup);
    return HomeShell(deps: widget.deps, onResetDone: _afterReset);
  }
}
