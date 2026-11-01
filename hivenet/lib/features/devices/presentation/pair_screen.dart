import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:hivenet_core/hivenet_core.dart' show HiveError;

import '../../../app/providers.dart';
import '../../../app/runtime/hivenet_runtime.dart';
import '../../../app/theme/spacing_tokens.dart';
import '../../../shared/widgets/empty_state_view.dart';

/// FR-12 screen 2. One phone shows a code, the other scans it. The code carries
/// the address, so this works even where mDNS is blocked.
class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  HiveNetRuntime? _runtime;

  @override
  void initState() {
    super.initState();
    _runtime = ref.read(runtimeProvider);
    // The other phone may finish (or fail) pairing while this screen shows the
    // code. Tell the user either way.
    _runtime?.lastPairing.addListener(_onPairingOutcome);
  }

  void _onPairingOutcome() {
    final outcome = _runtime?.lastPairing.value;
    if (outcome == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.message)));
    if (outcome.ok) context.go('/devices');
  }

  @override
  void dispose() {
    _runtime?.lastPairing.removeListener(_onPairingOutcome);
    // Stop accepting unknown devices as soon as this screen closes.
    _runtime?.cancelInvite();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rt = ref.watch(runtimeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair a device'),
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Show my code'),
          Tab(text: 'Scan a code'),
        ]),
      ),
      body: rt == null
          ? const EmptyStateView(
              icon: Icons.qr_code_2,
              title: 'Pairing is not available',
              message: 'HiveNet is not running on this device.',
            )
          : TabBarView(controller: _tabs, children: [
              const _ShowCode(),
              // Rebuilt when the tab changes, so the camera runs only while the
              // scan tab is showing.
              AnimatedBuilder(
                animation: _tabs.animation!,
                builder: (context, _) => _ScanCode(active: _tabs.index == 1 && !_tabs.indexIsChanging),
              ),
            ]),
    );
  }
}

class _ShowCode extends ConsumerStatefulWidget {
  const _ShowCode();

  @override
  ConsumerState<_ShowCode> createState() => _ShowCodeState();
}

