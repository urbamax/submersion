# Submersion — experimental Suunto Nautic / Ocean build

**Unofficial fork.** Not affiliated with the Submersion project. GPL-3.0, same as
upstream. Built to let people with a Suunto Nautic / Nautic S / Ocean try a real
full dive log before the driver lands upstream.

Upstream: <https://github.com/submersion-app/submersion>
Driver PR: <https://github.com/libdivecomputer/libdivecomputer/pull/73>
Tracking: <https://github.com/deepsealabs/libdc-swift/issues/29>

## What's different from upstream

- `packages/libdivecomputer_plugin/third_party/libdivecomputer` points at
  [`urbamax/submersion-libdc`](https://github.com/urbamax/submersion-libdc)
  (= Submersion's `submersion-patches` + the Nautic driver/parser from libdivecomputer#73
  + a CI/`<stdint.h>` fix, the event-mapping fix, and the `/Summary` cylinder-size decode)
- the plugin's native build files list the new sources on every platform
  (including the Android and MSVC project files, so all of `submersion-libdc`'s
  CI matrix builds)
- `libdc_download.c` carries water temperature forward between samples
  (the Nautic logs temp far less often than depth — without this the trace is gaps)
- the watch serial is taken from the BLE advertised name (`Suunto Nautic <serial>`)
  and saved on the dive-computer record — it is not in the dive data and the
  driver reports no device info

Everything else is stock upstream Submersion.

## Build & run

Needs the Flutter SDK (see `.github/flutter-version.txt` for the exact version).

```bash
git clone --recurse-submodules https://github.com/urbamax/submersion.git
cd submersion
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# macOS
(cd macos && pod install) && flutter run -d macos
# iOS (needs a signing team — your own free Apple ID works for a local run)
(cd ios && pod install) && flutter run -d <your-iphone>
```

On macOS, in Xcode → Runner → Signing & Capabilities, set the Team to your own
Apple ID; if signing complains about Push/iCloud/App Groups, remove those rows
from `macos/Runner/DebugProfile.entitlements` (a personal team can't provision
them). Keep the Bluetooth entitlement.

Then: **Import → dive computer → Bluetooth scan.** The watch advertises
`Suunto Nautic <serial>` / `Suunto Ocean <serial>` and shows up as
**Suunto / Nautic** (or Ocean).

## Known limitations

- Firmware version isn't shown (it's only available from a live `GET /Info`
  request the driver doesn't make yet). The watch serial is shown; the
  tank-transmitter serial the Suunto app displays is not (its value is computed
  by Suunto from a MAC stored in the `/Summary` and that conversion isn't known).
- The app's own computed events (ascent rate, safety stop) can overlap the
  watch's own on the profile.
- No signed/notarised binary — build it yourself.

## Feedback

Send raw captures (`<logid>.bin` + the Suunto app JSON export) to the tracker
issue above. A dive with a gas switch or two active tank transmitters is the
most useful.
