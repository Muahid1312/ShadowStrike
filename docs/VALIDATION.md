# Phase 5 validation — 2026-10-29

**READY FOR TESTING.** Godot 4.6.3 stable, Debian 13 x86_64. Ubuntu setup instructions are documented; no separate Ubuntu host or physical Android phone was available.

| Workflow | Result |
| --- | --- |
| Exact reusable setup | Passed end to end, with configured full JDK/SDK |
| Training / network / rules / release contracts | 44 + 34 + 13 + 27 = **118 checks passed** |
| Real two-process movement / combat / rounds | 38 / 64 / 66 checks passed |
| Real four-process combat | 114 checks passed |
| Rendered four-process full match flow | 119 checks passed, six captures |
| Capacity/active refusal, timeout/retry, graceful exit and forced host death | Passed |
| Main/settings/training/pause/wide rendered UI | Captured and inspected |
| Fresh generated-template official Gradle Android build | Passed |
| APK signature, manifest, ARM64 payload and ZIP/ELF16KB alignment | Passed |
| Physical Android install/launch and router/hotspot gameplay | **NOT VERIFIED** |
| Android sustained FPS/audio/thermals/touch/cutouts | **NOT VERIFIED** |

The actual APK is `builds/ShadowStrike-debug.apk`, version0.5.0/code5, minimum24/target36, Mobile/Vulkan. It uses a verified debug APK v2 signature and an exported GodotAppLauncher alias. See [complete release report](RELEASE.md) for audit priorities, fixes, structure, exact measurements, limitations, APK hash and release checklist; [Android instructions](ANDROID.md) for install and two-phone acceptance.

Evidence: [setup/contracts](test-results/phase5/setup.txt), [four-peer combat](test-results/phase5/combat-4.txt), [four-peer rounds](test-results/phase5/round-4.txt), [session edges](test-results/phase5/lan-edges.txt), [final build](test-results/phase5/android-build.txt), [manifest](test-results/phase5/apk-manifest.txt), [signature](test-results/phase5/apk-signature.txt), [alignment](test-results/phase5/apk-alignment.txt), [native/payload checks](test-results/phase5/apk-payload.txt), [profile before](test-results/phase5/profile-before.json), [profile after](test-results/phase5/profile-after.json).

All peers are independent real Godot processes with isolated preferences and actual loopback UDP. Test files coordinate fixtures only. Match tests accelerate expiry with 8/6-second rounds and retain/assert the300-second default. This does not prove phone Wi-Fi/hotspot routing or full five-minute device acceptance. Test runners reject game script/engine errors and require completion records; no assertions were disabled. Native synthetic touch and OS-notification injection do not establish physical Android behavior.

Performance observations: idle HUD draws60→0 per60frames, idle target callbacks7→0, flash4224→80triangles; drawcalls226 unchanged. The measured elapsed sample was slower after while build work ran; **no FPS improvement is claimed**. Graphics are desktop software OpenGL, not Mobile/Vulkan device results. See the report for the complete numbers and measurement boundaries.

One fresh-template CLI export printed editor scan-abort/ObjectDB shutdown warnings and an ADB daemon message, returned zero and produced the same independently verified APK checksum. Those export-tool diagnostics are retained separately from clean gameplay test logs. Earlier phases' evidence is historical; [Phase4 validation](PHASE4_VALIDATION.md) and previous source ZIPs are retained.

There is no host migration, historical hit rewind or real loss/jitter benchmark. Device installation/performance, physical audio/input, router/OEM isolation and background suspension remain unverified. The nine-panel reference image was absent, so exact fidelity is unknown. No later phase was started. Environment draft saving is distinct from publication/restoration and GitHub pushing.
