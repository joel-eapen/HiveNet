// THROWAWAY Milestone 0 spike code.
import 'package:flutter/material.dart';

import '../app/theme/spacing_tokens.dart';
import '../app/theme/typography.dart';
import 'spike_checks.dart';
import 'spike_controller.dart';

/// Developer-only screen for the PRD section 10.6 mobile compatibility gate.
class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final SpikeController c = SpikeController();
  final _host = TextEditingController();
  final _port = TextEditingController();
  Object? _initError;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    c.init().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object e) {
      if (mounted) setState(() => _initError = e);
    });
  }

  @override
  void dispose() {
    c.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  int? get _manualPort => int.tryParse(_port.text.trim());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feasibility spike (M0)')),
      body: _initError != null
          ? Center(child: Text('Spike failed to start: $_initError'))
          : !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => _body(context),
                ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Text('This device', style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.xs),
        SelectableText(
          'node ${c.nodeId} · ${c.platform}\nTCP port ${c.node.port}\n'
          '${c.localAddresses.join('\n')}',
          style: monoMetadataStyle,
        ),
        const SizedBox(height: Spacing.lg),
        Text('Checklist (PRD 10.6)', style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        for (final check in c.report.checks.values) _CheckCard(check),
        const SizedBox(height: Spacing.lg),
        Text('Actions', style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
          FilledButton(
              onPressed: c.busy ? null : c.selfTest,
              child: const Text('Loopback self-test')),
          FilledButton(
              onPressed: c.startDiscovery,
              child: const Text('Start mDNS advertise + discover')),
          OutlinedButton(
              onPressed: c.busy ? null : c.compressGenerated,
              child: const Text('Compress generated image')),
          OutlinedButton(
              onPressed: c.busy ? null : c.pickAndCompress,
              child: const Text('Pick image and compress')),
          OutlinedButton(onPressed: c.resetKey, child: const Text('Delete identity key')),
        ]),
        const SizedBox(height: Spacing.lg),
        Text('Discovered peers', style: theme.textTheme.titleMedium),
        if (c.found.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text('None yet. Start discovery on both phones.'),
          ),
        for (final p in c.found.values)
          _PeerCard(
            title: '${p.nodeId} (${p.platform})',
            subtitle: '${p.host}:${p.port}',
            busy: c.busy,
            onLink: () => c.link(p.host, p.port),
            onTransfer: () => c.interruptedTransfer(p.host, p.port),
            onImage: () => c.sendCompressed(p.host, p.port),
          ),
        const SizedBox(height: Spacing.md),
        Text('Manual connect (diagnostic only)', style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'IP', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: Spacing.sm),
        _PeerCard(
          title: 'Manual peer',
          subtitle: 'Uses the IP and port above',
          busy: c.busy,
          onLink: _manualPort == null ? null : () => c.link(_host.text.trim(), _manualPort!),
          onTransfer: _manualPort == null
              ? null
              : () => c.interruptedTransfer(_host.text.trim(), _manualPort!),
          onImage: _manualPort == null
              ? null
              : () => c.sendCompressed(_host.text.trim(), _manualPort!),
        ),
        const SizedBox(height: Spacing.lg),
        Text('Heartbeats received', style: theme.textTheme.titleMedium),
        if (c.heartbeats.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text('No peer is linked to this device yet.'),
          ),
        for (final b in c.heartbeats)
          ListTile(
            dense: true,
            leading: Icon(b.isOnline ? Icons.circle : Icons.pause_circle_outline,
                color: b.isOnline ? Colors.green : Colors.orange),
            title: Text('${b.nodeId} (${b.platform})'),
            subtitle: Text(
                '${b.isOnline ? "online" : "UNAVAILABLE"}, last heartbeat ${b.age.inSeconds}s ago'),
          ),
        if (c.lastReceivedImage != null) ...[
          const SizedBox(height: Spacing.lg),
          Text('Last received image', style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          Image.memory(c.lastReceivedImage!, height: 160),
          Text(c.lastReceivedInfo ?? '', style: monoMetadataStyle),
        ],
        const SizedBox(height: Spacing.lg),
        Text('Log', style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        SelectableText(
          c.report.logLines.reversed.take(60).join('\n'),
          style: monoMetadataStyle,
        ),
      ],
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard(this.check);
  final SpikeCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (check.status) {
      CheckStatus.pass => (Icons.check_circle, Colors.green, 'PASS'),
      CheckStatus.partial => (Icons.timelapse, Colors.orange, 'PARTIAL'),
      CheckStatus.fail => (Icons.cancel, Colors.red, 'FAIL'),
      CheckStatus.pending => (Icons.radio_button_unchecked, Colors.grey, 'PENDING'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${check.title} · $label',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(check.detail.isEmpty ? check.how : check.detail,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onLink,
    required this.onTransfer,
    required this.onImage,
  });

  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback? onLink;
  final VoidCallback? onTransfer;
  final VoidCallback? onImage;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(subtitle, style: monoMetadataStyle),
            const SizedBox(height: Spacing.sm),
            Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
              OutlinedButton(onPressed: onLink, child: const Text('Heartbeat link')),
              OutlinedButton(
                  onPressed: busy ? null : onTransfer,
                  child: const Text('5 MiB + resume')),
              OutlinedButton(
                  onPressed: busy ? null : onImage,
                  child: const Text('Send compressed image')),
            ]),
          ],
        ),
      ),
    );
  }
}
