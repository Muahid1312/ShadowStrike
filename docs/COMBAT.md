> Architecture retained from earlier phases. Current APK status and limitations: [Phase 5 release report](RELEASE.md).

# Authoritative LAN combat — retained in Phase 4

Phase 3 extends the existing Godot 4.6.3 project. Training, settings, touch ownership, ENet lobbies and predicted movement are retained. No account, internet server or database is used. Physical Android Wi-Fi/hotspot testing is **NOT VERIFIED**; the current evidence is from independent Linux Godot processes and a rendered desktop fallback.

## Implemented features

| System | Behavior |
| --- | --- |
| Rifle | Automatic 600 RPM; 30-round magazine / 120 reserve in LAN; approximately 2-second reload |
| Hits | Host raycast; world cover blocks bullets; separate body/head colliders deal 20/40 HP |
| Health | 100 HP, host reduction only, zero floor, no damage to dead/protected targets |
| Feedback | Confirmed recoil, muzzle flashes, shot/reload sounds, bounded impact geometry, gold hitmarkers, red damage-direction indicator |
| Elimination | Stop movement/shooting, disable hitboxes, lower local death camera, lightweight remote slump, reliable notification/feed |
| Respawn | About 3 seconds; clear-spawn capsule query and living-player spacing; 100 HP and fresh 30/120 loadout |
| Protection | About 2 seconds after initial spawn/respawn, gold remote ring and local notice; ends on an accepted shot |
| Stats | Authoritative eliminations/deaths, small local HUD counter, four-entry timed kill feed |
| Controls | Existing hold FIRE, AIM, joystick/look and reload; LAN personal pause still keeps shared simulation alive |

Training keeps its original 30/150 ammunition and 1.7-second reload so its existing drill and regression behavior remain intact. LAN balancing is owned by the new combat authority. Phase 4 adds the [round authority, scoreboard, results and rematch flow](MATCHES.md); combat is gated to PLAYING.

## Changed files

| File | Responsibility |
| --- | --- |
| `combat/authority.gd` (new) | Server state, validated intent, cooldown/reload, hit queries, damage, stats, death, safe spawn and protection |
| `network/session.gd` | Combat request/state/event RPCs, revision/event deduplication, life IDs, sender identity and disconnect cleanup; protocol version 4 |
| `network/match.gd` | Connect the existing player/rifle to server state, collect local intent, apply life changes and render confirmed effects |
| `player/player.gd` | Distinct host hitboxes, alive state, shot exclusions, dead movement suppression, fall reporting and respawn reset |
| `weapons/rifle.gd` | Preserve offline simulation; network mode only presents authoritative ammo/reload and confirmed shot effects |
| `network/avatar.gd` | Spatial shot/reload audio, muzzle flash, reload tilt, protection ring, death/respawn presentation |
| `ui/game_hud.gd` | Real health bar, ammo/reload, hit/damage feedback, elimination stats/feed and respawn/protection notices |
| `scripts/main.gd` | Phase/version label; existing screen and personal-pause flow reused |
| `project.godot`, `export_presets.cfg` | Version 0.4.0/code 4; Mobile/ARM64/landscape and LAN permissions retained |
| `tests/combat_peer.*`, `tools/test_combat.py` (new) | Actual host/client combat acceptance, with optional rendered host captures |
| `tests/lan_peer.gd` | Preserve movement tests; life argument and explicit combat-record cleanup assertion |
| `README.md`, `docs/` | Current instructions, architecture, Android checklist and recorded evidence |

The arena, targets, original touch-input implementation, saved-settings implementation and art are reused. No unrelated repository refactor was performed.

## Authority and hit validation

The listen host owns every health/ammo/stat/timer record. A client sends a match epoch, increasing request sequence, life identifier, held-fire/reload intent, bounded yaw/pitch and its movement sequence. It sends **no shot origin, hit point, victim, damage, health, kills or ammunition**. The server selects the operator from `multiplayer.get_remote_sender_id()`; a payload cannot name another shooter.

