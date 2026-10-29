# ShadowStrike 0.5.0 — READY FOR TESTING

Phase 5 stabilizes the existing game and produces a real Android debug APK. Training and the host-authoritative 2–4-player offline LAN Free-for-All remain intact. **Physical Android installation, hotspot play and device performance are NOT VERIFIED. This is not READY FOR RELEASE.** No subsequent development phase has been started.

## Deliverables and APK identity

| Item | Result |
| --- | --- |
| Debug APK | `builds/ShadowStrike-debug.apk` |
| SHA-256 file | `builds/ShadowStrike-debug.apk.sha256` |
| Size | 79,686,858 bytes, about 76 MiB |
| App / identifier | ShadowStrike / `com.shadowstrike.training` |
| Version / protocol | 0.5.0, code 5 / protocol 4 |
| Device / renderer | ARM64 only; landscape, immersive; Mobile/Vulkan |
| Effective SDK | Minimum API 24, target/compile API 36 |
| Signing | Debug certificate; APK v2 signature verifies (API 24+) |
| Alignment | ZIP 16 KB page alignment and both native libraries' ELF LOAD alignment pass |
| Manifest | Correctly typed Vulkan requirements, landscape and exported launcher alias verified |
| Runtime networking | ENet UDP7777 by default; INTERNET/ACCESS_NETWORK_STATE; no HTTP/backend/account service |

SHA-256:

```text
a383022d7bcd6b684221188a37b7775307ebe0e696247b00770e90749f605cd8
```

The final helper was tested after moving away all generated Android build files: it recreated the official template and successfully rebuilt the same APK checksum. The generated template, SDK/JDK, Gradle caches and debug keystore are outside the source archive. Source is independently usable with the documented dependencies. The APK bundles its game assets and ARM64 runtime, and excludes tests/docs/tools. It includes only the two ARM64 native libraries, with no other ABI payload. Native libraries remain uncompressed/page-aligned for direct loading; this accounts for much of the APK size compared with the superseded compressed stock export.

## Prioritized audit and fixes

| Priority | Confirmed issue | Resolution |
| --- | --- | --- |
| P1 packaging | SDK and exact export templates absent | Installed official SDK tools and SHA-512-verified Godot 4.6.3 templates |
| P1 packaging | SDK overrides rejected by stock-template exporter | Removed overrides; now inherit API 24/36 from the matching template |
| P1 packaging | Android ETC2/ASTC texture import absent; exporter failed with an empty configuration message | Enabled Android texture imports and added a regression assertion |
| P1 packaging | Stock Godot exporter wrote Vulkan feature values as strings, causing an AAPT diagnostic | Switched packaging to the official Gradle template; AAPT now reports typed boolean/integer attributes without errors |
| P1 tooling | Installed Java was a runtime without javac | Installed a full OpenJDK 21.0.13 compiler/runtime and made configure_android.py require javac |
| P2 efficiency | HUD repainted every frame while idle | Redraw only for changing hit/damage feedback or resize; avoid repeating life-font overrides; update visible FPS text at 4 Hz |
| P2 efficiency | All seven available targets ran idle frame callbacks | Enable processing only during their 0.65-second hit cooldown |
| P2 geometry | Tiny muzzle flash used the default 4,224-triangle sphere | Use an 80-triangle sphere, retaining the same size/color/flash duration |
| P2 UI | Middle quality preset was named BALANCED | Renamed to MEDIUM; all three presets tested against actual renderer/shadow/fog state |
| P2 build robustness | Export wrote directly over the last successful build; fresh source needed generated Android files | Build into a temporary directory, validate ZIP/ARM64/assets, promote only on success and write a portable checksum; recreate template when absent |

No new gameplay-authority or synchronization defect was confirmed in Phase 5. Network/session, match/rules, combat authority, player movement, touch HUD, arena and remote-avatar scripts are byte-identical to Phase 4. They were exercised through real independent processes rather than rewritten. A release-test teardown initially quit with reload audio still being mixed; the harness now stops playback and allows audio cleanup before exit. Final gameplay/contract suites have no engine errors or resource-leak warnings.

## Verification results

| Test | Actual result |
| --- | --- |
| Parse/import + original training integration | 44 checks passed |
| Network/export/UI contracts | 34 checks passed |
| Match/ranking/menu-touch contracts | 13 checks passed |
| Phase 5 graphics/input/lifecycle/audio/export regression | 27 checks passed |
| Two-process movement/session | 38 checks passed |
| Two-process combat | 64 checks passed |
| Two-process timer/results/rematch | 66 checks passed |
| Four-process authoritative combat | 114 checks passed |
| Four-process rounds with rendered host | 119 checks passed; six captures |
| Full/active refusal, timeout/retry, graceful exit, forcibly terminated host | Passed |
| Rendered menu/settings/training/pause/wide layout | Captured and inspected; no observed overlap/clipping in tested viewports |
| Python/shell helper syntax | Passed |
| Official Gradle debug export | Passed, including fresh generated-template recreation |
| APK ZIP/payload/ABI, AAPT manifest, apksigner and zipalign | Passed |
| Native ELF page alignment | Both libraries pass ≥16 KB LOAD alignment |
| Physical Android install/launch | NOT VERIFIED; adb listed no devices |
| Two-to-four-phone router/hotspot match | NOT VERIFIED |
| Sustained phone 30–60 FPS, thermals, battery and audio | NOT VERIFIED |

