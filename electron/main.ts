import { app, BrowserWindow, globalShortcut, ipcMain, Menu, type Session } from "electron";
import { mkdirSync, writeFileSync } from "node:fs";
import { readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { DesktopCommand, DesktopResult } from "./preload.cjs";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("electron_main");

const WINDOW_TOGGLE_HOTKEY = "F10";
const currentDirectory = dirname(fileURLToPath(import.meta.url));
const developmentUrl = process.env.AGEFIELD_DEV_URL;
const capturePath = process.env.AGEFIELD_CAPTURE_PATH;
const captureNav = process.env.AGEFIELD_CAPTURE_NAV;
const metricsPath = process.env.AGEFIELD_METRICS_PATH;
const uiQaPath = process.env.AGEFIELD_UI_QA_PATH;
const toastDismissQaPath = process.env.AGEFIELD_TOAST_DISMISS_QA_PATH;
const toastDismissedCapturePath = process.env.AGEFIELD_TOAST_DISMISSED_CAPTURE_PATH;
const controlQaPath = process.env.AGEFIELD_CONTROL_QA_PATH;
const controlQaAction = process.env.AGEFIELD_CONTROL_QA_ACTION;
const hasAutomatedQa = Boolean(
  capturePath || captureNav || metricsPath || uiQaPath || toastDismissQaPath || toastDismissedCapturePath || controlQaPath,
);
let controlQaClickReceived = false;
if (hasAutomatedQa) {
  const qaUserDataPath = join(app.getPath("temp"), `agefield-high-qa-${process.pid}`);
  mkdirSync(qaUserDataPath, { recursive: true });
  app.setPath("userData", qaUserDataPath);
}
const allowedActions = new Set([
  "toggle",
  "quick-action",
  "teleport",
  "spawn-item",
  "set-time",
  "reset-player",
  "reset-interface",
]);
const allowedToggleDetails = new Set([
  "God Mode",
  "Infinite Stamina",
  "Unlimited Money",
  "Invisible Mode",
  "No Detection",
  "Super Speed",
  "No Clip",
  "Free Roam",
  "Low Gravity",
]);
const allowedQuickActionDetails = new Set([
  "Heal Player",
  "Clear Wanted",
  "Restore Spawned Items",
]);
const allowedTeleportDetails = new Set([
  "Agefield High",
  "Home",
  "Police Station",
  "General Store",
  "Cloth Shop",
  "Return",
]);
const allowedSpawnItemDetails = new Set([
  "Burger",
  "Candy",
  "Soda",
  "Blue Power Bar",
  "Red Power Bar",
  "Hot Dog",
  "Newspaper",
  "Parent Note",
]);
const bridgeRoot = join(app.getPath("temp"), "AgefieldHighModMenuBridge");
mkdirSync(bridgeRoot, { recursive: true });
const commandPath = join(bridgeRoot, "command.txt");
const responsePath = join(bridgeRoot, "response.txt");
const readyPath = join(bridgeRoot, "ready.txt");
let commandSequence = 0;
const runtimeFeatureIds: Readonly<Record<string, string>> = Object.freeze({
  god_mode: "god-mode",
  infinite_stamina: "infinite-stamina",
  unlimited_money: "unlimited-money",
  invisible_mode: "invisible-mode",
  no_detection: "no-detection",
  super_speed: "super-speed",
  no_clip: "no-clip",
  free_roam: "free-roam",
  low_gravity: "low-gravity",
});
let dispatchQueue: Promise<DesktopResult> = Promise.resolve({
  accepted: true,
  mode: "live-offline",
  message: "Bridge queue ready.",
});

function isSafeDevelopmentUrl(candidate: string): boolean {
  try {
    const parsedUrl = new URL(candidate);
    return parsedUrl.protocol === "http:" && parsedUrl.hostname === "127.0.0.1" && parsedUrl.port === "5173";
  } catch {
    return false;
  }
}

function validateCommand(candidate: unknown): candidate is DesktopCommand {
  if (typeof candidate !== "object" || candidate === null) return false;
  const command = candidate as Record<string, unknown>;
  if (typeof command.action !== "string" || !allowedActions.has(command.action)) return false;
  if (
    command.detail !== undefined &&
    (typeof command.detail !== "string" || command.detail.length > 120 || /[\r\n=]/.test(command.detail))
  ) return false;
  if (command.enabled !== undefined && typeof command.enabled !== "boolean") return false;
  if (command.action === "toggle") return allowedToggleDetails.has(String(command.detail)) && typeof command.enabled === "boolean";
  if (command.action === "quick-action") return allowedQuickActionDetails.has(String(command.detail)) && command.enabled === undefined;
  if (command.action === "teleport") return allowedTeleportDetails.has(String(command.detail)) && command.enabled === undefined;
  if (command.action === "spawn-item") return allowedSpawnItemDetails.has(String(command.detail)) && command.enabled === undefined;
  if (command.action === "set-time") return /^\d{2}:\d{2} [AP]M$/.test(String(command.detail)) && command.enabled === undefined;
  if (command.action === "reset-player") return command.detail === "Player state" && command.enabled === undefined;
  return command.action === "reset-interface" && command.detail === "Interface defaults" && command.enabled === undefined;
}

function commandCapability(command: DesktopCommand): string {
  if (command.action === "set-time" || command.action === "reset-player") return `${command.action}:*`;
  return `${command.action}:${command.detail ?? ""}`;
}

function parseFields(contents: string): Record<string, string> {
  const fields: Record<string, string> = {};
  for (const line of contents.split(/\r?\n/)) {
    const separator = line.indexOf("=");
    if (separator > 0) fields[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return fields;
}

async function readFields(targetPath: string): Promise<Record<string, string> | null> {
  try {
    return parseFields(await readFile(targetPath, "utf8"));
  } catch {
    return null;
  }
}

async function writeAtomic(targetPath: string, contents: string): Promise<void> {
  mkdirSync(bridgeRoot, { recursive: true });
  const temporaryPath = `${targetPath}.${process.pid}.tmp`;
  await writeFile(temporaryPath, contents, "utf8");
  await rm(targetPath, { force: true });
  await rename(temporaryPath, targetPath);
}

function isFreshReady(fields: Record<string, string> | null): fields is Record<string, string> {
  if (!fields || fields.protocol !== "1" || !fields.boot_id) return false;
  const heartbeat = Number(fields.heartbeat);
  return Number.isFinite(heartbeat) && Math.abs(Date.now() / 1000 - heartbeat) <= 5;
}

async function getRuntimeInfo(): Promise<{
  platform: string;
  mode: "live-offline";
  connected: boolean;
  bridgeVersion?: string;
  activeMods?: readonly string[];
  capabilities?: readonly string[];
}> {
  const ready = await readFields(readyPath);
  const connected = isFreshReady(ready);
  const activeMods = connected
    ? (ready.active ?? "").split(",").map((feature) => runtimeFeatureIds[feature]).filter(Boolean)
    : undefined;
  const capabilities = connected
    ? (ready.capabilities ?? "").split(",").map((capability) => capability.trim()).filter(Boolean)
    : undefined;
  return {
    platform: process.platform,
    mode: "live-offline",
    connected,
    ...(connected && ready.version ? { bridgeVersion: ready.version } : {}),
    ...(activeMods ? { activeMods } : {}),
    ...(capabilities ? { capabilities } : {}),
  };
}

async function waitForBridgeResponse(id: string, bootId: string, timeoutMs: number): Promise<DesktopResult> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const response = await readFields(responsePath);
    if (response?.id === id && response.boot_id === bootId) {
      return {
        accepted: response.accepted === "1",
        mode: "live-offline",
        message: response.message || "The game bridge returned no message.",
      };
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return {
    accepted: false,
    mode: "live-offline",
    message: "The game did not answer. Make sure the official game is running, then retry.",
  };
}

async function dispatchToGame(command: DesktopCommand): Promise<DesktopResult> {
  if (command.action === "reset-interface") {
    return { accepted: true, mode: "live-offline", message: "Interface defaults restored." };
  }
  const ready = await readFields(readyPath);
  if (!isFreshReady(ready)) {
    return {
      accepted: false,
      mode: "live-offline",
      message: "Start or resume the official game before using the mod menu.",
    };
  }

  const capabilities = new Set((ready.capabilities ?? "").split(",").map((capability) => capability.trim()).filter(Boolean));
  if (!capabilities.has(commandCapability(command))) {
    return {
      accepted: false,
      mode: "live-offline",
      message: "The running bridge does not advertise this control. Restart the official game after updating the mod bridge.",
    };
  }

  commandSequence += 1;
  const id = `${Date.now().toString(36)}-${commandSequence.toString(36)}`;
  await writeAtomic(commandPath, [
    "protocol=1",
    `boot_id=${ready.boot_id}`,
    `id=${id}`,
    `action=${command.action}`,
    `detail=${command.detail ?? ""}`,
    `enabled=${command.enabled === undefined ? "" : command.enabled ? "1" : "0"}`,
    "",
  ].join("\n"));
  return waitForBridgeResponse(id, ready.boot_id, command.action === "teleport" ? 10_000 : 3_500);
}

function enqueueDispatch(command: DesktopCommand): Promise<DesktopResult> {
  const run = dispatchQueue.then(() => dispatchToGame(command));
  const safeRun = run.catch(() => ({
    accepted: false,
    mode: "live-offline" as const,
    message: "The local game bridge failed safely. Retry after the game finishes loading.",
  }));
  dispatchQueue = safeRun;
  return safeRun;
}

function readCaptureViewport(): { width: number; height: number } | null {
  const captureViewport = process.env.AGEFIELD_CAPTURE_VIEWPORT;
  const match = captureViewport?.match(/^(\d{3,4})x(\d{3,4})$/);
  if (!match) return null;
  const width = Number(match[1]);
  const height = Number(match[2]);
  if (width < 360 || width > 3840 || height < 600 || height > 2160) return null;
  return { width, height };
}

function enforceOfflineSessionPolicy(applicationSession: Session): void {
  applicationSession.setPermissionCheckHandler(() => false);
  applicationSession.setPermissionRequestHandler((_webContents, _permission, callback) => callback(false));
  applicationSession.on("will-download", (event) => event.preventDefault());
  applicationSession.webRequest.onBeforeRequest((details, callback) => {
    const requestedUrl = new URL(details.url);
    const isLocalDevelopmentRequest = Boolean(
      developmentUrl &&
        requestedUrl.hostname === "127.0.0.1" &&
        requestedUrl.port === "5173" &&
        ["http:", "ws:"].includes(requestedUrl.protocol),
    );
    const isPackagedAsset = requestedUrl.protocol === "file:";
    callback({ cancel: !isLocalDevelopmentRequest && !isPackagedAsset && requestedUrl.protocol !== "devtools:" });
  });
}

function writeQaJsonSync(targetPath: string, payload: object): void {
  mkdirSync(dirname(targetPath), { recursive: true });
  writeFileSync(targetPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function waitForWindowEvent(targetWindow: BrowserWindow, eventName: "minimize", timeoutMs: number): Promise<boolean> {
  return new Promise((resolve) => {
    const timeout = setTimeout(() => resolve(false), timeoutMs);
    targetWindow.once(eventName, () => {
      clearTimeout(timeout);
      resolve(true);
    });
  });
}

async function runWindowControlQa(targetWindow: BrowserWindow): Promise<void> {
  if (!controlQaPath || (controlQaAction !== "minimize" && controlQaAction !== "close")) return;

  await new Promise((resolve) => setTimeout(resolve, 350));
  if (controlQaAction === "minimize") {
    const minimizeEvent = waitForWindowEvent(targetWindow, "minimize", 2000);
    const rendererClickDispatched = await targetWindow.webContents.executeJavaScript(`(() => {
      const control = document.querySelector('button[aria-label="Minimize application"]');
      if (!(control instanceof HTMLButtonElement)) return false;
      control.click();
      return true;
    })()`);
    const minimizeEventObserved = await minimizeEvent;
    const isMinimizedAfterClick = targetWindow.isMinimized();
    targetWindow.restore();
    await new Promise((resolve) => setTimeout(resolve, 180));
    const isRestored = !targetWindow.isMinimized() && targetWindow.isVisible();
    writeQaJsonSync(controlQaPath, {
      action: "minimize",
      processId: process.pid,
      rendererClickDispatched,
      ipcClickReceived: controlQaClickReceived,
      minimizeEventObserved,
      isMinimizedAfterClick,
      isRestored,
    });
    targetWindow.close();
    return;
  }

  targetWindow.once("closed", () => {
    writeQaJsonSync(controlQaPath, {
      action: "close",
      processId: process.pid,
      ipcClickReceived: controlQaClickReceived,
      windowDestroyed: targetWindow.isDestroyed(),
      remainingWindowCount: BrowserWindow.getAllWindows().length,
    });
  });
  void targetWindow.webContents.executeJavaScript(`(() => {
    const control = document.querySelector('button[aria-label="Close application"]');
    if (!(control instanceof HTMLButtonElement)) return false;
    control.click();
    return true;
  })()`).catch((error: unknown) => {
    if (targetWindow.isDestroyed()) return;
    writeQaJsonSync(controlQaPath, {
      action: "close",
      processId: process.pid,
      ipcClickReceived: controlQaClickReceived,
      windowDestroyed: false,
      error: error instanceof Error ? error.message : "Unknown close QA error",
    });
    targetWindow.close();
  });
}

function createMainWindow(): BrowserWindow {
  const captureViewport = readCaptureViewport();
  const mainWindow = new BrowserWindow({
    width: captureViewport?.width ?? 1500,
    height: captureViewport?.height ?? 940,
    minWidth: 900,
    minHeight: 564,
    backgroundColor: "#07070d",
    frame: false,
    useContentSize: true,
    autoHideMenuBar: true,
    show: hasAutomatedQa,
    title: "Agefield High — Mod Menu",
    webPreferences: {
      preload: join(currentDirectory, "preload.cjs"),
      partition: hasAutomatedQa ? "agefield-automated-qa" : "persist:agefield-high",
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
      devTools: Boolean(developmentUrl),
      backgroundThrottling: true,
    },
  });

  mainWindow.setAspectRatio(1500 / 940);
  enforceOfflineSessionPolicy(mainWindow.webContents.session);
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  mainWindow.webContents.on("will-navigate", (event) => event.preventDefault());
  mainWindow.once("ready-to-show", () => {
    if (!mainWindow.isVisible()) mainWindow.show();
  });
  if (controlQaPath && (controlQaAction === "minimize" || controlQaAction === "close")) {
    mainWindow.webContents.once("did-finish-load", () => {
      void runWindowControlQa(mainWindow).catch((error: unknown) => {
        writeQaJsonSync(controlQaPath, {
          action: controlQaAction,
          processId: process.pid,
          ipcClickReceived: controlQaClickReceived,
          error: error instanceof Error ? error.message : "Unknown window-control QA error",
        });
        if (!mainWindow.isDestroyed()) mainWindow.close();
      });
    });
  } else if (capturePath || metricsPath || uiQaPath || toastDismissQaPath || toastDismissedCapturePath) {
    mainWindow.webContents.once("did-finish-load", () => {
      void mainWindow.webContents.insertCSS("* { animation: none !important; transition: none !important; }")
        .then(() => {
          setTimeout(() => {
            const prepareNavigation = captureNav
              ? mainWindow.webContents.executeJavaScript(`(() => {
                  const requested = ${JSON.stringify(captureNav.toUpperCase())};
                  const target = [...document.querySelectorAll("nav button")]
                    .find((button) => button.textContent?.trim().toUpperCase() === requested);
                  if (!(target instanceof HTMLButtonElement)) return false;
                  target.click();
                  return true;
                })()`)
                .then(() => new Promise((resolve) => setTimeout(resolve, 300)))
              : Promise.resolve();
            const prepareUiQa = prepareNavigation.then(() => uiQaPath || toastDismissQaPath || toastDismissedCapturePath
              ? mainWindow.webContents.executeJavaScript(`(() => {
                  const target = [...document.querySelectorAll("nav button")]
                    .find((button) => button.textContent?.trim().toUpperCase() === "WORLD");
                  const rect = target?.getBoundingClientRect();
                  return rect ? { x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2) } : null;
                })()`)
                .then((position: { x: number; y: number } | null) => {
                  if (position) mainWindow.webContents.sendInputEvent({ type: "mouseMove", ...position });
                  return new Promise((resolve) => setTimeout(resolve, 100));
                })
                .then(() => mainWindow.webContents.executeJavaScript(`(() => {
                  const control = [...document.querySelectorAll("button")]
                    .find((button) => button.textContent?.includes("God Mode"));
                  if (!(control instanceof HTMLButtonElement)) return false;
                  control.click();
                  return true;
                })()`))
                .then(() => new Promise((resolve) => setTimeout(resolve, 320)))
              : undefined);

            void prepareUiQa.then(() => {
              const qaTasks: Promise<unknown>[] = [];
              if (capturePath) {
                qaTasks.push(mainWindow.webContents.capturePage().then((image) => writeFile(capturePath, image.toPNG())));
              }
              if (metricsPath) {
                qaTasks.push(
                  mainWindow.webContents.executeJavaScript(`(() => {
                  const root = document.documentElement;
                  const body = document.body;
                  const stage = document.querySelector("[data-design-canvas]");
                  const stageRect = stage?.getBoundingClientRect();
                  return {
                    viewport: { width: innerWidth, height: innerHeight },
                    document: {
                      clientWidth: root.clientWidth,
                      clientHeight: root.clientHeight,
                      scrollWidth: root.scrollWidth,
                      scrollHeight: root.scrollHeight,
                      overflowX: getComputedStyle(root).overflowX,
                      overflowY: getComputedStyle(root).overflowY
                    },
                    body: {
                      clientWidth: body.clientWidth,
                      clientHeight: body.clientHeight,
                      scrollWidth: body.scrollWidth,
                      scrollHeight: body.scrollHeight,
                      overflowX: getComputedStyle(body).overflowX,
                      overflowY: getComputedStyle(body).overflowY
                    },
                    designCanvas: stageRect ? {
                      left: stageRect.left,
                      top: stageRect.top,
                      right: stageRect.right,
                      bottom: stageRect.bottom,
                      width: stageRect.width,
                      height: stageRect.height,
                      scale: stage?.getAttribute("data-scale")
                    } : null,
                    removedStatusSurfaces: {
                      offlineBadgeExists: Boolean(document.querySelector(".offline-badge")),
                      titlebarStatusExists: Boolean(document.querySelector(".titlebar-status")),
                      offlineModeTextExists: document.body.textContent?.includes("OFFLINE MODE") ?? false,
                      noConnectionTextExists: document.body.textContent?.includes("NO CONNECTION REQUIRED") ?? false,
                      localOfflineSessionTextExists: document.body.textContent?.includes("LOCAL OFFLINE SESSION") ?? false
                    },
                    documentHasHorizontalScroll: root.scrollWidth > root.clientWidth,
                    documentHasVerticalScroll: root.scrollHeight > root.clientHeight,
                    bodyHasHorizontalScroll: body.scrollWidth > body.clientWidth,
                    bodyHasVerticalScroll: body.scrollHeight > body.clientHeight,
                    completeCanvasVisible: Boolean(stageRect && stageRect.left >= 0 && stageRect.top >= 0 && stageRect.right <= innerWidth && stageRect.bottom <= innerHeight)
                  };
                  })()`)
                    .then((metrics) => writeFile(metricsPath, `${JSON.stringify(metrics, null, 2)}\n`, "utf8")),
                );
              }
              if (uiQaPath) {
                qaTasks.push(
                  mainWindow.webContents.executeJavaScript(`(() => {
                    const inactiveNav = [...document.querySelectorAll("nav button")]
                      .find((button) => button.textContent?.trim().toUpperCase() === "WORLD");
                    const inactiveStyle = inactiveNav ? getComputedStyle(inactiveNav) : null;
                    const toast = document.querySelector(".toast");
                    const toastRect = toast?.getBoundingClientRect();
                    return {
                      inactiveNavFound: Boolean(inactiveNav),
                      inactiveNavMatchesHover: Boolean(inactiveNav?.matches(":hover")),
                      inactiveNavBackgroundColor: inactiveStyle?.backgroundColor ?? null,
                      inactiveNavBackgroundImage: inactiveStyle?.backgroundImage ?? null,
                      inactiveNavHoverIsTransparent: Boolean(inactiveStyle && inactiveStyle.backgroundColor === "rgba(0, 0, 0, 0)" && inactiveStyle.backgroundImage === "none"),
                      toastPresent: Boolean(toast),
                      toastText: toast?.textContent ?? null,
                      toastInLowerRight: Boolean(toastRect && toastRect.left > innerWidth / 2 && toastRect.top > innerHeight / 2),
                      footerDisclaimerPresent: document.body.textContent?.includes("All mods are for offline single player only.") ?? false
                    };
                  })()`)
                    .then((metrics) => writeFile(uiQaPath, `${JSON.stringify(metrics, null, 2)}\n`, "utf8")),
                );
              }
              if (toastDismissQaPath) {
                qaTasks.push(
                  new Promise((resolve) => setTimeout(resolve, 2150))
                    .then(() => mainWindow.webContents.executeJavaScript(`(() => ({
                      checkedAfterMilliseconds: 2150,
                      toastPresentAfterInterval: Boolean(document.querySelector(".toast"))
                    }))()`))
                    .then((metrics) => writeFile(toastDismissQaPath, `${JSON.stringify(metrics, null, 2)}\n`, "utf8")),
                );
              }
              if (toastDismissedCapturePath) {
                qaTasks.push(
                  new Promise((resolve) => setTimeout(resolve, 2150))
                    .then(() => mainWindow.webContents.capturePage())
                    .then((image) => writeFile(toastDismissedCapturePath, image.toPNG())),
                );
              }
              void Promise.all(qaTasks).finally(() => app.quit());
            });
          }, 900);
        });
    });
  }

  if (developmentUrl && isSafeDevelopmentUrl(developmentUrl)) {
    void mainWindow.loadURL(developmentUrl);
  } else {
    void mainWindow.loadFile(join(currentDirectory, "../dist/index.html"));
  }

  return mainWindow;
}

function registerOfflineHandlers(): void {
  ipcMain.handle("agefield:get-runtime-info", () => getRuntimeInfo());
  ipcMain.handle("agefield:dispatch", (_event, command: unknown): Promise<DesktopResult> | DesktopResult => {
    if (!validateCommand(command)) {
      return { accepted: false, mode: "live-offline", message: "Rejected invalid local command." };
    }
    return enqueueDispatch(command);
  });
  ipcMain.on("agefield:window-control", (event, action: unknown) => {
    if (action !== "minimize" && action !== "close") return;
    const targetWindow = BrowserWindow.fromWebContents(event.sender);
    if (!targetWindow || targetWindow.isDestroyed()) return;
    if (controlQaPath && action === controlQaAction) controlQaClickReceived = true;
    if (action === "minimize") targetWindow.minimize();
    if (action === "close") targetWindow.close();
  });
}

function registerWindowToggleHotkey(getMainWindow: () => BrowserWindow | null): void {
  const registered = globalShortcut.register(WINDOW_TOGGLE_HOTKEY, () => {
    const targetWindow = getMainWindow();
    if (!targetWindow || targetWindow.isDestroyed()) return;
    if (targetWindow.isMinimized() || !targetWindow.isVisible()) {
      if (targetWindow.isMinimized()) targetWindow.restore();
      targetWindow.show();
      targetWindow.focus();
      return;
    }
    targetWindow.minimize();
  });
  if (!registered || !globalShortcut.isRegistered(WINDOW_TOGGLE_HOTKEY)) {
    console.warn(`Agefield window hotkey unavailable: ${WINDOW_TOGGLE_HOTKEY}`);
  }
}

const hasSingleInstanceLock = app.requestSingleInstanceLock();
if (!hasSingleInstanceLock) {
  app.quit();
} else {
  let mainWindow: BrowserWindow | null = null;
  app.on("second-instance", () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  });

  void app.whenReady().then(() => {
    Menu.setApplicationMenu(null);
    registerOfflineHandlers();

    mainWindow = createMainWindow();
    registerWindowToggleHotkey(() => mainWindow);
    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) mainWindow = createMainWindow();
    });
  });

  app.on("window-all-closed", () => {
    if (process.platform !== "darwin") app.quit();
  });

  app.on("will-quit", () => globalShortcut.unregisterAll());
}
