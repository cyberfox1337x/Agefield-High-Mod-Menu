import { contextBridge, ipcRenderer } from "electron";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("electron_preload");

export type DesktopCommand = Readonly<{
  action: string;
  detail?: string;
  enabled?: boolean;
}>;

export type DesktopResult = Readonly<{
  accepted: boolean;
  mode: "live-offline" | "offline-preview";
  message: string;
}>;

export type DesktopRuntimeInfo = Readonly<{
  platform: string;
  mode: "live-offline" | "offline-preview";
  connected: boolean;
  bridgeVersion?: string;
  activeMods?: readonly string[];
  capabilities?: readonly string[];
}>;

const desktopBridge = Object.freeze({
  getRuntimeInfo: (): Promise<DesktopRuntimeInfo> =>
    ipcRenderer.invoke("agefield:get-runtime-info"),
  dispatch: (command: DesktopCommand): Promise<DesktopResult> =>
    ipcRenderer.invoke("agefield:dispatch", command),
  minimizeWindow: (): void => ipcRenderer.send("agefield:window-control", "minimize"),
  closeWindow: (): void => ipcRenderer.send("agefield:window-control", "close"),
});

contextBridge.exposeInMainWorld("agefieldDesktop", desktopBridge);