Requests are checked against the current roster/match/life, sequence, alive state and a 35-request/second budget. Aim must be finite, yaw within ±π and pitch within ±84°. The authoritative physics loop applies the 0.1-second cooldown, available magazine and reload rules. Hundreds of requests cannot create hundreds of shots. A short rising fire edge is retained until the next physics tick, so a press/release received in one update is not lost; it still obeys cooldown and ammo. Held intent expires after 300 ms without refresh.

Reliable fire can arrive before its related movement-channel packet. The press therefore includes validated aim, latched for its opening shot. Sustained fire uses the newer validated movement/intent aim. **Position always comes from the host's simulated player body**, with a fixed 1.65 m eye offset. Client camera bob, local correction offsets and arbitrary origins are never used for hit testing.

The server raycasts up to 150 m against arena layer 1, body-hitbox layer 4 and head-hitbox layer 8. Player movement capsules use layer 2 and are omitted from this shooting mask. Both shooter-owned hitbox RIDs and its movement RID are excluded. Target identity/zone is read from server-created collider metadata. Damage/death/respawn functions are not RPCs and explicitly require the host; target membership, alive state and protection are checked again before damage.

Body/head hitboxes are lightweight boxes, not per-bone collision. Player-to-player physical movement collision remains disabled; shooting hitboxes are independent. Self-shooting is excluded. A host-detected fall below the arena adds a death without awarding a self-elimination. Disconnected players cannot be damaged for a new kill and their state/timers are removed.

## Synchronization and duplicate handling

- Reliable control channel 0: combat intent at approximately 10 Hz plus changed edges/reload requests; authority-only critical state, damage feedback, reload events, elimination feed and respawn events.
- Opening shots are reliable so a single tap can be seen/heard by observers. Subsequent sustained-fire cosmetic shots use unreliable channel 2. Cosmetic packet loss never determines health or ammunition.
- Changed player state is batched at the end of a server physics tick. Active countdowns get a 5 Hz correction; clients extrapolate only their displayed timer values. Ammo, health, alive state, eliminations/deaths, loadout and spawn remain authoritative.
- Each public state has a monotonic revision. Match epochs isolate sessions. Each player life has a generation ID included in movement batches, snapshots and combat actions/events. A pre-respawn packet cannot move or shoot from the next life.
- Shot/critical events have unique server event IDs and a bounded deduplication window. Presentation events never apply damage. Repeated intents do not directly execute damage, and an eliminated-state guard prevents duplicate death/stat transitions.
- Existing movement stays at 60 Hz host simulation, 20 Hz input batches/snapshots and roughly 100 ms remote interpolation. Dead controls/history are cleared; respawn resets velocity, camera, prediction corrections and stale input queues.

A reload only transfers `min(missing magazine rounds, reserve)`. Empty magazines/reserves never become negative. Reloading/death reject shooting; reloads are canceled by death. Respawn restores the default LAN loadout. If no candidate is clear, respawn waits briefly rather than forcing overlap.

## Reproduce automated checks

From the checkout with Godot 4.6.3 on PATH:

```bash
./tools/test.sh
python3 tools/test_lan.py --players 2
python3 tools/test_lan.py --players 4
python3 tools/test_lan_edges.py
python3 tools/test_combat.py --players 2
python3 tools/test_combat.py --players 4
```

The Python runners create independent OS processes, ENet peers and isolated user-data directories. Shared files coordinate test commands/results only; gameplay state and effects cross real loopback UDP through the production RPCs. Logs identify the temporary evidence directory. In the managed cloud task, local socket creation needs the supported execution-sandbox escalation flow.

Optional rendered captures require a working X display; for a desktop software renderer:

```bash
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 python3 tools/test_combat.py --players 4 --visual
```

This renders the host with OpenGL Compatibility/Low quality while clients remain headless. It is a desktop testing override, not the exported Mobile renderer. The display must already exist. No live server or display is assumed to survive environment publication.