Tests use real separate Godot scene trees and ENet peers over loopback UDP. Shared files coordinate fixtures, not gameplay state. They cover names/ready/start/load barrier, countdown freeze, movement/prediction, actual raycast body/head/cover damage, ammo/reloads, one-time kills/deaths/scores, invalid/old-life/flooded requests, respawn/protection, authoritative time, deterministic winner, frozen results, client departure, host-only rematch/reset and simultaneous departures. Short 8/6-second rounds accelerate acceptance; 300 seconds remains the asserted default. A full five-minute phone session has not been run.

The release regression exercises native Input.parse_input_event touch emulation, joystick without accidental shooting, concurrent movement/fire at the expected 600 RPM, emulated mouse-look filtering, reload, background-notification input clearing/resume, real master-bus volume and on-screen separated controls at 1280×720, 1440×720 and 1600×720 logical dimensions. These are synthetic tests, not physical touchscreen acceptance.

Evidence is under [test-results/phase5/](test-results/phase5/) and [the validation index](VALIDATION.md). Godot export reports harmless ADB-daemon connection messages without an attached device. The fresh-template CLI export also printed editor scan-abort/ObjectDB cleanup warnings on shutdown; it returned zero and the rebuilt APK passed all independent checks. Those export-editor warnings are distinct from the clean game test runs and are retained in the build log. No assertions were removed to obtain passing results.

## Performance findings

Same 60 idle rendered frames, desktop OpenGL Compatibility / Low / Mesa llvmpipe on the Debian 13 cloud host:

| Measurement | Before | After |
| --- | --- | --- |
| HUD custom draw invocations | 60 | 0 |
| Idle target process callbacks scheduled per frame | 7 | 0 |
| Muzzle-flash mesh triangles | 4,224 | 80 |
| Observed scene draw calls/frame | 226 | 226 |
| Godot static allocation monitor | 49,033,398 bytes | 48,153,922 bytes |
| Elapsed for sampled 60 frames | 1,079 ms | 1,334 ms |

The elapsed sample was slower after the changes while export work was running, so it demonstrates **no FPS improvement**. The measured reductions concern idle callbacks, redraw work and flash geometry. Allocation numbers exclude much of driver/GPU memory and are not Android RSS measurements. Draw-call count is unchanged. No device performance target is claimed; real profiling must decide whether geometry batching or other larger changes are necessary.

LOW applies 65% render scale, no sun shadows/fog and no MSAA. MEDIUM (default) applies 85%, shadows/fog, no MSAA. HIGH applies 100%, shadows/fog and 2× MSAA. Tests verify actual properties, not selector text. Materials are shared, geometry/collisions remain simple, impacts are bounded, physics stays at 60 Hz and network movement/snapshots remain capped at 20 Hz. Combat intent heartbeat is 10 Hz, host-clock correction 5 Hz, and scoreboard refresh remains event-driven. No phone bandwidth benchmark was performed.

Existing rifle/reload sounds use bounded per-player audio sources and the master bus. Hit/elimination/menu/victory feedback remains the existing visual presentation; no soundtrack or additional sound assets were introduced. Physical speaker quality/mixing is not verified.

To reproduce the profile with an available display, use isolated XDG directories and:

```bash
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 ./tools/godot.sh \
  --rendering-method gl_compatibility --audio-driver Dummy \
  --script res://tests/performance_profile.gd -- /absolute/path/profile.json
```

The display must actually exist. This desktop override does not alter the Android Mobile renderer.

## Structure and changed files

```text
ShadowStrike/
  project.godot, export_presets.cfg
  scenes/, scripts/          entry, settings, shared geometry and navigation
  player/, weapons/, maps/   preserved gameplay and original procedural assets
  network/, combat/         host session, prediction, combat and round authority
  ui/                       theme, menus, touch HUD, scoreboard and results
  assets/                   original icon/audio and licensed Open Sans fonts
  tests/                    retained integration plus release audit/profile
  tools/                    run, test, Android configuration and atomic build helpers
  docs/                     reports, screenshots, evidence and device checklist
  builds/                   actual APK and SHA-256; separate from source ZIP
  android/build/            generated official template; recreated by build helper
```

Phase 5 modifies project/export settings, main-menu version text, settings/HUD, rifle flash, target cooldown scheduling, configure_android.py, build_android.sh, test.sh, .gitignore and documentation. It adds release_audit.gd/tscn, performance_profile.gd, fresh screenshots and release evidence. The exact manifest, signing and provenance records accompany this report.

## Release checklist and next action

- [x] Desktop game launches; retained training/menu/settings/navigation tests pass.
- [x] Actual local ENet connection, movement, combat, completion and rematch tests pass with two/four processes.
- [x] No critical gameplay crashes observed in tested paths.
- [x] Real ARM64 APK built, signed and independently inspected.
- [ ] Physical Android installation and launch succeed.
- [ ] Two-phone hotspot and shared-router acceptance complete.
- [ ] Four-phone acceptance and default five-minute session complete.
- [ ] Actual touch/audio/cutouts/lifecycle/performance/thermals acceptable on target devices.
- [ ] Production signing/distribution acceptance complete.

Follow [ANDROID.md](ANDROID.md) for exact build/install commands, two-phone A-hotspot/B-client steps and troubleshooting. The launcher component is `com.shadowstrike.training/com.godot.game.GodotAppLauncher`. A different signing certificate requires uninstalling an older package before installation.

The nine-panel reference image was never supplied, so exact visual fidelity cannot be verified. Known retained limits are no host migration/historical hit rewind, trusted unencrypted LAN hosting, lightweight art/audio, no realistic loss/jitter benchmark and possible host suspension by Android. Universal hotspot compatibility and production readiness are not claimed. No blocking defect remains in the exercised source/packaging paths; the outstanding device checks keep the verdict at **READY FOR TESTING**.
