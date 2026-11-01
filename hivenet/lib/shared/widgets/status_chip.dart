import 'package:flutter/material.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../app/network_state.dart';
import '../../app/theme/spacing_tokens.dart';
import '../../app/theme/status_tone.dart';
import 'status_style.dart';

/// Pill showing a status with an icon AND text. Colour reinforces but is
/// never the only signal.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.style});

  StatusChip.availability(AvailabilityStatus s, {Key? key})
      : this(key: key, style: availabilityStyle(s));
  StatusChip.replica(ReplicaState s, {Key? key})
      : this(key: key, style: replicaStyle(s));
  StatusChip.upload(UploadState s, {Key? key})
      : this(key: key, style: uploadStyle(s));
  StatusChip.peer(PeerStatus s, {Key? key})
      : this(key: key, style: peerStyle(s));
  StatusChip.network(NetworkState s, {Key? key})
      : this(key: key, style: networkStyle(s));
  StatusChip.importance(Importance i, {Key? key})
      : this(key: key, style: importanceStyle(i));
  StatusChip.visibility(ImageVisibility v, {Key? key})
      : this(key: key, style: visibilityStyle(v));

  final StatusStyle style;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final fg = style.tone.foreground(brightness);
    return Semantics(
      label: style.label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md - 2, vertical: Spacing.xs + 1),
          decoration: BoxDecoration(
            color: style.tone.background(brightness),
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: Sizes.iconSm, color: fg),
              const SizedBox(width: Spacing.xs + 2),
              Flexible(
                child: Text(
                  style.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
