# Agefield High Mod Menu — One-Click Offline Installer

This package installs the Agefield High Mod Menu desktop app and its verified offline runtime in one pass. It is built only for the official Steam release of **Agefield High — Rock the School**, App ID **3562580**, build **24987926**.

## Install

1. Close Agefield High.
2. Run `Agefield High Mod Menu-Setup-1.6.0-x64.exe`.
3. Approve the Windows administrator prompt.
4. Launch the official game through Steam, enter your save, then open the menu from the desktop or Start menu. Press **F10** to show or minimize it.

Setup finds the official Steam library automatically and validates the exact supported build before changing anything. It will stop safely if the game is running, the build is unsupported, the install is not eligible, or an unknown/partial UE4SS loader is present.

## Features

- Nine reversible player toggles: God Mode, Infinite Stamina, Unlimited Money, No Detection, Invisible Mode, Super Speed, No Clip, Free Roam, and Low Gravity.
- Heal Player, Clear Wanted, Reset Player, and session-spawn restoration.
- Ground-validation logic for teleports to Agefield High, Home, Police Station, General Store, and Cloth Shop, plus Return.
- Eight safe item spawns: Burger, Candy, Soda, Blue/Red Power Bars, Hot Dog, Newspaper, and Parent Note.
- School-day time controls.
- Facing-relative No Clip controls with W/A/S/D, Space up, and Z down.
- A secure, offline-only Electron app with no analytics, accounts, or multiplayer hooks.

## Update and uninstall

Close the game before updating or uninstalling. Setup creates exact backups under `%ProgramData%\Cyberfox1337x\AgefieldHighModMenu\Runtime`. If the supported UE4SS v3.0.1 loader already exists, the installer preserves unrelated mods and settings and owns only the two required hook keys plus the three Agefield mod-registry entries. Uninstall restores those owned values without deleting unrelated later edits.

## Safety and compatibility

- Official Steam App ID 3562580, build 24987926 only.
- Offline single-player only.
- No executable patching, memory scanner, DRM bypass, anti-cheat bypass, or online cheat behavior.
- The installer includes the official UE4SS v3.0.1 release under its MIT license. Unknown loader versions are refused instead of overwritten.
- The installer is not code-signed, so Windows SmartScreen may show an unknown-publisher warning. Verify `CHECKSUMS.txt` before running it.

## Credits and disclosure

- **Cyberfox1337x** — Full-Stack Developer
- **tooka223** — Graphic Designer; helped shape the menu design
- **UE4SS-RE contributors** — UE4SS runtime, MIT license

The included v1.5.5 No Clip pacing and post-fix teleport landing path still require physical confirmation in the official game after restart; this listing does not claim that pending runtime gate has passed.
