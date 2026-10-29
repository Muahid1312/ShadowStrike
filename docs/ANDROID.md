# Android debug build and two-phone testing

The Phase 5 project is version **0.5.0/code 5**, package **com.shadowstrike.training**, app name **ShadowStrike**, ARM64 only, landscape/immersive and Mobile/Vulkan. All players must use protocol 4. Networking permissions are INTERNET and ACCESS_NETWORK_STATE for offline ENet UDP; the game has no internet service dependency. A Vulkan-capable device is required; API 24 alone does not guarantee a compatible GPU.

## Build on Ubuntu

Install the standard **Godot 4.6.3 stable** editor from the [official archive](https://godotengine.org/download/archive/). Use its exact standard (non-.NET) export templates and verify the published SHA-512 before installation. Keep TLS/artifact checks enabled. Put Godot on PATH or set GODOT to the executable. This project uses the official **Gradle Android template**: the stock APK export path in 4.6.3 emits Vulkan manifest fields that cause an AAPT diagnostic.

Install a complete JDK, including the compiler:

```bash
sudo apt-get update
sudo apt-get install openjdk-17-jdk unzip python3
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$HOME/Android/Sdk"
"$JAVA_HOME/bin/javac" -version
```

A full JDK 21 also works and is used in this cloud build. A JRE with only java/keytool cannot compile the Gradle launcher. Adapt paths for your Ubuntu architecture.

Get the Linux command-line tools from [Google's Android SDK downloads](https://developer.android.com/studio#command-line-tools-only), verify the published checksum and place the inner bin/lib files under `$ANDROID_HOME/cmdline-tools/latest/`. Use sdkmanager (or its documented Android CLI replacement) to install the matching packages and review/accept the SDK licenses:

```bash
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
  "platform-tools" "build-tools;36.0.0" "build-tools;36.1.0" \
  "platforms;android-36" "ndk;29.0.14206865"
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --licenses
```

Godot 4.6.3's official Gradle template declares compile/target API 36, build-tools 36.1.0 and NDK 29.0.14206865. Build-tools 36.0.0 is also used by the export validation helper. Exact template declarations take precedence over older Godot 4.6 documentation. Gradle can automatically fetch missing licensed SDK components; preinstalling them makes the dependency requirements explicit.

Launch `./tools/godot.sh --editor`, then **Editor → Manage Export Templates** and install exact **4.6.3 stable** templates. The wrapper's normal location is:

```text
../.shadowstrike-runtime/data/godot/export_templates/4.6.3.stable/
    android_debug.apk
    android_release.apk
    android_source.zip
    version.txt
```

Close the editor, then configure paths and build:

```bash
python3 tools/configure_android.py --sdk "$ANDROID_HOME" --java "$JAVA_HOME"
./tools/test.sh
./tools/build_android.sh
```

The helper creates the official generated `android/build` template when absent, uses sibling writable Gradle state (override GRADLE_USER_HOME if needed), exports into a temporary directory, validates the APK ZIP/ARM64/assets, then replaces the last successful `builds/ShadowStrike-debug.apk` and writes its SHA-256. A failed export does not promote a partial APK. Generated Android/Gradle caches are excluded from source control and the source ZIP; the build helper recreates them from the matching templates.

Build-time downloads need Google SDK/Maven, Maven Central and Gradle distribution access. Behind a proxy, configure Gradle's HTTP/HTTPS proxy properties and trusted CA through your build environment, preserving TLS verification. Do not put proxy credentials or signing keys in the repository. No proxy settings are needed by the LAN game.

## Verify and install

```bash
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose builds/ShadowStrike-debug.apk
"$ANDROID_HOME/build-tools/36.0.0/zipalign" -c -P 16 -v 4 builds/ShadowStrike-debug.apk
"$ANDROID_HOME/platform-tools/adb" devices -l
"$ANDROID_HOME/platform-tools/adb" install -r builds/ShadowStrike-debug.apk
"$ANDROID_HOME/platform-tools/adb" shell am start -n \
  com.shadowstrike.training/com.godot.game.GodotAppLauncher
```

The exported launcher is the `GodotAppLauncher` alias, not the internal non-exported GodotApp activity. Enable USB debugging and approve the computer on each phone. Alternatively transfer the APK and open it, allowing installation from that source when Android prompts. Debug signing is for testing, not production distribution. If the installed package has a different signing certificate, uninstall it first (this deletes that app's saved preferences). Keep the local debug keystore outside source archives; rebuilding on another machine may produce another debug certificate.

No connected physical Android devices are available in this environment. Successful packaging/signature/manifest checks do not prove installation, rendering or phone networking. Physical tests below are **NOT VERIFIED**.

## Two-phone hotspot procedure — NOT VERIFIED

1. **Phone A:** enable its hotspot. Launch ShadowStrike, select HOST GAME, enter a name, choose 2 players, leave UDP **7777**, choose five minutes/kill limit off, and host. The lobby displays candidate local private IPv4 addresses. Use the actual address belonging to the hotspot interface; never assume 192.168.43.1.
2. **Phone B:** join A's hotspot and keep that Wi-Fi active even if Android labels it “no internet.” Open ShadowStrike → JOIN GAME, enter a different name, A's actual reachable address and UDP7777. Do not use 127.0.0.1. Confirm both names, host marker, player count and ready states match.
3. Ready B. Verify A cannot start while B is unready, then start. Both arenas must load before 3, 2, 1, GO; no movement/fire during countdown. Move independently; use joystick/swipe/fire simultaneously, aim/sprint/jump/reload and check no stuck actions after release/cancel.
4. Shoot body/head (20/40 damage), check cover, 100 HP, 30/120 ammo, two-second reload, elimination/death/feed, three-second respawn and two-second protection ending on accepted fire. Open SCORES and compare every row and 100 points per elimination.
5. Pause/settings on A while B moves and shoots. B and the shared timer continue. Repeat on B; background/foreground each app and check safe recovery. Android may suspend the host process, ending clients' session after timeout; an in-game pause cannot prevent OS suspension.
6. Let the default five-minute match expire. Compare frozen winner/rankings/local stats on both phones; no fire/movement afterwards. A returns both to lobby, names/connections persist, B readies again, and a fresh match has full health/ammo and zero scores. Repeat with kill limit1 and a short timer.
7. Leave B during play/death/results; A must see cleanup without ghost respawn or corrupted results. Leave/force-stop A; B must receive a notice and return to a usable menu. Recreate/rejoin a session. Add phones C/D to exercise all four slots and refused full/active joins.
8. Repeat on a shared non-guest Wi-Fi router, with upstream internet/mobile data off. Test 16:9/18:9/20:9 screens, Android Back, keyboards/cutouts, cancellation and LOW/MEDIUM/HIGH. Measure sustained FPS, thermals, battery and real audio before accepting device performance.

## Connection troubleshooting

- Check the actual interface IP, exact port and compatible build on every phone. Host listens on IPv4 0.0.0.0; displayed candidates can include unrelated tethering/VPN interfaces.
- Keep both phones on the same local network. Disable conflicting VPN/cellular routing for diagnosis; Android may prefer another network when the hotspot lacks upstream internet.
- Guest/client isolation and some hotspot/OEM configurations block station-to-host UDP. The game cannot override them. Try a non-guest router or a third phone's hotspot with both players joined as stations, and document the phone/OS combination. Universal hotspot compatibility is not claimed.
- Permit local host UDP7777 and return traffic, especially for Ubuntu/phone mixed tests. No TCP listener, discovery service or router port-forward is used.
- Wrong/unreachable addresses time out after 10 seconds. A new session can retry after failure. Changing networks requires leaving and hosting/joining again.
- After a phone-specific failure, record device/Android version, network type, exact step, on-screen notice and `adb logcat` output. Never treat successful loopback Linux tests as phone acceptance.

See [release report/checklist](RELEASE.md), [match acceptance](MATCHES.md), [combat details](COMBAT.md) and [LAN architecture](LAN.md).
