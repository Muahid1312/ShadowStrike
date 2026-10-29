> Architecture retained from earlier phases. Current APK status and limitations: [Phase 5 release report](RELEASE.md).

# Offline ENet LAN foundation — retained in Phase 4

Phase 3 adds authoritative combat to this foundation. See [COMBAT.md](COMBAT.md) for the current combat design, changed files and phone acceptance steps.

## Scope and status

Implemented on top of the existing Phase 1 project. Host/join forms, a ready-gated lobby, two-to-four-player spawning, authoritative movement, client prediction/reconciliation, interpolated colored remote models, personal pause menus and session cleanup are working in **local multi-process Godot tests**. No cloud service, account, multicast discovery or external database is involved.

**Physical Android Wi-Fi / hotspot testing: NOT VERIFIED.** No APK exists yet because the Android SDK and exact export templates are missing. See [Android build instructions](ANDROID.md).

## Files created or modified

| Files | Change |
| --- | --- |
| `network/session.gd` (new) | Autoload session lifecycle, roster, validated RPCs, readiness, load barrier, spawn assignments, input queues, snapshots and cleanup |
| `network/match.gd` (new) | Reuse FPSPlayer bodies for host simulation/local prediction; route snapshots to reconciliation and remote visuals |
| `network/avatar.gd` (new) | Lightweight head/torso/arms/legs/rifle, player color/name, look pitch, walking animation and interpolation |
| `ui/lan_panel.gd` (new) | Host/join forms, IPv4 display, capacity/port controls, error feedback and lobby |
| `player/player.gd` | Preserve offline control, share movement simulation, add explicit network roles and prediction/replay |
| `scripts/main.gd` | Add LAN navigation and startup/cleanup; keep training; make LAN pause local to the operator |
| `ui/game_hud.gd` | Real connection/operator indicators and Leave Match; existing health/ammo/touch controls reused |
| `project.godot`, `export_presets.cfg` | Lan autoload, fixed 60 Hz physics, version 0.4.0, Android socket permissions |
| `tests/lan_peer.*`, `tests/lan_edge.*`, `tests/network_contract.*`, `tests/lan_visual.*` (new) | Real-process acceptance, lifecycle edge cases, validation and rendered captures |
| `tools/test_lan.py`, `tools/test_lan_edges.py` (new), `tools/test.sh` | Orchestrate isolated host/client processes; retain training checks and add contract checks |
| `README.md`, `docs/ANDROID.md`, `docs/VALIDATION.md`, this file and evidence/screenshots | Current run, build and test instructions |

The existing arena, targets, rifle implementation, touch HUD input component, settings and art assets were reused. They were not recreated. Settings remain locally persisted. The Phase 1 source archive is retained separately.

## Architecture and authority

One device is both host and an active first-person player. ENet listens on IPv4 UDP **7777**, configurable from **1024–65535**. The server binds all local interfaces; the UI shows available RFC 1918/link-local IPv4 addresses. It does not guess a hotspot gateway. A client types the actual host address directly.

`/root/Lan` has server authority (peer 1). Session metadata and transitions use authority-only reliable RPCs on channel 0. The host derives sender identity from `multiplayer.get_remote_sender_id()`: a client never selects another player's input queue. Player nodes explicitly retain authority 1, including the client-predicted local body. Client prediction is not client authority.

The host owns the roster, capacity, ready state, slot assignments and match phase. At least two registered players and every client's Ready flag are required. A single reliable launch includes distinct server-assigned spawns. Every peer loads the same arena and acknowledges readiness for the current match epoch; the host then releases the load barrier. Duplicate starts are ignored and new connections are refused during loading/play. A 25-second load timeout cleans up rather than leaving half-loaded sessions.

## Movement protocol

- Physics: **60 Hz**, shared CharacterBody3D movement function for prediction and authoritative simulation.
- Input: **20 batches/second** on channel 1, unreliable ordered. Each batch repeats up to 12 recent unacknowledged commands to cover ordinary packet loss.
- Command: sequence number, normalized X/Z movement, yaw, pitch, sprint, jump and aim. Phase 3 also tags input batches with a life identifier so pre-respawn inputs cannot move a new life. **No client position, velocity, delta time, health or arbitrary player ID is accepted.**
- Validation: exact command length/types, finite numbers, bounded axes/angles, boolean actions, monotonically processed sequence numbers, at most 12 commands per batch, 24 queued commands per sender and a 35-batch/second budget. Ready changes are rate limited; unregistered peers have a handshake deadline.
- The host consumes at most one command per operator per fixed physics tick. Queue volume or a large sequence number cannot increase movement speed. An input gap stops repeating movement after 150 ms; jump edges are not replayed on missing packets.
- State: **20 snapshots/second** on channel 2, unreliable ordered, containing peer IDs, position, velocity, yaw, pitch, running/grounded state and last processed input sequence. Match epochs and snapshot ticks reject stale updates.
- Client: immediately predicts local input, resets to acknowledged host position/velocity, replays bounded unacknowledged input at the fixed timestep and smooths small camera corrections. A long backlog favors authority rather than replaying indefinitely.
- Remote rendering: small snapshot buffer and roughly **100 ms** interpolation delay using local receipt timestamps, so clocks need not be synchronized. It freezes the latest sample instead of extrapolating unbounded motion. Remote models do not own cameras, audio listeners, HUDs or controls; Phase 3 adds spatial shot/reload sound emitters.

Player-to-player collision is disabled; bodies collide with the arena. This avoids prediction conflicts between differently timed remote representations. The host keeps the authoritative remote physics bodies; clients only need their own predicted body and visual proxies for others.

These rates are design limits, not measured Wi-Fi bandwidth/FPS claims. Real Android jitter, packet loss, thermals and latency require device testing.

