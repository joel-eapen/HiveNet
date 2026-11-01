import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/typography.dart';

/// Shows a shortened identifier (never the full hash by default) with a copy
/// action that copies the full value.
class CopyableIdentifier extends StatelessWidget {
  const CopyableIdentifier({super.key, required this.value, this.label});

  final String value;
  final String? label;

  /// `3fa9c1d2…0001`
  static String shorten(String v) =>
      v.length <= 14 ? v : '${v.substring(0, 8)}…${v.substring(v.length - 4)}';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text('$label ', style: Theme.of(context).textTheme.labelMedium),
        ],
        Flexible(
          child: Text(shorten(value),
              style: monoMetadataStyle, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: 'Copy ${label ?? 'identifier'}',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied')),
              );
            }
          },
        ),
      ],
    );
  }
}
