# Agefield High Mod Menu

<img width="1672" height="941" alt="image" src="https://github.com/user-attachments/assets/fd172ddf-7bcb-4e1c-8c44-fe6cac22c15a" />



A self-contained Electron + React + TypeScript Windows application that recreates the supplied neon school-hallway mod-menu design. The frameless desktop window uses custom Agefield controls and proportionally fits its complete design canvas into every supported window size without document scrollbars. It is intentionally there are no network requests, analytics, accounts, or multiplayer features.

## Current integration status

Version 1.6.0 uses a local, allowlisted file bridge to the installed `AgefieldModBridge` UUE4SS Lua mod in the official Steam build. The Electron application remains the only user-facing menu. Commands are serialized through the current user's temporary directory, bound to the current game session, validated on both sides, and acknowledged only after the game returns verified read-back.

A list of cheats for GTA V is presented below; (1) God Mode, (2) Infinite Stamina, (3) Unlimited Money, (4) No Detection, (5) Invisible Mode, (6) Super Speed, (7) No Clip, (8) Free Roam, (9) Low Gravity), (10) Heal Player, (11) Clear Wanted, (12) Restore Spawned Items, (13-17) Five named teleport locations plus "Return", (18-25) Eight Safely Restorable Item Spawns, (26) Time of Day, and (27) Reset Player. Unlimited money has a HUD safe 9,999 cap with exact-delta restore. All other cheat options have an explicit path to reset or turn them off. In addition, while No Clip is engaged all player movement is controlled by relative directional inputs as follows: W moves forward (or up), A turns left, S moves back (or down), D turns right, Space jumps upward and Z jumps downward. In addition to those options the bridge has exclusive control over all player movement during flight. As such it also consumes any queued input as well as player velocity upon release of flight direction changes or turning off/no clip. When flight ceases the bridge relinquishes its authority over player movement. A fail closed/ no pass gameplay-world gate prevents No Clip from being activated at the start/main menu screen and will clear out old controller/Pawn references each time the player leaves the current game world. Flight was built using a v1.5.5 version of the event driven GTA V flight build which still required some post restart confirmation of physical lag/smoothness in the official GTA V game.

Teleport contains ground validation (age field high) logic for home, police station, general Store, Cloth Shop. Each command first puts the player into fly mode with the World Partition loaded, then it does a down trace for walkable geometry, at a capsule safe height, returns the intended movement/collision state back on the player, and performs 5 grounded dwell checks before saying "success." If a trace fails, lands, or has a dwell, the script will go back to where the last valid spot was, as opposed to placing you in a hole. When using return, it will use the most recent grounded location that was recorded when you teleported. The desktop bridge gives the player a maximum of 10 seconds to complete the ground validation. Post-fix landing path still needs official game confirmation after restart. Inventory supports Burger, Candy, Soda, Blue Power Bar, Red Power Bar, hot dog, newspaper, and Parent Note; remove spawned items only removes the exact counts of items added to menu during current bridge session.

the running bridge has an exact capability manifest that it makes public. electron does the same check on that manifest before sending the command. therefore we do not display or allowlist artwork-only controls for systems that are not in the official build (therefore the shipped version of the app will have no dummy button(s) nor the "session failed" toast).

the user interface can be broken down into four sections which do not overlap. player section owns all 9 character toggle, reset player, heal player, clear wanted. inventory section owns item spawn and restore sessionspawning. world section owns all teleport locations, return, world clock, and school day time shortcuts. settings section owns global window hot key and a creative team credits card. 
we did not remove the teleports, fun, school events, time & world side bar pages... we removed them as they would be redundant views.

## Desktop behavior

