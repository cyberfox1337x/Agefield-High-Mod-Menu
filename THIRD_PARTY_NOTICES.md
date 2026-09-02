<!-- cyberfox1337x.function("third_party_notices") -->
# Third-party notices

## RE-UE4SS

The one-click installer uses the official RE-UE4SS v3.0.1 release from the
[UE4SS-RE project](https://github.com/UE4SS-RE/RE-UE4SS). RE-UE4SS is licensed
under the MIT License. The verified license is included in generated installer
payloads at `THIRD-PARTY-NOTICES/UE4SS-LICENSE.txt`.

The repository does not redistribute the UE4SS binary archive in Git history.
The packaging script downloads the pinned official release asset and verifies:

- file size: `5,523,402` bytes
- SHA-256: `4B47D4BCEDDD2F561A4E395BFA00924CCFC945AF576A2D0C613E6537846C57EC`

## Fonts and libraries

JavaScript and font dependencies are installed from the versions recorded in
`package-lock.json`. Their individual license texts and notices remain governed
by their respective packages.

## Game content

No Agefield High game binaries, archives, saves, or extracted game assets are
included in this repository. The application requires a separately purchased,
supported official Steam installation.
