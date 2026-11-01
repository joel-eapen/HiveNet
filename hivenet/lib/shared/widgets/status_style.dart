import 'package:flutter/material.dart';
import 'package:hivenet_core/hivenet_core.dart';

import '../../app/network_state.dart';
import '../../app/theme/status_tone.dart';

/// Label, icon and colour for one status. Every status has all three so colour
/// is never the only signal.
class StatusStyle {
  const StatusStyle(this.label, this.icon, this.tone);
  final String label;
  final IconData icon;
  final StatusTone tone;
}

StatusStyle availabilityStyle(AvailabilityStatus s) => switch (s) {
      AvailabilityStatus.available =>
        const StatusStyle('Available', Icons.check_circle_outline, StatusTone.success),
      AvailabilityStatus.temporarilyUnavailable => const StatusStyle(
          'Temporarily unavailable', Icons.cloud_off_outlined, StatusTone.error),
      AvailabilityStatus.underReplicated => const StatusStyle(
          'Under-replicated', Icons.warning_amber_rounded, StatusTone.warning),
      AvailabilityStatus.pending =>
        const StatusStyle('Pending', Icons.schedule, StatusTone.info),
      AvailabilityStatus.deleted =>
        const StatusStyle('Deleted', Icons.delete_outline, StatusTone.neutral),
    };

/// Stored and online are separate states (PRD section 13.2).
StatusStyle replicaStyle(ReplicaState s) => switch (s) {
      ReplicaState.storedVerified => const StatusStyle(
          'Stored (verified)', Icons.verified_outlined, StatusTone.info),
      ReplicaState.onlineServable => const StatusStyle(
          'Online, servable', Icons.cloud_done_outlined, StatusTone.success),
      ReplicaState.temporarilyUnavailable => const StatusStyle(
          'Temporarily unavailable', Icons.cloud_off_outlined, StatusTone.warning),
      ReplicaState.missing =>
        const StatusStyle('Missing', Icons.help_outline, StatusTone.error),
      ReplicaState.corrupted =>
        const StatusStyle('Corrupted', Icons.error_outline, StatusTone.error),
    };

StatusStyle uploadStyle(UploadState s) => switch (s) {
      UploadState.created =>
        const StatusStyle('Queued', Icons.schedule, StatusTone.neutral),
      UploadState.reserving =>
        const StatusStyle('Reserving space', Icons.lock_clock_outlined, StatusTone.info),
      UploadState.transferring =>
        const StatusStyle('Uploading', Icons.upload_outlined, StatusTone.info),
      UploadState.verifying =>
        const StatusStyle('Verifying', Icons.fact_check_outlined, StatusTone.info),
      UploadState.committing =>
        const StatusStyle('Committing', Icons.save_outlined, StatusTone.info),
      UploadState.replicating =>
        const StatusStyle('Replicating', Icons.copy_all_outlined, StatusTone.info),
      UploadState.completed =>
        const StatusStyle('Replicated', Icons.check_circle_outline, StatusTone.success),
      UploadState.retryPending =>
        const StatusStyle('Waiting to retry', Icons.replay, StatusTone.warning),
      UploadState.failed =>
        const StatusStyle('Failed', Icons.error_outline, StatusTone.error),
      UploadState.underReplicated => const StatusStyle(
          'Uploaded, replication incomplete', Icons.warning_amber_rounded, StatusTone.warning),
    };

StatusStyle peerStyle(PeerStatus s) => switch (s) {
      PeerStatus.discovered =>
        const StatusStyle('Nearby', Icons.wifi_find, StatusTone.neutral),
      PeerStatus.online =>
        const StatusStyle('Online', Icons.circle, StatusTone.success),
      PeerStatus.temporarilyUnavailable => const StatusStyle(
          'Unavailable (app not active)', Icons.pause_circle_outline, StatusTone.warning),
      PeerStatus.offline =>
        const StatusStyle('Offline', Icons.circle_outlined, StatusTone.error),
    };

StatusStyle networkStyle(NetworkState s) => switch (s) {
      NetworkState.offline =>
        const StatusStyle('Offline', Icons.wifi_off, StatusTone.error),
      NetworkState.discovering =>
        const StatusStyle('Discovering', Icons.wifi_find, StatusTone.info),
      NetworkState.connected =>
        const StatusStyle('Connected', Icons.wifi, StatusTone.success),
      NetworkState.degraded =>
        const StatusStyle('Degraded', Icons.network_check, StatusTone.warning),
    };

StatusStyle importanceStyle(Importance i) => switch (i) {
      Importance.normal => const StatusStyle('Normal', Icons.photo_outlined, StatusTone.neutral),
      Importance.important =>
        const StatusStyle('Important', Icons.star_outline, StatusTone.info),
    };

StatusStyle visibilityStyle(ImageVisibility v) => switch (v) {
      ImageVisibility.private =>
        const StatusStyle('Private', Icons.lock_outline, StatusTone.neutral),
      ImageVisibility.selectedDevices => const StatusStyle(
          'Selected devices', Icons.people_outline, StatusTone.neutral),
      ImageVisibility.networkShared => const StatusStyle(
          'Approved group', Icons.group_outlined, StatusTone.neutral),
    };
