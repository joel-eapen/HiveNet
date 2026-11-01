import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  }

  @override
  void dispose() {
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
          : TabBarView(controller: _tabs, children: const [_ShowCode(), _ScanCode()]),
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
  const _ScanCode();

  @override
  ConsumerState<_ScanCode> createState() => _ScanCodeState();
}

class _ScanCodeState extends ConsumerState<_ScanCode> {
  final _paste = TextEditingController();
  MobileScannerController? _camera;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  }

  @override
  void dispose() {
    _camera?.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _pair(String text) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Connecting. Confirm on both phones when asked.';
    });
    await _camera?.stop();
    try {
      final device = await ref.read(runtimeProvider)!.pairWithCode(text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Paired with ${device.displayName}')));
      context.go('/devices');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _friendly(e);
      });
      await _camera?.start();
    }
  }

  String _friendly(Object e) {
    final text = '$e';
    if (text.contains('expired')) return 'That code has expired. Ask for a new one.';
    if (text.contains('not valid')) return 'That is not a HiveNet pairing code.';
    if (text.contains('SocketException') || text.contains('timed out')) {
      return 'Could not reach the other phone. Check that both are on the same network and the code is still showing.';
    }
    if (text.contains('declined')) return 'Pairing was declined.';
    return 'Pairing did not complete. No device was added.';
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
              errorBuilder: (context, error) => const EmptyStateView(
                icon: Icons.no_photography_outlined,
                title: 'Camera not available',
                message: 'Allow camera access, or paste the code below instead.',
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
