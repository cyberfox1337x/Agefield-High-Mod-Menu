import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("agefield_runtime_installer_contract_tests");

const readProjectFile = (relativePath: string) =>
  readFileSync(resolve(process.cwd(), relativePath), "utf8").replace(/^\uFEFF/, "");

const helperSource = readProjectFile("installer/AgefieldRuntimeInstaller.ps1");
const prepareSource = readProjectFile("scripts/Prepare-AgefieldRuntimePayload.ps1");
const nsisSource = readProjectFile("installer/installer.nsh");
const bridgeSource = readProjectFile(
  "integration/uue4ss/Mods/AgefieldModBridge/Scripts/main.lua",
);
const packageManifest = JSON.parse(readProjectFile("package.json"));
const payloadManifest = JSON.parse(readProjectFile("installer/runtime/payload-manifest.json"));

describe("one-click runtime installer contract", () => {
  it("gates installation to the exact supported official Steam build", () => {
    expect(helperSource).toContain("$script:ExpectedAppId = '3562580'");
    expect(helperSource).toContain("$script:ExpectedBuildId = '24987926'");
    expect(helperSource).toContain(
      "$script:ExpectedExecutableSha256 = '4C8EAE91E49295780D9C0D1F850773AFBC535E1120D3EDAB5992D575B3127951'",
    );
    expect(helperSource).toContain("Get-OfficialGameInstall -RequireExactBuild");
    expect(helperSource).toContain("A repack or Steam-emulation marker was found");
    expect(helperSource).toContain("Close Agefield High before installing");
  });

  it("packages the verified UE4SS payload and production overlays", () => {
    expect(prepareSource).toContain("cyberfox1337x -ModuleName 'prepare_agefield_runtime_payload'");
    expect(packageManifest.scripts["prepare:runtime"]).toContain(
      "Prepare-AgefieldRuntimePayload.ps1",
    );
    expect(packageManifest.build.extraResources).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ to: "agefield-runtime/AgefieldRuntimeInstaller.ps1" }),
        expect.objectContaining({ from: "installer/runtime", to: "agefield-runtime" }),
      ]),
    );
    expect(payloadManifest.payloadFiles).toHaveLength(25);
    expect(payloadManifest.ue4ssVersion).toBe("3.0.1");
    expect(payloadManifest.overlays).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ targetPath: "UE4SS-settings.ini" }),
        expect.objectContaining({ targetPath: "Mods/mods.txt" }),
        expect.objectContaining({ targetPath: "Mods/AgefieldModBridge/Scripts/main.lua" }),
      ]),
    );
  });

  it("uses a per-machine one-click NSIS transaction for install and uninstall", () => {
    expect(packageManifest.version).toBe("1.6.0");
    expect(packageManifest.build.nsis).toEqual(
      expect.objectContaining({
        oneClick: true,
        perMachine: true,
        include: "installer/installer.nsh",
      }),
    );
    expect(nsisSource).toContain('!insertmacro cyberfox1337x_function "agefield_runtime_nsis"');
    expect(nsisSource).toContain("!macro customInstall");
    expect(nsisSource).toContain("-Action Install");
    expect(nsisSource).toContain("!macro customUnInstall");
    expect(nsisSource).toContain("-Action Uninstall");
    expect(nsisSource).toMatch(/\$\{If\} \$0 != 0[\s\S]*?Abort/);
  });

  it("preserves unrelated configuration through semantic update and rollback", () => {
    expect(helperSource).toContain("ownership = 'semantic-ini'");
    expect(helperSource).toContain("ownership = 'semantic-mod-registry'");
    expect(helperSource).toContain("Get-SemanticBaseline");
    expect(helperSource).toContain("Restore-BaselineRecord");
    expect(helperSource).toContain("Remove-IniValue");
    expect(helperSource).toContain("Remove-ModRegistryValue");
    expect(helperSource).toContain("Remove-FailedInitialState");
    expect(helperSource).toContain("Add-ExistingManagedPlanItems");
  });

  it("keeps executable function-style signatures at the Lua domain boundaries", () => {
    for (const boundary of [
      "agefield_mod_bridge",
      "bootstrap",
      "player_controls",
      "world_controls",
      "inventory_quick_actions",
      "keybind_transport",
    ]) {
      expect(bridgeSource).toContain(`cyberfox1337x.function_signature("${boundary}")`);
    }
  });
});