## Lifecycle and errors

Client connection/registration has a **10-second application timeout**. Full lobbies, active matches, unreachable hosts and refused transports produce an actionable error and leave the join form usable. Names are limited to 1–20 printable characters; direct numeric IPv4 and valid unprivileged UDP ports are required. Compatible builds use an explicit protocol version.

Host departure sends a shutdown notice when possible; unannounced host loss is caught by transport disconnection or the client's six-second snapshot watchdog. Clients return to the menu, drop the ENet peer, clear rosters/queues and discard the old match. There is no host migration. A departing client is removed from the roster, authoritative bodies and remote visuals. During an active match, remaining operators may continue even if only the host remains; creating a new match still requires a new lobby with two players.

LAN pause/Settings disables local input and clears held contacts; it does not pause the shared tree. The host continues to simulate everyone. Training retains full-tree pause. Keep the host app in the foreground: Android can suspend its event loop in the background, which will end connectivity for clients.

## Test with two Android phones

1. Build one debug APK following [ANDROID.md](ANDROID.md), and install the same build on both phones. Both must be ARM64 with a working Vulkan driver for this Mobile preset.
2. Connect both to the **same non-guest Wi-Fi**. Disable mobile data for this acceptance run if desired, so success cannot be mistaken for an internet service dependency. Leave local Wi-Fi enabled.
3. On phone A, choose **HOST GAME**. Enter a name, capacity 2 (or 3–4 for additional phones), port **7777**, then Host Game. Note all displayed private IPv4 addresses.
4. Select the host address belonging to the shared Wi-Fi network. On B, choose **JOIN GAME**, enter its own name, that address and **7777**, then Join Game. Do not enter `127.0.0.1` on a second phone.
5. Confirm both names appear on both screens. On B choose **READY**. Confirm the host's Start Match becomes enabled; try unready first to verify the gate, then ready again. A chooses **START MATCH**.
6. After both enter the arena, turn to find the other operator. Move independently, sprint, jump and swipe-look. Confirm color/name labels and head orientation track the other player. Verify each phone retains its own first-person camera, rifle and touch controls.
7. Open A's pause menu while B moves. B must keep moving; resume A. Verify B's pause menu similarly. Check the synchronized elimination feed/counters. Open SCORES to inspect live rankings; verify the timer continues. Full results/rematch acceptance is in [MATCHES.md](MATCHES.md). Ping display remains absent.
8. Leave on B: A should see B disappear and its operator count decrease. Start a fresh session and rejoin. Then leave/close the host: B should receive a notice and return to the menu. Also force-stop A to exercise unexpected host loss.
9. Try an additional phone during an active match and beyond lobby capacity; it must not be admitted. Test an incorrect address/port and confirm bounded failure and retry/back controls.
10. Repeat with a **phone hotspot**: A can host the hotspot and the game, with B joined to it. Use the hotspot interface's actual address shown on A, or the actual gateway/interface information from device settings if enumeration is unavailable. Never assume `192.168.43.1`.
11. If hosting from the hotspot owner is blocked by that device's routing, use a router, or a third phone's hotspot with both players joined as stations. Document the exact phone/OS/network combination; do not treat a workaround as universal hotspot support.
12. With internet/mobile data off, repeat movement and disconnect checks. Check sustained Low/Balanced/High FPS, touch cancellation, audio, soft-keyboard layout and app backgrounding on hardware before accepting the Android build.

## Android / LAN compatibility notes

- Android **INTERNET** is the normal permission required to create sockets, including offline UDP. **ACCESS_NETWORK_STATE** is also configured. No internet API, multicast lock, location permission, Wi-Fi scan or discovery service is used. This build targets API 35; local-network policies/prompts can change on newer Android versions or OEM builds and need physical verification.
- A missing SIM or disconnected upstream internet does not prevent a usable local network, but some phones prefer cellular/VPN routes or disconnect Wi-Fi marked “no internet.” Confirm the active network remains connected to the intended hotspot/router.
- Guest Wi-Fi, AP/client isolation and some hotspots block peer traffic. The game cannot override this. Verify host-to-client reachability or use a different network.
- Host UDP 7777 (or the chosen port) and return UDP traffic must be permitted. Desktop firewall rules apply when mixing Android and Ubuntu; no TCP listener is used. Never expose this LAN test server through a router port forward.
- IP/interface enumeration on Android can be incomplete; multiple private addresses can include tethering/VPN interfaces. The displayed list is a set of candidates, not proof that an address is reachable from a given client. Changing networks requires leaving and creating/joining again.
- This is IPv4-only direct joining, without multicast discovery, passwords, encryption, host migration or late-join state transfer. Test on a trusted local network. The protocol validates gameplay inputs; it is not a public-internet service hardening effort.

## Current limits

Phase 3 extends this foundation with server-authoritative combat, critical state replication and respawns; the former local-only weapon limitation no longer applies in LAN combat. See [COMBAT.md](COMBAT.md) for current authority and hit-registration boundaries. Player-to-player physical collision remains disabled, while dedicated server body/head hitboxes participate in shooting queries.

Prediction remains simple; no clock synchronization, historical rewind or WAN latency guarantees are provided. Remote models remain original block geometry. Physical Android Wi-Fi/hotspot behavior and performance are not verified. There is no host migration. Phase 4 adds a host round timer, full scoreboard, victory/results and rematches; see [MATCHES.md](MATCHES.md).

Phase 4 uses protocol 4 and a pure listen-host star: Godot client relay is disabled because no gameplay RPC is peer-to-peer. Host broadcasts target only ENet peers still in CONNECTED state, avoiding sends to channels already closing during simultaneous departures. Rematches retain the existing ENet connection and reopen the lobby.