class _ShowCodeState extends ConsumerState<_ShowCode> {
  String? _code;
  DateTime? _expires;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _create();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    try {
      final invite = await ref.read(runtimeProvider)!.createInvite();
      if (mounted) {
        setState(() {
          _code = invite.toQrString();
          _expires = invite.expiresAt;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return EmptyStateView(
        icon: Icons.wifi_off,
        title: 'Could not create a code',
        message: _error!.contains('Wi-Fi') ? 'Connect to Wi-Fi first, then try again.' : _error!,
        action: FilledButton(onPressed: _create, child: const Text('Try again')),
      );
    }
    if (_code == null) return const Center(child: CircularProgressIndicator());

    final left = _expires!.difference(DateTime.now().toUtc());
    final expired = left.isNegative;
    return ListView(
      padding: const EdgeInsets.all(Spacing.xl),
      children: [
        Text('Let the other phone scan this', style: theme.textTheme.titleLarge),
        const SizedBox(height: Spacing.sm),
        const Text('Open Pair a device on the other phone, choose Scan a code, and point it here.'),
        const SizedBox(height: Spacing.xl),
        Center(
          child: Opacity(
            opacity: expired ? 0.2 : 1,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(Spacing.md),
              child: QrImageView(data: _code!, size: 260),
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Center(
          child: Text(
            expired
                ? 'This code has expired'
                : 'Valid for ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Center(
          child: OutlinedButton(
            onPressed: _create,
            child: Text(expired ? 'Make a new code' : 'Refresh code'),
          ),
        ),
        const SizedBox(height: Spacing.xl),
        const Text(
          'This code works once. Treat it like a password: only show it to the person you want to pair with.',
        ),
        const SizedBox(height: Spacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Code as text'),
                content: SelectableText(_code!),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
              ),
            ),
            icon: const Icon(Icons.text_snippet_outlined),
            label: const Text('Show as text'),
          ),
        ),
      ],
    );
  }
}

class _ScanCode extends ConsumerStatefulWidget {
  const _ScanCode({required this.active});

  /// True while this tab is the one on screen.
  final bool active;

  @override
  ConsumerState<_ScanCode> createState() => _ScanCodeState();
}

class _ScanCodeState extends ConsumerState<_ScanCode> {
  final _paste = TextEditingController();
  // autoStart is off: the camera is started and stopped here, only while this
  // tab is visible, so it never collides with the widget's own start-up.
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    autoStart: false,
  );
  bool _busy = false;
  bool _cameraOn = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.active) _startCamera();
  }

  @override
  void didUpdateWidget(_ScanCode old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _startCamera();
    if (!widget.active && old.active) _stopCamera();
  }

  @override
  void dispose() {
    _camera.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (_cameraOn || _busy) return;
    _cameraOn = true;
    try {
      await _camera.start();
    } on MobileScannerException catch (e) {
      // Already running is harmless. Anything else is shown by the errorBuilder.
      if (e.errorCode != MobileScannerErrorCode.controllerAlreadyInitialized) {
        _cameraOn = false;
      }
    } catch (_) {
      _cameraOn = false;
    }
  }

  Future<void> _stopCamera() async {
    if (!_cameraOn) return;
    _cameraOn = false;
    try {
      await _camera.stop();
    } catch (_) {
      // Stopping something already stopped is fine.
    }
  }

  Future<void> _pair(String text) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Connecting. Confirm on both phones when asked.';
    });
    await _stopCamera();
    try {
      final device = await ref.read(runtimeProvider)!.pairWithCode(text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Paired with ${device.displayName}')));
      context.go('/devices');
    } catch (e) {
      if (!mounted) return;
      debugPrint('pairing failed: $e');
      setState(() {
        _busy = false;
        _message = _friendly(e);
      });
      if (widget.active) await _startCamera();
    }
  }

  String _cameraTitle(MobileScannerErrorCode code) => switch (code) {
        MobileScannerErrorCode.permissionDenied => 'Camera access is off',
        MobileScannerErrorCode.unsupported => 'No camera found',
        _ => 'The camera could not start',
      };

  String _cameraHelp(MobileScannerException error) {
    final base = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Allow camera access for HiveNet in your phone\'s settings, then reopen this tab.',
      MobileScannerErrorCode.unsupported => 'This device has no usable camera.',
      _ => 'Close and reopen this tab to try again.',
    };
    final detail = error.errorDetails?.message;
    return '$base You can also paste the code below.'
        '${detail == null ? '' : '\n\n($detail)'}';
  }

  String _friendly(Object e) {
    final text = '$e';
    if (text.contains('expired')) return 'That code has expired. Ask for a new one.';
    if (text.contains('not valid')) return 'That is not a HiveNet pairing code.';
    if (text.contains('SocketException') || text.contains('timed out')) {
      return 'Could not reach the other phone. Check that both are on the same network and the code is still showing.';
    }
    if (text.contains('declined')) return 'Pairing was declined on one of the phones.';
    if (text.contains('different device') || text.contains('does not match the expected')) {
      return 'That is not the phone whose code you scanned. No device was added.';
    }
    if (text.contains('disconnected') || text.contains('closed the connection')) {
      return 'The other phone disconnected before pairing finished. '
          'Check on its Devices screen whether it was added, then try again if not.';
    }
    final detail = e is HiveError ? e.technicalDetails : null;
    return 'Pairing did not complete. No device was added.'
        '${detail == null ? '' : ' ($detail)'}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.lg),
          child: SizedBox(
            height: 300,
            child: MobileScanner(
              controller: _camera,
              onDetect: (capture) {
                for (final b in capture.barcodes) {
                  final raw = b.rawValue;
                  if (raw != null && raw.startsWith('hivenet://pair')) {
                    _pair(raw);
                    break;
                  }
                }
              },
              errorBuilder: (context, error) => EmptyStateView(
                icon: Icons.no_photography_outlined,
                title: _cameraTitle(error.errorCode),
                message: _cameraHelp(error),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Text(_message!),
          ),
        const SizedBox(height: Spacing.md),
        Text('Or paste the code', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _paste,
          maxLines: 2,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'hivenet://pair?d=…',
          ),
        ),
        const SizedBox(height: Spacing.sm),
        FilledButton(
          onPressed: _busy ? null : () => _pair(_paste.text),
          child: const Text('Pair'),
        ),
      ],
    );
  }
}
