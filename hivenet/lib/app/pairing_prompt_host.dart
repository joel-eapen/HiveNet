import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/devices/presentation/pairing_dialog.dart';
import 'providers.dart';
import 'router.dart';
import 'runtime/hivenet_runtime.dart';

/// Shows the "Pair with this device?" dialog whenever a pairing needs an
/// answer, on top of whatever screen is open (including onboarding).
class PairingPromptHost extends ConsumerStatefulWidget {
  const PairingPromptHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PairingPromptHost> createState() => _PairingPromptHostState();
}

class _PairingPromptHostState extends ConsumerState<PairingPromptHost> {
  // Kept in fields: `ref` must not be used in dispose().
  ValueNotifier<PairingPrompt?>? _pending;
  PairingPrompt? _shown;

  @override
  void initState() {
    super.initState();
    _pending = ref.read(runtimeProvider)?.pendingPairing;
    _pending?.addListener(_onChange);
    // A prompt may already be waiting if the app was just opened.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
  }

  @override
  void dispose() {
    _pending?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final prompt = _pending?.value;
    if (prompt == null || identical(prompt, _shown)) return;
    // The root navigator sits below this widget, so go through its key.
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      // Not built yet: try again after the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
      return;
    }
    _shown = prompt;
    showPairingPrompt(context, prompt);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
