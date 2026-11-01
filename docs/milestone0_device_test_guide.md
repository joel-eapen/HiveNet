# Milestone 0: device test guide

Goal: settle the eight mobile compatibility checks in PRD section 10.6 on real phones, before building the full gallery and replication.

The test harness is a developer screen in the app: **Settings → Feasibility spike (developer)**. Its code is in `hivenet/lib/spike/` and is throwaway. It uses its own simple wire format, not the production protocol.

## Status so far (Android emulator only)

| # | Check | Result |
|---|---|---|
| 1 | Local-network permission handled | Not testable on the emulator. Needs an iPhone for the prompt. |
| 2 | Two devices discover each other | Not testable on the emulator. Needs two phones. |
| 3 | Framed TCP transfer in chunks | Partial. 5 MiB, 1 MiB chunks, per-chunk ACK, SHA-256 verified over loopback. |
| 4 | Interruption and resume | Partial. Dropped at 2,097,152 bytes and resumed from exactly that offset (loopback). |
| 5 | JPEG and HEIC import | Partial. PNG to JPEG works. HEIC untested. |
| 6 | Cross-platform decode and hash | Needs two different platforms. |
| 7 | Key survives restart | Pass on the Android emulator (Keystore). Repeat on a real Android phone and an iPhone. |
| 8 | Backgrounded peer goes unavailable | Needs two phones. |

`dart`/`flutter` unit tests also cover the framing code: byte-by-byte delivery, coalesced frames, a 1 MiB chunk across uneven reads, oversized and malformed frames.

## Findings already recorded

- **`flutter_image_compress` does not cap size.** `minWidth` and `minHeight` are lower bounds, so asking for 2048 left a 3000x2000 image unchanged. The production compressor must read the input size and compute the exact target itself, never upscaling. Verified: 3000x2000 became 2048x1365.
- EXIF (including GPS) is stripped with `keepExif: false`. The spike checks the output bytes for an EXIF marker.
- `bonsoir` takes the Android multicast lock itself, so no extra lock code is needed.

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
