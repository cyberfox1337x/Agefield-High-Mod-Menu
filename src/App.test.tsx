import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("agefield_app_tests");

const capabilities = [
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
];

describe("Agefield High offline menu", () => {
  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  beforeEach(() => {
    localStorage.clear();
    delete window.agefieldDesktop;
  });

  it("renders only controls backed by verified game capabilities", () => {
    render(<App />);

    expect(screen.getByRole("heading", { name: "MOD MENU" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /God Mode/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Unlimited Money/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /No Clip/ })).toBeInTheDocument();
    expect(screen.getByText("Smooth flight follows facing; Space rises, Z descends.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Heal Player/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Clear Wanted/ })).toBeInTheDocument();
    expect(screen.queryByText("Max Reputation")).not.toBeInTheDocument();
    expect(screen.queryByText("Unlock All Outfits")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Player" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Inventory" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "World" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Settings" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Teleport" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Fun" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "School Events" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Time & World" })).not.toBeInTheDocument();
    expect(screen.queryByText("Agefield High")).not.toBeInTheDocument();
    expect(screen.queryByText("MOD CONTROL DESK")).not.toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "SPAWN ITEMS" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Restore Spawned Items/ })).not.toBeInTheDocument();
    expect(screen.queryByText(/not available in this game build/i)).not.toBeInTheDocument();
  });

  it("fits the fixed design canvas and exposes custom desktop window controls", async () => {
    const user = userEvent.setup();
    const minimizeWindow = vi.fn();
    const closeWindow = vi.fn();
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({ platform: "win32", mode: "live-offline", connected: true, capabilities }),
      dispatch: async () => ({ accepted: true, mode: "live-offline", message: "ok" }),
      minimizeWindow,
      closeWindow,
    };
    render(<App />);

    const designCanvas = document.querySelector("[data-design-canvas]");
    expect(designCanvas).toHaveAttribute("data-scale");
    expect(Number(designCanvas?.getAttribute("data-scale"))).toBeLessThanOrEqual(1);

    await user.click(screen.getByRole("button", { name: "Minimize application" }));
    await user.click(screen.getByRole("button", { name: "Close application" }));
    expect(minimizeWindow).toHaveBeenCalledOnce();
    expect(closeWindow).toHaveBeenCalledOnce();
  });

  it("shows the global window hotkey and creative credits in Settings", async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole("button", { name: "Settings" }));
    expect(screen.getByText("Window hotkey")).toBeInTheDocument();
    expect(screen.getByText("Press F10 to minimize or restore the menu.")).toBeInTheDocument();
    expect(screen.queryByText("Game bridge")).not.toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Credits" })).toBeInTheDocument();
    expect(screen.getByText("Cyberfox1337x")).toBeInTheDocument();
    expect(screen.getByText("Full-Stack Developer")).toBeInTheDocument();
    expect(screen.getByText("tooka223")).toBeInTheDocument();
    expect(screen.getByText("Graphic Designer")).toBeInTheDocument();
    expect(screen.getByText("Helped shape the menu design.")).toBeInTheDocument();
    expect(screen.queryByText("Offline lock")).not.toBeInTheDocument();
    expect(screen.queryByText("Capability filtering")).not.toBeInTheDocument();
  });

  it("toggles a verified player option and persists the selection", async () => {
    const user = userEvent.setup();
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({ platform: "win32", mode: "live-offline", connected: true, capabilities }),
      dispatch: async () => ({ accepted: true, mode: "live-offline", message: "God Mode enabled." }),
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
    };
    render(<App />);

    const godMode = screen.getByRole("button", { name: /God Mode/ });
    expect(godMode).toHaveAttribute("aria-pressed", "false");
    await user.click(godMode);

    expect(godMode).toHaveAttribute("aria-pressed", "true");
    expect(localStorage.getItem("agefield-high-offline-menu-state-v3")).toContain("god-mode");
  });

  it("never overlaps runtime refreshes when one is still pending", async () => {
    vi.useFakeTimers();
    let resolveRuntimeInfo: ((info: { platform: string; mode: "live-offline"; connected: boolean; capabilities: readonly string[] }) => void) | undefined;
    const getRuntimeInfo = vi.fn(() => new Promise<{ platform: string; mode: "live-offline"; connected: boolean; capabilities: readonly string[] }>((resolve) => {
      resolveRuntimeInfo = resolve;
    }));
    window.agefieldDesktop = {
      getRuntimeInfo,
      dispatch: async () => ({ accepted: true, mode: "live-offline", message: "ok" }),
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
    };
    render(<App />);

    expect(getRuntimeInfo).toHaveBeenCalledOnce();
    await act(async () => vi.advanceTimersByTime(20_000));
    expect(getRuntimeInfo).toHaveBeenCalledOnce();

    await act(async () => resolveRuntimeInfo?.({ platform: "win32", mode: "live-offline", connected: true, capabilities }));
    await act(async () => vi.advanceTimersByTime(1_999));
    expect(getRuntimeInfo).toHaveBeenCalledOnce();
    await act(async () => vi.advanceTimersByTime(1));
    expect(getRuntimeInfo).toHaveBeenCalledTimes(2);
  });

  it("removes controls that the connected bridge does not advertise", async () => {
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({
        platform: "win32",
        mode: "live-offline",
        connected: true,
        capabilities: ["toggle:God Mode", "quick-action:Heal Player", "reset-player:*"],
      }),
      dispatch: async () => ({ accepted: true, mode: "live-offline", message: "ok" }),
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
    };
    render(<App />);

    await waitFor(() => expect(screen.queryByRole("button", { name: /Unlimited Money/ })).not.toBeInTheDocument());
    expect(screen.getByRole("button", { name: /God Mode/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Heal Player/ })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Clear Wanted/ })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "World" })).not.toBeInTheDocument();
  });

  it("shows confirmations only in a resetting two-second toast", async () => {
    vi.useFakeTimers();
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({ platform: "win32", mode: "live-offline", connected: true, capabilities }),
      dispatch: async (command) => ({
        accepted: true,
        mode: "live-offline",
        message: `${command.detail ?? command.action} updated in game.`,
      }),
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
    };
    render(<App />);

    const godMode = screen.getByRole("button", { name: /God Mode/ });
    await act(async () => fireEvent.click(godMode));

    const message = "God Mode updated in game.";
    expect(screen.getByText(message)).toHaveClass("toast");
    act(() => vi.advanceTimersByTime(1900));
    expect(screen.getByText(message)).toBeInTheDocument();
    act(() => vi.advanceTimersByTime(101));
    expect(screen.queryByText(message)).not.toBeInTheDocument();
  });

  it("dispatches the verified time-of-day control", async () => {
    const user = userEvent.setup();
    const dispatch = vi.fn(async () => ({ accepted: true as const, mode: "live-offline" as const, message: "Time updated." }));
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({ platform: "win32", mode: "live-offline", connected: true, capabilities }),
      dispatch,
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
    };
    render(<App />);

    await user.click(screen.getByRole("button", { name: "World" }));
    expect(screen.getByRole("heading", { name: "TIME OF DAY" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /First Bell/ })).toBeInTheDocument();
    fireEvent.keyUp(screen.getByRole("slider", { name: "Time of day" }), { key: "ArrowRight" });
    await waitFor(() => expect(dispatch).toHaveBeenCalledWith(expect.objectContaining({ action: "set-time" })));
  });

  it("dispatches a verified teleport destination and exposes return", async () => {
    const user = userEvent.setup();
    const dispatch = vi.fn(async () => ({ accepted: true as const, mode: "live-offline" as const, message: "Teleported." }));
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({ platform: "win32", mode: "live-offline", connected: true, capabilities }),
      dispatch,
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
    };
    render(<App />);

    await user.click(screen.getByRole("button", { name: "World" }));
    expect(screen.getByRole("heading", { name: "TELEPORT" })).toBeInTheDocument();
    expect(screen.getByText("Agefield High")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "RETURN TO PREVIOUS LOCATION" }));
    await waitFor(() => expect(dispatch).toHaveBeenCalledWith({ action: "teleport", detail: "Return", enabled: undefined }));
  });

  it("spawns a verified item through the inventory page", async () => {
    const user = userEvent.setup();
    const dispatch = vi.fn(async () => ({ accepted: true as const, mode: "live-offline" as const, message: "Spawned." }));
    window.agefieldDesktop = {
      getRuntimeInfo: async () => ({ platform: "win32", mode: "live-offline", connected: true, capabilities }),
      dispatch,
      minimizeWindow: () => undefined,
      closeWindow: () => undefined,
    };
    render(<App />);

    await user.click(screen.getByRole("button", { name: "Inventory" }));
    expect(screen.getByRole("heading", { name: "Inventory" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "RESTORE ITEMS SPAWNED THIS SESSION" })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /Burger/ }));
    await waitFor(() => expect(dispatch).toHaveBeenCalledWith({ action: "spawn-item", detail: "Burger", enabled: undefined }));
  });
});