- Sidebar item inactive areas will show a transparent area in the background of the mouse-over. When you move over an inactive sidebar item, it will have violet accents for both the icon and the label, while the active Player panel will be solid again.
- Globally toggle the Running Menu from Minimized to Restored/Focused using "F10." Failure to register a global hotkey is fatal, but shutting down removes the global hotkey registration.
- No clip controls use face-relative W, A, S, D keys to move left/right/front/back, space bar to go up, and z key to go down.
- All toggle/command confirmation messages display a single low right corner message that fades away after two seconds. Each additional action resets this timer.
- The titlebar minimize and close buttons do not cross the allow-listed preload/IPC barrier.
- Both the visual OFFLINE MODE badge and the LOCAL OFFLINE SESSION titlebar label are disabled by default. This application remains technically offline-only due to its Electron security policy and local bridge.
- Titlebar MOD CONTROL DESK subtitle was removed. Items spawn on Inventory tab. Teleportation options and Time controls exist only on World tab. Options related to player-state control exist only on Player tab.
- Online/offline status (Offline Lock), capability filtering (Capability Filtering) and visible game bridge cards (visible game bridges) were removed from settings. The credits page now shows Cyberfox1337x as Full Stack developer and tooka223 as Graphic designer. The note on the credits page mentions that tooka223 also influenced how the menu was designed.
- Status readouts never overlap. Renderer refreshes every two seconds while shown. While minimized or hidden, renderer waits ten seconds before refreshing. Once the window is shown again, renderer refreshes instantly. If there has been no change in the state, renderer does not update. Throttling is enabled via Electron for background tasks. At idle, all gamebridge code except the lightweight local command polling stays dormant. For NoClip, only 50ms of input monitoring is armed while movement input exists. Continuous velocity is only updated/write when either direction or travel yaw is changed. Active mod enforcement and teleport landing validation stay demand-armed until they are needed. Only one task is allowed per loop in each game thread task.
- Release output uses a latest-only policy: After successful Windows packaging, the "release/" directory will contain only the installer/portable EXE for the most recent version. All intermediate unpacked files, block maps, build data and older versions of releases are automatically deleted.

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

The v1.6.0 Setup EXE is an installer of the per machine type which requires Administrator approval to install the desktop application, locate the Steam App ID 3562580 based on the manifests in Steam's library, validate the build number 24987926 and the specific supported shipping executable SHA-256 hash. After validation, the installer installs the validated UE4SS v3.0.1 runtime and the Agefield Bridge into that Win64 directory derived by manifest location. This version of the Setup will refuse installation if attempting to use a Legacy Non-Steam Path, Unknown Game Builds, Repack/Emulation Markers, Protection Components, A Running Game, Partial Loader Installs, Conflicting Proxy Loaders, and Unknown Versions of UE4SS.

When performing a clean install of a game, Setup will install all payloads of the reviewed runtime. If the exact supported UE4SS Loader already exists, Setup will preserve other mods and configurations. Only HookProcessInternal=1, HookInitGameState=1, Keybinds : 1, AgefieldModBridge : 1, and AgefieldReflectionDiscovery : 0 will be merged into this existing Loader.

Pre-install files will be backup under %ProgramData%\Cyberfox1337x\AgefieldHighModMenu\Runtime. Update and Uninstall Restore will only restore Settings/Entries owned by Agefield to prevent loss of unrelated changes made after installation.

Do NOT close the game prior to installing, updating, or uninstalling. The Portable EXE will remain a UI-only build when user has the verified runtime installed; no modifications will be performed to the game. npm run package:nexus generates the most current ZIP ready for nexus (documentation included), Third Party Notice File, Checksum Files and uploads nothing.


The current 1.6.0 installer and portable executable are the only files retained in `release/`.

## Public-source notes

This repository contains the desktop application, production UE4SS Lua bridge, installer logic, tests, and case-study source. It intentionally excludes game files, saves, private runtime analysis, generated build output, and packaged executables. Release executables belong in GitHub Releases rather than Git history.

`npm run prepare:runtime` downloads only the pinned official UE4SS v3.0.1 archive and its MIT license, then refuses either file unless its reviewed size and SHA-256 match. See `THIRD_PARTY_NOTICES.md` for attribution.

This is an unofficial offline single-player mod and is not affiliated with or endorsed by Refugium Games.

[![Read the Full Explanation](https://img.shields.io/badge/Read%20the%20Full%20Explanation-9750ff?style=for-the-badge)](https://agefield-high-article.feel-by-sale.workers.dev/)

