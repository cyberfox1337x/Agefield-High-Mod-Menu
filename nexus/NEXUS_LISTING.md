# Title

Agefield High Mod Menu - One-Click Offline Installer

# Summary

Install the full neon desktop mod menu and its verified UE4SS runtime in one click for the official Steam build. Offline single-player only, with safe build gating, backups, readback, and rollback.

# Suggested description (BBCode)

[center][size=6][color=#c657ff]AGEFIELD HIGH MOD MENU[/color][/size]
[size=4]One-click offline installer for the official Steam build[/size][/center]

[heading]What this is[/heading]
I built this as a real desktop control menu for Agefield High — Rock the School. The Setup EXE installs both the app and the verified runtime, finds the game through Steam, validates the supported build, and refuses to touch anything it cannot prove is compatible.

[heading]Included controls[/heading]
[list]
[*]God Mode, Infinite Stamina, Unlimited Money, No Detection, Invisible Mode, Super Speed, No Clip, Free Roam, and Low Gravity
[*]Heal Player, Clear Wanted, Reset Player, and Restore Spawned Items
[*]Ground-validation logic for teleports to Agefield High, Home, Police Station, General Store, and Cloth Shop, plus Return
[*]Burger, Candy, Soda, Blue/Red Power Bars, Hot Dog, Newspaper, and Parent Note spawning
[*]School-day time controls
[*]Facing-relative W/A/S/D No Clip controls, with Space up and Z down
[*]Global F10 show/minimize shortcut
[/list]

[heading]Install[/heading]
[list=1]
[*]Close Agefield High.
[*]Run the Setup EXE and approve the administrator prompt.
[*]Launch the official game through Steam and load your save.
[*]Open the menu from the desktop or Start menu. Press F10 to show or minimize it.
[/list]

The installer supports Steam App ID 3562580, build 24987926 only. It verifies the shipping executable, backs up every file it owns, preserves unrelated UE4SS mods/settings, and rolls back a failed transaction. Unknown or partial UE4SS installations are refused instead of overwritten.

[heading]Uninstall[/heading]
Close the game, then uninstall Agefield High Mod Menu from Windows Settings. The uninstaller restores the exact Agefield-owned settings and files from its ProgramData backup while preserving unrelated post-install edits.

[heading]Important[/heading]
[list]
[*]Offline single-player only.
[*]No game executable patching, DRM bypass, anti-cheat bypass, memory scanner, or multiplayer behavior.
[*]The installer is currently unsigned. Windows SmartScreen may display an unknown-publisher warning; compare the SHA-256 values in CHECKSUMS.txt.
[*]UE4SS v3.0.1 is included under the MIT license with attribution.
[/list]

[heading]Credits[/heading]
[b]Cyberfox1337x[/b] — Full-Stack Developer
[b]tooka223[/b] — Graphic Designer; helped shape the menu design
[b]UE4SS-RE contributors[/b] — UE4SS runtime

[heading]AI disclosure[/heading]
The application code, installer engineering, and listing copy were created with AI-assisted development and reviewed and tested by the author. Apply the appropriate Nexus AI tag/disclosure when publishing.

[heading]Current runtime confirmation gate[/heading]
The included v1.5.5 No Clip pacing and post-fix teleport landing path still require physical confirmation in the official game after restart. I am not marking that pending runtime gate as passed.
