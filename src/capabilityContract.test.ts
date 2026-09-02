import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("agefield_capability_contract_tests");

const appSource = readFileSync(resolve(process.cwd(), "src/App.tsx"), "utf8");
const electronSource = readFileSync(resolve(process.cwd(), "electron/main.ts"), "utf8");
const bridgeSource = readFileSync(
  resolve(process.cwd(), "integration/uue4ss/Mods/AgefieldModBridge/Scripts/main.lua"),
  "utf8",
);
const productionSources = `${appSource}\n${electronSource}\n${bridgeSource}`;

describe("verified runtime capability contract", () => {
  it("contains no production unavailable placeholder messages", () => {
    expect(productionSources).not.toMatch(/not available in this game build/i);
    expect(productionSources).not.toContain("unavailable_messages");
  });

  it("does not render or allowlist artwork-only controls", () => {
    for (const unsupportedLabel of [
      "Max Reputation",
      "Unlock All Outfits",
      "Remove Detention",
      "Cafeteria",
      "Gym",
      "Principal Office",
      "Courtyard",
      "School Supplies",
      "Unlock Collectibles",
      "Party Mode",
      "Pep Rally",
    ]) {
      expect(`${appSource}\n${electronSource}`).not.toContain(unsupportedLabel);
    }
  });

  it("shares the exact verified controls across the app and runtime bridge", () => {
    for (const capability of [
      "toggle:God Mode",
      "toggle:Infinite Stamina",
      "toggle:Unlimited Money",
      "toggle:No Detection",
      "toggle:Invisible Mode",
      "toggle:Super Speed",
      "toggle:No Clip",
      "toggle:Free Roam",
      "toggle:Low Gravity",
      "quick-action:Heal Player",
      "quick-action:Clear Wanted",
      "quick-action:Restore Spawned Items",
      "teleport:Agefield High",
      "teleport:Home",
      "teleport:Police Station",
      "teleport:General Store",
      "teleport:Cloth Shop",
      "teleport:Return",
      "spawn-item:Burger",
      "spawn-item:Candy",
      "spawn-item:Soda",
      "spawn-item:Blue Power Bar",
      "spawn-item:Red Power Bar",
      "spawn-item:Hot Dog",
      "spawn-item:Newspaper",
      "spawn-item:Parent Note",
      "set-time:*",
      "reset-player:*",
    ]) {
      expect(appSource).toContain(capability);
      expect(bridgeSource).toContain(capability);
    }
  });

  it("allows grounded teleports to finish their delayed runtime validation", () => {
    expect(electronSource).toContain('command.action === "teleport" ? 10_000 : 3_500');
  });

  it("registers one recoverable global window toggle hotkey", () => {
    expect(electronSource).toContain('const WINDOW_TOGGLE_HOTKEY = "F10"');
    expect(electronSource).toContain("globalShortcut.register(WINDOW_TOGGLE_HOTKEY");
    expect(electronSource).toContain("targetWindow.minimize()");
    expect(electronSource).toContain("targetWindow.restore()");
    expect(electronSource).toContain("globalShortcut.unregisterAll()");
  });

  it("throttles renderer work while the window is hidden", () => {
    expect(appSource).toContain("RUNTIME_REFRESH_HIDDEN_MS = 10000");
    expect(appSource).not.toContain("setInterval(refreshRuntimeInfo");
    expect(electronSource).toContain("backgroundThrottling: true");
  });
});
