# Milestone 0: device test guide

Goal: settle the eight mobile compatibility checks in PRD section 10.6 on real phones, before building the full gallery and replication.

The test harness is a developer screen in the app: **Settings → Feasibility spike (developer)**. Its code is in `hivenet/lib/spike/` and is throwaway. It uses its own simple wire format, not the production protocol.

## Scope decision: Android only (for now)

iPhone support is deferred. The iOS configuration (`NSLocalNetworkUsageDescription`, `NSBonjourServices`) stays in the project but is untested, and nothing here depends on it. Checks that need an iPhone are marked out of scope below, not failed. Revisit when an iPhone and full Xcode are available.

## Status so far

Devices: Android emulator (API 37), motorola edge 60 pro (Android 17), V2117 (Android 13).

| # | Check | Result |
|---|---|---|
| 1 | Local-network permission handled | **Out of scope** (iOS-only prompt). |
| 2 | Two devices discover each other (mDNS) | **Pass** between the two real phones, both directions, on a phone hotspot. **Fails on the campus Wi-Fi** (see findings). |
| 3 | Framed TCP transfer in chunks | **Pass** between real phones: 5 MiB, 1 MiB chunks, per-chunk ACKs, SHA-256 verified by the receiver. |
| 4 | Interruption and resume | **Pass**: dropped at 2,097,152 bytes, resumed from exactly that offset, including to an mDNS-discovered peer. |
| 5 | JPEG and HEIC import | **Pass on Android** on two phones. |
| 6 | Cross-device decode and hash | **Pass for Android to Android** (receiver verifies the SHA-256 on every transfer). The final compressed-image send between the two phones was not observed to completion, so image decode on the receiving phone is exercised only by the transfer hash check. Cross-platform with iOS is out of scope. |
| 7 | Key survives restart | **Pass** on the emulator and on the Motorola's Keystore. Reboot untested. |
| 8 | Backgrounded peer goes unavailable | **Pass** (emulator backgrounded; phone marked it unavailable at about 40 s). |

## Findings

- **`flutter_image_compress` does not cap size.** `minWidth`/`minHeight` are lower bounds, so asking for 2048 left a 3000x2000 image unchanged. The production compressor must read the input size and compute the exact target, never upscaling.
- **Rotation is applied and EXIF/GPS is removed.** A JPEG with GPS coordinates and a "rotate 90" tag came out rotated correctly (the marker square moved to the expected corner) with no EXIF, on both phones. A 4000x3000 input came out 1536x2048 (longest side 2048).
- **HEIC decodes on Android.** A HEIC file was converted to JPEG on both phones (Android 13 and 17), so HEIC does not have to be rejected on Android. Real iPhone HEIC from Photos is still untested.
- **Compression is repeatable on one device but differs between devices.** The Motorola gave identical bytes across runs. The V2117 gave different bytes for the same input, with the same dimensions and the same visual result. So the same photo uploaded from two different phones gets two different content IDs. Consequences: the content ID must be computed once, by the uploader, on the exact bytes that are stored. A receiver must never re-compress and re-hash. The PRD already says the ID depends on the exact compressed bytes; this confirms it matters in practice.
- **Backgrounding.** An emulator's app kept heartbeating for about 20 seconds after being sent to the background, then stopped. The peer was marked unavailable at about 40 seconds. After the app came back to the foreground it did not reconnect on its own, so the production heartbeat needs automatic reconnection. This was an emulator, so real phones may differ.
- **Campus Wi-Fi (NITJ-WiFi) allows device-to-device traffic** in this test (pings and TCP worked both ways). This will not hold on every network; the app must say so when peers are unreachable.
- `bonsoir` takes the Android multicast lock itself, so no extra lock code is needed.
- **mDNS is blocked on the campus Wi-Fi (NITJ-WiFi) but works on a phone hotspot.** On NITJ-WiFi the phones could ping each other and open TCP connections, but neither saw the other's mDNS broadcast, and a service the Mac advertised was invisible to both phones. The network drops multicast between devices. On a phone hotspot both phones discovered each other and resolved the correct address and port. Pairing therefore must not depend on mDNS: the pairing QR code carries the address and port, and manual connect stays as a fallback.
- **The emulator cannot test mDNS.** It sits behind a virtual network. Manual connect by IP works.

## What you need

- Two phones on the **same Wi-Fi**. Not a guest network, and not one with client isolation.
- Android phones: USB debugging on, connected with a data cable, `adb devices` listing them.
- An iPhone needs full Xcode and CocoaPods installed on the Mac first (not done yet).

## Running the app on a phone

```sh
cd hivenet
flutter devices                      # note the device ids
flutter run -d <device-id>           # run once per phone
```

Open Settings → Feasibility spike on each phone. The screen shows the node id, platform, TCP port and local addresses.

## Procedure

Run these in order. The checklist at the top of the screen turns PASS, PARTIAL or FAIL by itself.

1. **Discovery and permission (checks 1, 2).** On both phones tap **Start mDNS advertise + discover**. On iOS, an "allow local network" prompt must appear. Each phone should list the other under *Discovered peers* within 5 to 10 seconds. Then, on iOS, deny the permission, restart and confirm the app shows a failure instead of hanging. If discovery fails on both, try the **Manual connect** fields with the other phone's IP and port.
2. **Transfer and resume (checks 3, 4).** On a discovered peer tap **5 MiB + resume**. The log should show the drop at 2 MiB and the resume from the same offset. Do it in both directions.
3. **Import (check 5).** Tap **Pick image and compress**. Pick a normal JPEG. On an iPhone, also pick a HEIC photo from Photos. Read the log: it states what format the picker actually delivered, and what came out. If HEIC fails, the PRD says to reject it with a clear message; note which behaviour you get.
4. **Cross-platform decode (check 6).** Compress an image on one phone, tap **Send compressed image** to the other. The receiver shows the image and reports it decoded with the matching hash. Repeat Android to iPhone and iPhone to Android.
5. **Key persistence (check 7).** Note the key fingerprint, fully close the app (swipe it away), reopen the spike screen. The same fingerprint must appear. Also try after a device reboot.
6. **Background behaviour (check 8).** On both phones tap **Heartbeat link** toward the other. Check that *Heartbeats received* shows the peer as online. Put one phone's app in the background (home button) for about 30 seconds. On the other phone, the peer should turn UNAVAILABLE. Bring it back and see whether it recovers. Do this once with an Android and once with an iPhone in the background: iOS is expected to suspend, Android may not.

## Recording results

Copy each check's final line from the screen, plus the log, into a note for the team. Record the phone models and OS versions. A check marked PARTIAL has only worked on one device. For check 8, confirm the peer disappeared because the app was backgrounded and not because the Wi-Fi dropped.

## Decisions this milestone should produce

- The cross-platform image output format (JPEG or WebP).
- How HEIC is handled: converted, or rejected with a message.
- Whether `bonsoir` is reliable enough on both platforms, or needs a fallback.
- The heartbeat lease length, if 15 seconds proves wrong in practice.