The combat harness positions stationary authoritative bodies on the host to isolate body/head/cover cases; clients do not supply positions to gameplay RPCs. It also uses one explicit **host-only ammo fixture** (28 magazine / 1 reserve) to exercise the final reserve round without a long multi-magazine drain. Neither fixture is a game control or RPC. See [validation evidence](VALIDATION.md) for actual outcomes and remaining limits.

## Android combat acceptance

1. Build the same Phase 5 APK for both phones using [ANDROID.md](ANDROID.md). A real APK is now available; see the [Phase 5 release report](RELEASE.md). Do not mix phase versions: current builds use protocol 4.
2. Join the same Wi-Fi router, or join an Android hotspot. On A choose Host Game, capacity 2–4, port 7777; on B enter A's actual reachable private IPv4/port. Never assume a fixed hotspot gateway. Follow [LAN setup and isolation notes](LAN.md#test-with-two-android-phones).
3. Ready B and start from A. Check 100 HP and **30 / 120** on each screen, gold spawn rings/notices for about two seconds, and independent first-person controls.
4. Stand still on a clear lane after protection expires. Aim below the head: each isolated body hit must remove 20 HP. Aim at the head: each isolated head hit must remove 40 HP. Check health and hit feedback on both screens. Repeat with A and B as shooter.
5. Put concrete/crates between players. Firing must consume ammunition and produce world impacts without damaging the covered player. Strafe/jump and repeat to assess real-device hit registration under movement.
6. Hold FIRE: approximately ten accepted shots/second, magazine stops at zero, never negative. Hold movement, look and AIM simultaneously with FIRE; contacts must remain independent. Reload via touch: about two seconds, no firing during reload, conserved reserve and matching remote reload animation/audio.
7. Eliminate a player: controls and shooting stop, HP becomes zero, a death/countdown appears, remote model slumps and each feed records one elimination. Shooter eliminations and victim deaths must update correctly on all devices.
8. After about three seconds, verify a clear spawn, restored health/loadout, reset movement/camera and re-enabled controls. Shoot a protected respawn: no damage. Have that player fire: protection must end immediately on the accepted shot.
9. Check near/far shot sound attenuation, muzzle flashes, light impact geometry, hitmarkers, damage direction and feed readability at 16:9/18:9/20:9. Background/foreground, release/cancel contacts and open a personal pause menu during combat.
10. Disconnect a client while alive and again while dead/reloading. No ghost body, stale combat record or delayed respawn should remain. Close/force-stop the host; other phones must return safely to the menu. No host migration is provided.
11. Repeat with three/four phones and with upstream internet/mobile data disabled. Check sustained performance, packet loss/jitter, Wi-Fi client isolation, hotspot routing and OEM behavior. Record the exact phones/Android versions and network used.

Physical Android input, routing, audio, Mobile/Vulkan rendering, thermal behavior and the 30–60 FPS target remain **NOT VERIFIED** until these steps run on hardware.

## Retained combat limitations

- Hits use current host collision state, without historical rewind/lag compensation. Remote render interpolation and network delay can make moving-target aim differ from the host's current position. Aim is carried with fire to avoid stale cross-channel ordering, but latency is not removed and high-loss networks can still cause corrections/disconnection.
- Sustained automatic-fire cosmetic packets may drop. Critical ammo/health/death/feed/respawn state and opening shots are reliable. No packet-loss emulator, WAN benchmark or hostile-network penetration test was run.
- Lightweight box hitboxes, block models, synthesized audio and simple slump/reload effects remain prototype assets. Existing practice-plate flash behavior is primarily host-local; player combat and bullet impacts are synchronized.
- The listen host is trusted, ENet is not encrypted, and there is no host migration or public matchmaking. This is a local-network prototype, not an internet service.
- Phase 5 supplies a debug APK; physical-device LAN acceptance remains unverified. The original UI reference image was absent, so a direct visual-reference match cannot be assessed.

There are no confirmed unresolved combat defects in the final passing checks; this is limited evidence, not a guarantee of bug-free device behavior. Phase 4 match rules, scoreboard and results are now implemented; see [MATCHES.md](MATCHES.md). Physical Android acceptance and latency testing remain necessary before production readiness.
