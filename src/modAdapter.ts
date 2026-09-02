const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("mod_adapter");

export type ModAction =
  | "toggle"
  | "quick-action"
  | "teleport"
  | "spawn-item"
  | "set-time"
  | "reset-player"
  | "reset-interface";

export type ModCommand = Readonly<{
  action: ModAction;
  detail?: string;
  enabled?: boolean;
}>;

export type ModResult = Readonly<{
  accepted: boolean;
  mode: "live-offline" | "offline-preview";
  message: string;
}>;

export type RuntimeInfo = Readonly<{
  platform: string;
  mode: "live-offline" | "offline-preview";
  connected: boolean;
  bridgeVersion?: string;
  activeMods?: readonly string[];
  capabilities?: readonly string[];
}>;

type DesktopBridge = Readonly<{
  getRuntimeInfo: () => Promise<RuntimeInfo>;
  dispatch: (command: ModCommand) => Promise<ModResult>;
  minimizeWindow: () => void;
  closeWindow: () => void;
}>;

declare global {
  interface Window {
    agefieldDesktop?: DesktopBridge;
  }
}

export interface ModAdapter {
  readonly mode: "live-offline" | "offline-preview";
  readonly transport: "electron" | "browser";
  getRuntimeInfo(): Promise<RuntimeInfo>;
  dispatch(command: ModCommand): Promise<ModResult>;
}

function createBrowserPreviewAdapter(): ModAdapter {
  return {
    mode: "offline-preview",
    transport: "browser",
    async getRuntimeInfo() {
      return { platform: "browser", mode: "offline-preview", connected: false };
    },
    async dispatch(command) {
      return {
        accepted: false,
        mode: "offline-preview",
        message: `${command.detail ?? command.action} requires the installed desktop application and running official game.`,
      };
    },
  };
}

export function createModAdapter(): ModAdapter {
  const desktopBridge = window.agefieldDesktop;
  if (!desktopBridge) return createBrowserPreviewAdapter();

  return {
    mode: "live-offline",
    transport: "electron",
    getRuntimeInfo() {
      return desktopBridge.getRuntimeInfo();
    },
    dispatch(command) {
      return desktopBridge.dispatch(command);
    },
  };
}
