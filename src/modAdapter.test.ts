import { describe, expect, it } from "vitest";
import { createModAdapter } from "./modAdapter";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("mod_adapter_tests");

describe("createModAdapter", () => {
  it("uses a safe browser preview when no desktop bridge exists", async () => {
    const adapter = createModAdapter();
    const result = await adapter.dispatch({ action: "toggle", detail: "God Mode", enabled: true });

    expect(adapter.transport).toBe("browser");
    expect(result).toEqual({
      accepted: false,
      mode: "offline-preview",
      message: "God Mode requires the installed desktop application and running official game.",
    });
  });

  it("routes commands through the isolated Electron bridge", async () => {
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({
        platform: "win32",
        mode: "live-offline",
        connected: true,
        bridgeVersion: "1.3.2",
        capabilities: ["quick-action:Heal Player"],
      }),
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
      dispatch: async (command) => ({
        accepted: command.action === "quick-action",
        mode: "live-offline",
        message: command.detail ?? "",
      }),
    };

    const adapter = createModAdapter();
    const result = await adapter.dispatch({ action: "quick-action", detail: "Heal Player" });

    expect(adapter.transport).toBe("electron");
    expect(adapter.mode).toBe("live-offline");
    expect(result.accepted).toBe(true);
    delete window.agefieldDesktop;
  });
});
