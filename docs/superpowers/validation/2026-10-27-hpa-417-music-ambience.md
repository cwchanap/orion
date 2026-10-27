# HPA-417 music and ambience: native preflight

Date: 2026-10-27

## Discovery

- A physical iPhone was found: `iPhone (4)`, UDID `00008120-000C1DE214B9A01E`, iOS 27.0.1, paired over Wi-Fi. Flutter refused to install because Developer Mode is disabled. The spike did not launch, so it produced no playback or native-player observations.
- Android could not be enumerated because `adb` is not installed. No Android device spike ran.
- The installed dependency set is available offline: `flame_audio` 2.12.2 and transitive `audioplayers` 6.8.1. The app lockfile pins those versions.
- A disposable iOS spike and generated 2-second PCM tone were created under ignored `tmp/` and removed after the install attempt. No project assets or runtime files changed.

## Attempted commands

| Command | Result |
| --- | --- |
| `rtk proxy xcrun devicectl list devices` (sandbox) | Exit 1; CoreDeviceService initialization timed out. |
| `rtk flutter devices` (sandbox) | Exit 1; Flutter SDK cache writes failed with `Operation not permitted`. |
| `rtk proxy xcrun devicectl list devices` (escalated) | Exit 0; found paired physical iPhone `00008120-000C1DE214B9A01E` as available. |
| `rtk flutter devices` (escalated) | Exit 0; found that iPhone wirelessly on iOS 27.0.1. |
| `rtk proxy adb devices -l` | Exit 1; `adb: No such file or directory`. |
| `rtk flutter pub get --offline` (disposable spike) | Exit 0; resolved `flame_audio` 2.12.2 and `audioplayers` 6.8.1 from local cache. |
| `rtk flutter run --no-pub --debug --device-id 00008120-000C1DE214B9A01E` | Exit 1 before install: Flutter requires Developer Mode to be enabled on the phone. |

## Acceptance gates — still pending

- [ ] iOS loop seam listening on a physical device.
- [ ] iOS Silent switch behavior.
- [ ] iOS mixing with other-app music and interruption behavior during calls.
- [ ] Android physical-device playback and interruption behavior.
- [ ] HPA-168 music files, explicit asset declarations, and asset-loop acceptance.

No audible behavior is inferred from package availability or device discovery. The spike did not instantiate `Bgm`, so there is no native constructor result to report.
