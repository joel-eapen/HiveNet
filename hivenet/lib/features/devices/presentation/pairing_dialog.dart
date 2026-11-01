import 'package:flutter/material.dart';

import '../../../app/runtime/hivenet_runtime.dart';
import '../../../app/theme/typography.dart';

/// Shows the other device's name and fingerprint and asks the user to accept.
/// Both users do this on their own phone; pairing completes only if both accept.
Future<void> showPairingPrompt(BuildContext context, PairingPrompt prompt) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Pair with this device?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prompt.peerName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('Check that this code matches the one on the other phone:'),
          const SizedBox(height: 8),
          SelectableText(prompt.fingerprint, style: monoMetadataStyle),
          const SizedBox(height: 12),
          const Text(
            'Pairing lets this device store encrypted copies for you and you for it. '
            'It does not let it see your images unless you share one with it.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            prompt.respond(false);
            Navigator.of(context).pop();
          },
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () {
            prompt.respond(true);
            Navigator.of(context).pop();
          },
          child: const Text('Pair'),
        ),
      ],
    ),
  );
}
