# Agefield High — Mod Menu

A self-contained Electron + React + TypeScript Windows application that recreates the supplied neon school-hallway mod-menu design. The frameless desktop window uses custom Agefield controls and proportionally fits its complete design canvas into every supported window size without document scrollbars. It is intentionally offline-only: there are no network requests, analytics, accounts, or multiplayer features.

## Current integration status

Version 1.6.0 uses a local, allowlisted file bridge to the installed `AgefieldModBridge` UUE4SS Lua mod in the official Steam build. The Electron application remains the only user-facing menu. Commands are serialized through the current user's temporary directory, bound to the current game session, validated on both sides, and acknowledged only after the game returns verified read-back.

The 28-token production contract provides nine reversible toggles (God Mode, Infinite Stamina, Unlimited Money, No Detection, Invisible Mode, Super Speed, No Clip, Free Roam, and Low Gravity), Heal Player, Clear Wanted, Restore Spawned Items, five named teleport destinations plus Return, eight safely restorable item spawns, Time of Day, and Reset Player. Unlimited Money uses a HUD-safe 9,999 cap and exact-delta restoration. Speed, collision, visibility, perception, gravity, stamina consumption, and death notification have explicit off/reset paths. While No Clip is active, W/A/S/D are facing-relative controls that rotate the character into the travel direction, Space rises, and Z descends. The bridge exclusively owns movement input during flight, consumes queued input and velocity on release/direction change/off/reset, and releases that ownership when flight ends. A fail-closed gameplay-world gate rejects No Clip on the main menu and clears stale controller/Pawn references across world transitions. The bundled v1.5.5 event-driven flight build still requires post-restart physical smoothness/lag confirmation in the official game.

Teleport includes ground-validation logic for Agefield High, Home, Police Station, General Store, and Cloth Shop. Each command stages the player in flying mode while World Partition loads, traces downward for walkable geometry, uses capsule-safe height, restores the intended movement/collision state, and requires five grounded dwell checks before reporting success. A failed trace, landing, or dwell is designed to restore the last safe position instead of leaving the player below the world. Return uses the grounded location saved immediately before teleporting. The desktop bridge allows up to ten seconds for this validation. The post-fix landing path still needs a physical official-game confirmation after restart. Inventory supports Burger, Candy, Soda, Blue Power Bar, Red Power Bar, Hot Dog, Newspaper, and Parent Note; Restore Spawned Items removes only the exact counts added through the menu during the current bridge session.

The running bridge publishes an exact capability manifest. The application renders only those verified commands, and Electron checks the same manifest before dispatch. Artwork-only controls for systems absent from the official build are no longer displayed or allowlisted, so the shipped interface contains no fake buttons or placeholder failure toasts.

The interface is organized into four non-overlapping sections: Player owns all nine character toggles, Reset Player, Heal Player, and Clear Wanted; Inventory owns item spawning and session-spawn restoration; World owns every teleport destination, Return, the world clock, and school-day time shortcuts; Settings contains the global window hotkey and a dedicated creative-team Credits card. The former Teleport, Fun, School Events, and Time & World sidebar pages were removed instead of being left as duplicate views.

## Desktop behavior

- Inactive sidebar items keep a transparent background on hover; the icon and label receive the violet accent while the active Player panel remains filled.
- `F10` globally toggles the running menu between minimized and restored/focused states. Registration failure is non-fatal, and shutdown unregisters the shortcut.
- No Clip controls are facing-relative W/A/S/D, Space to rise, and Z to descend.
- Toggle and command confirmations use one lower-right toast that dismisses after two seconds. Repeated actions restart that interval.
- The titlebar minimize and close controls cross only the allowlisted preload/IPC boundary.
- The visual OFFLINE MODE badge and LOCAL OFFLINE SESSION titlebar label are intentionally absent; the application remains technically offline-only through its Electron security policy and local bridge.
- The `MOD CONTROL DESK` titlebar subtitle is removed. Item spawning and session-spawn restoration appear only on Inventory; teleports and time controls appear only on World; player-state controls appear only on Player.
- Settings no longer displays the redundant Offline lock, Capability filtering, or visible Game bridge cards. Its Credits card names Cyberfox1337x as Full-Stack Developer and tooka223 as Graphic Designer, with a note that tooka223 helped shape the menu design.
- Runtime-status reads never overlap: the renderer refreshes every two seconds while visible, backs off to ten seconds while minimized/hidden, refreshes immediately when restored, and skips identical state updates. Electron explicitly enables background throttling. The game bridge keeps only its lightweight local command poll alive at idle; No Clip key edges arm a 50 ms input monitor only while movement input is present, and continuous velocity is written/read back only when direction or travel yaw changes. Active-mod enforcement and teleport landing validation remain demand-armed, with one game-thread task allowed per loop.
- Release output follows a latest-only policy: after successful Windows packaging, `release/` retains only the current version's installer and portable EXEs. Intermediate unpacked files, blockmaps, build metadata, and older release copies are removed automatically.

## Run

```powershell
npm install
npm run dev
```

`npm run dev` launches the desktop application. Production checks and packaging:

```powershell
npm run lint
npm run test
npm run build
npm run package:win
```

## One-click Windows installer

The v1.6.0 Setup EXE is a per-machine installer that requests administrator approval, installs the desktop application, locates Steam App ID 3562580 from Steam's own library manifests, validates build 24987926 and the exact supported shipping-executable SHA-256, then installs the verified UE4SS v3.0.1 runtime and production Agefield bridge into that manifest-derived `Win64` directory. It refuses the legacy non-Steam path, unknown game builds, repack/emulation markers, protection components, a running game, partial loader installs, conflicting proxy loaders, and unknown UE4SS versions.

On a clean game install, Setup installs the complete reviewed runtime payload. When the exact supported UE4SS loader already exists, Setup preserves unrelated mods and configuration: it merges only `HookProcessInternal = 1`, `HookInitGameState = 1`, `Keybinds : 1`, `AgefieldModBridge : 1`, and `AgefieldReflectionDiscovery : 0`. Pre-install files are backed up under `%ProgramData%\Cyberfox1337x\AgefieldHighModMenu\Runtime`; update and uninstall restore only Agefield-owned settings/entries so unrelated later edits survive. Any failed first transaction restores game files and removes its incomplete installer state.

Close the game before installing, updating, or uninstalling. The Portable EXE remains a UI-only build for users who already have the verified runtime installed; it does not modify the game. `npm run package:nexus` creates the latest Nexus-ready ZIP, documentation, third-party notice, and checksums without uploading anything.


The current 1.6.0 installer and portable executable are the only files retained in `release/`.

## Public-source notes

This repository contains the desktop application, production UE4SS Lua bridge, installer logic, tests, and case-study source. It intentionally excludes game files, saves, private runtime analysis, generated build output, and packaged executables. Release executables belong in GitHub Releases rather than Git history.

`npm run prepare:runtime` downloads only the pinned official UE4SS v3.0.1 archive and its MIT license, then refuses either file unless its reviewed size and SHA-256 match. See `THIRD_PARTY_NOTICES.md` for attribution.

This is an unofficial offline single-player mod and is not affiliated with or endorsed by Refugium Games. Development and visual iteration were AI-assisted under human direction, with final design, integration choices, validation, and publication owned by Cyberfox1337x.

## Credits

- **Cyberfox1337x** — Full-Stack Developer
- **tooka223** — Graphic Designer; helped shape the visual direction of the menu
- **UE4SS-RE contributors** — RE-UE4SS runtime, used under the MIT License
