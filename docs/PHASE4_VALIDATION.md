Historical Phase 4 evidence; current results are [Phase 5](VALIDATION.md).

# Phase 4 validation — 2026-10-29

Runtime: Debian 13 Linux x86_64, **Godot 4.6.3.stable.official.7d41c59c4**. Ubuntu setup/build instructions are provided; no separate Ubuntu installation or physical Android device was available.

## Executed results

| Workflow | Actual outcome |
| --- | --- |
| Exact reusable setup sequence | Editor import, training/contracts, two-process movement, combat and full round acceptance |
| Original training integration | **44 checks, 0 failures** |
| Network/configuration/UI contracts | **34 checks, 0 failures** |
| Match rules and synthetic GUI tap | **13 checks, 0 failures** |
| Two-process full round acceptance | **66 checks, 0 failures** |
| Four-process full round with rendered host | **119 checks, 0 failures**, six rendered captures |
| Retained two-process LAN movement | **38 checks, 0 failures** |
| Retained four-process LAN movement/dead-player disconnect | **90 checks, 0 failures** |
| Retained two-process combat acceptance | **64 checks, 0 failures**, including synthetic multitouch |
| Full/active refusal, timeout/retry, forced host loss | Passed |
| Shell/Python helpers | Syntax/compilation checks passed |
| Actual Android debug export | **Failed**: exact templates and Android SDK tools missing; no APK |

Evidence: [full setup/training/contracts](TEST_RESULTS.txt), [two-peer rounds](test-results/round-2.txt), [rendered four-peer rounds](test-results/round-4.txt), [two-peer combat](test-results/combat-2.txt), [four-peer movement](test-results/lan-4.txt), [session edges](test-results/lan-edges.txt), [actual Android exporter](test-results/android-export.txt). Earlier Phase 3 combat-4 evidence is retained with its original label; it is not a claim of another Phase 4 four-peer combat run.

## Real processes and test fixtures

Every participant is an independent Godot OS process with its own ENet peer, scene tree and isolated preferences. Gameplay state crosses actual loopback UDP. Files only coordinate fixtures and record acceptance results. Runners preserve exit codes, require completion markers and reject unexpected script/engine errors. No mocked transport replaces gameplay RPCs. Rendered tests use an existing virtual X display and **OpenGL Compatibility / Low / Mesa llvmpipe**, not the Android Mobile renderer. The virtual driver warns that V-Sync mode changes are unsupported.

Round acceptance uses an 8-second timer round and a 6-second kill-limit round, then a countdown cancellation. The five-minute default is asserted independently; a full five-minute physical session has not been executed. Host-only fixtures place stationary actors in known clear lanes to isolate real raycast scoring, without trusting client positions. Existing combat fixtures additionally cover body/head damage, inserted physical cover and final-reserve reload transfer. Fixtures are test code, not player controls or remotely callable gameplay setters.

## Match behaviors exercised

- Host start/ready gates, all-scenes-ready barrier, one three-second countdown and rejected duplicate/unauthorized transitions.
- Movement/fire/reload blocked during countdown even through the raw request path; real host and client control during PLAYING.
- Initial 100 HP, 30/120 ammunition and fresh zero stats for every peer.
- Actual host-authoritative elimination updates all boards: one elimination, one death, exactly 100 points, no death penalty. Duplicate elimination and repeated notification do not rescore.
- Deterministic ranking contracts cover eliminations, deaths, stable ID and derived scores without mutating source records.
- Clients compare host timing within test tolerance using local receipt time; no synchronized wall clock. A personal pause leaves the host timer and other peers running.
- Scoreboard elements are not rebuilt each frame; all displayed scores are replicated combat state.
- Timer expiry freezes movement/combat/statistics and gives every peer the same winner and complete result snapshot. Late fire/duplicate combat events leave results unchanged.
- A client departs during four-player RESULTS; all remaining peers retain the identical frozen four-row results, then rematch as three connected players.
- Clients cannot return to lobby themselves. Host return retains peer IDs/names, resets client ready flags and old bodies/records/input, then creates a fresh epoch/loadout/health/stats/timer without duplicate player nodes.
- Kill limit 1 ends the second round before time expiry, consistently across peers.
- Peers leave simultaneously during another countdown; host safely returns to a one-player lobby and cannot start alone.
- Existing movement/disconnect and combat tests still pass. Edge tests forcibly terminate the host without a graceful shutdown RPC and verify clients recover to a clean menu.

The preserved training suite covers menus/settings/persistence, movement/sprint/jump/gravity, raycast targets, training ammunition/reload, pause/resume and touch ownership. Combat acceptance checks 20/40 body/head damage, cover, protection, ammo/fire-rate validation, reload exclusion/conservation, duplicate/flooded/old-life requests, deaths/feed, three-second respawn and two-second protection. Synthetic simultaneous move/aim/fire/look and touch reload exercise shipped HUD wiring. Standard GUI touch emulation is now separately tested through Input.parse_input_event and a real Button, with window-coordinate scaling accounted for.

The arena/targets, touch HUD, settings, shared geometry, rifle and remote avatar scripts were compared byte-for-byte with the retained Phase 3 ZIP and are unchanged. Round gates are targeted additions around existing player/session/combat systems.

## Fixes found during validation

- A typed-dictionary result oracle initially compared JSON-deserialized floats with authoritative integers. The oracle now uses Godot Variant serialization to preserve exact numeric types; full equality assertions remain intact.
- Simultaneous disconnects exposed native ENet sends to already closing channels. Host broadcasts now filter peers by ENet CONNECTED state. Godot's unused client-to-client relay is disabled for this star topology, avoiding its own departure forwarding to closed peers. Final four-process tests contain no engine errors.
- Standard menu buttons needed touch-to-mouse emulation. It is enabled, with emulated mouse look filtered and explicit Android touch fire preserved. GUI taps and simultaneous combat touch tests pass synthetically.

No required assertions were removed or disabled. Captures `screenshots/phase4-{host,countdown,scoreboard,playing,results,rematch-lobby}.png` were rendered and inspected at 1280×720. Timer/header spacing, four-player table rows and result navigation fit without overlap in that viewport.

## Android and unverified boundaries

Version **0.4.0/code 4**, ARM64, Mobile/landscape and INTERNET/ACCESS_NETWORK_STATE are configured. A real debug export returned exit 1 because exact `4.6.3.stable/android_debug.apk` / `android_release.apk`, SDK adb and build-tools/apksigner are missing. Java 21 is configured and accepted. **No APK exists.** Follow [ANDROID.md](ANDROID.md) and the [Phase 4 phone checklist](MATCHES.md#android-acceptance--not-executed).

**Physical Android two-to-four-phone Wi-Fi/hotspot matches: NOT VERIFIED.** Also unverified: Mobile/Vulkan rendering, physical multitouch/cancellation, audio, soft keyboards/cutouts, wider phone aspect ratios, sustained 30–60 FPS/thermals, AP/OEM routing, realistic injected packet loss/jitter and hostile-network hardening. There is no historical hit rewind or host migration. Loopback/software rendering is not device performance evidence.

The nine-panel UI reference image was absent, so exact fidelity is unknown. Art/audio remain lightweight prototypes. Phase 5 has not been started. Environment draft persistence, publication, fresh-task restoration and GitHub pushes are separate outcomes; saving setup instructions does not publish or push the project.
