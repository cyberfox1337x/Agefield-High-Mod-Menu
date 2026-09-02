import {
  Activity,
  Backpack,
  CalendarDays,
  Code2,
  Crown,
  DollarSign,
  EyeOff,
  Gavel,
  Home,
  HeartPulse,
  FileText,
  Globe2,
  Minus,
  Moon,
  Map,
  MapPin,
  Navigation,
  Palette,
  RotateCcw,
  Settings,
  School,
  ShoppingBag,
  Shield,
  ShieldCheck,
  Sun,
  UserRound,
  X,
  Zap,
  type LucideIcon,
} from "lucide-react";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { createModAdapter, type ModAction, type ModResult, type RuntimeInfo } from "./modAdapter";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("agefield_app");

const TOAST_DURATION_MS = 2000;
const RUNTIME_REFRESH_VISIBLE_MS = 2000;
const RUNTIME_REFRESH_HIDDEN_MS = 10000;
const STORAGE_KEY = "agefield-high-offline-menu-state-v3";
const DESIGN_WIDTH = 1500;
const DESIGN_HEIGHT = 940;
const VIEWPORT_GUTTER = 0;

type NavId = "player" | "inventory" | "world" | "settings";

type OptionDefinition = Readonly<{
  id: string;
  label: string;
  description: string;
  icon: LucideIcon;
}>;

type ActionDefinition = Readonly<{
  label: string;
  description: string;
  icon: LucideIcon;
}>;

type ItemDefinition = Readonly<{
  label: string;
  category: "Food & Drinks" | "Pranks" | "Equipment" | "School & Story";
  icon: LucideIcon;
}>;

type PersistedState = Readonly<{
  enabledMods: readonly string[];
  time: number;
}>;

const verifiedCapabilities = Object.freeze([
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
]);

const navItems: readonly { id: NavId; label: string; icon: LucideIcon }[] = [
  { id: "player", label: "Player", icon: UserRound },
  { id: "inventory", label: "Inventory", icon: Backpack },
  { id: "world", label: "World", icon: Globe2 },
  { id: "settings", label: "Settings", icon: Settings },
] as const;

const primaryTeleportLocations: readonly { label: string; description: string; icon: LucideIcon }[] = [
  { label: "Agefield High", description: "School map marker", icon: School },
  { label: "Home", description: "Player home marker", icon: Home },
  { label: "Police Station", description: "Police station marker", icon: ShieldCheck },
  { label: "General Store", description: "General store marker", icon: ShoppingBag },
  { label: "Cloth Shop", description: "Clothing store marker", icon: ShoppingBag },
] as const;

function teleportIcon(label: string): LucideIcon {
  if (/school|high/i.test(label)) return School;
  if (/home/i.test(label)) return Home;
  if (/police/i.test(label)) return ShieldCheck;
  if (/store|shop/i.test(label)) return ShoppingBag;
  return MapPin;
}

const playerOptions: readonly OptionDefinition[] = [
  { id: "god-mode", label: "God Mode", description: "Invincible. No damage taken.", icon: Shield },
  { id: "infinite-stamina", label: "Infinite Stamina", description: "Never get tired.", icon: Zap },
  { id: "unlimited-money", label: "Unlimited Money", description: "Keeps the balance at 9,999.", icon: DollarSign },
  { id: "invisible-mode", label: "Invisible Mode", description: "Hide from the game world.", icon: EyeOff },
  { id: "no-detection", label: "No Detection", description: "Clear and suppress wanted status.", icon: Gavel },
  { id: "super-speed", label: "Super Speed", description: "Run at verified boosted speed.", icon: Navigation },
  { id: "no-clip", label: "No Clip", description: "Smooth flight follows facing; Space rises, Z descends.", icon: Activity },
  { id: "free-roam", label: "Free Roam", description: "Combine safe roaming and no detection.", icon: Map },
  { id: "low-gravity", label: "Low Gravity", description: "Use a reversible lunar gravity scale.", icon: Moon },
] as const;

const quickActions: readonly ActionDefinition[] = [
  { label: "Heal Player", description: "Restore Full Health", icon: HeartPulse },
  { label: "Clear Wanted", description: "Remove Wanted Level", icon: ShieldCheck },
  { label: "Restore Spawned Items", description: "Undo Menu Spawns", icon: RotateCcw },
] as const;

const spawnItems: readonly ItemDefinition[] = [
  { label: "Burger", category: "Food & Drinks", icon: ShoppingBag },
  { label: "Candy", category: "Food & Drinks", icon: ShoppingBag },
  { label: "Soda", category: "Food & Drinks", icon: ShoppingBag },
  { label: "Blue Power Bar", category: "Food & Drinks", icon: Zap },
  { label: "Red Power Bar", category: "Food & Drinks", icon: Zap },
  { label: "Hot Dog", category: "Food & Drinks", icon: ShoppingBag },
  { label: "Newspaper", category: "School & Story", icon: FileText },
  { label: "Parent Note", category: "School & Story", icon: FileText },
] as const;

const schoolSchedule = [
  { label: "First Bell", description: "Set the school clock to 08:00 AM", time: "08:00 AM", icon: School },
  { label: "Lunch Time", description: "Set the school clock to 12:00 PM", time: "12:00 PM", icon: ShoppingBag },
  { label: "Final Bell", description: "Set the school clock to 03:00 PM", time: "03:00 PM", icon: CalendarDays },
  { label: "Night Out", description: "Set the world clock to 10:00 PM", time: "10:00 PM", icon: Moon },
] as const;

const initialState: PersistedState = { enabledMods: [], time: 8 };

function readPersistedState(): PersistedState {
  try {
    const rawState = localStorage.getItem(STORAGE_KEY);
    if (!rawState) return initialState;
    const parsedState = JSON.parse(rawState) as Partial<PersistedState>;
    const time = typeof parsedState.time === "number" && parsedState.time >= 0 && parsedState.time <= 24
      ? parsedState.time
      : initialState.time;
    const enabledMods = Array.isArray(parsedState.enabledMods)
      ? parsedState.enabledMods.filter((id): id is string => typeof id === "string")
      : [];
    return { enabledMods, time };
  } catch {
    return initialState;
  }
}

function formatTime(decimalHours: number): string {
  const roundedMinutes = Math.round(decimalHours * 60);
  const hour24 = Math.floor(roundedMinutes / 60) % 24;
  const minutes = roundedMinutes % 60;
  const period = hour24 >= 12 ? "PM" : "AM";
  const hour12 = hour24 % 12 || 12;
  return `${hour12.toString().padStart(2, "0")}:${minutes.toString().padStart(2, "0")} ${period}`;
}

function calculateStageScale(viewportWidth: number, viewportHeight: number): number {
  const availableWidth = Math.max(1, viewportWidth - VIEWPORT_GUTTER * 2);
  const availableHeight = Math.max(1, viewportHeight - VIEWPORT_GUTTER * 2);
  return Math.min(availableWidth / DESIGN_WIDTH, availableHeight / DESIGN_HEIGHT);
}

function sameStringList(left?: readonly string[], right?: readonly string[]): boolean {
  if (left === right) return true;
  if (!left || !right || left.length !== right.length) return false;
  return left.every((value, index) => value === right[index]);
}

function sameRuntimeInfo(left: RuntimeInfo, right: RuntimeInfo): boolean {
  return left.platform === right.platform
    && left.mode === right.mode
    && left.connected === right.connected
    && left.bridgeVersion === right.bridgeVersion
    && sameStringList(left.activeMods, right.activeMods)
    && sameStringList(left.capabilities, right.capabilities);
}

function ToggleRow({ option, enabled, onToggle }: { option: OptionDefinition; enabled: boolean; onToggle: () => void }) {
  const Icon = option.icon;
  return (
    <button className="toggle-row" type="button" onClick={onToggle} aria-pressed={enabled}>
      <Icon className="option-icon" aria-hidden="true" />
      <span className="option-copy">
        <strong>{option.label}</strong>
        <small>{option.description}</small>
      </span>
      <span className={`switch ${enabled ? "is-on" : ""}`} aria-hidden="true"><span /></span>
    </button>
  );
}

function BrandLogo() {
  return (
    <div className="brand-logo" aria-label="Agefield High — Rock the School">
      <Crown className="brand-crown" aria-hidden="true" />
      <span className="brand-agefield">AGEFIELD</span>
      <span className="brand-high">HIGH</span>
      <span className="brand-ribbon">ROCK THE SCHOOL</span>
      <span className="brand-spark" aria-hidden="true">✦</span>
    </div>
  );
}

function TitleBlock() {
  return (
    <div className="title-block">
      <div className="crest" aria-hidden="true"><Shield /><Zap /></div>
      <div>
        <h1>MOD MENU</h1>
        <span>Play your way. Your school, your rules.</span>
      </div>
    </div>
  );
}

function WindowTitlebar() {
  return (
    <div className="window-titlebar" data-window-drag-region>
      <div className="titlebar-identity">
        <span className="titlebar-crest" aria-hidden="true"><Shield /><strong>A</strong></span>
        <strong>AGEFIELD HIGH</strong>
      </div>
      <div className="window-controls">
        <button type="button" aria-label="Minimize application" title="Minimize" onClick={() => window.agefieldDesktop?.minimizeWindow()}>
          <Minus aria-hidden="true" />
        </button>
        <button className="close-control" type="button" aria-label="Close application" title="Close" onClick={() => window.agefieldDesktop?.closeWindow()}>
          <X aria-hidden="true" />
        </button>
      </div>
    </div>
  );
}

function App() {
  const adapter = useMemo(() => createModAdapter(), []);
  const [activeNav, setActiveNav] = useState<NavId>("player");
  const [state, setState] = useState<PersistedState>(readPersistedState);
  const [toast, setToast] = useState("");
  const [itemCategory, setItemCategory] = useState<ItemDefinition["category"]>("Food & Drinks");
  const [selectedItem, setSelectedItem] = useState("Burger");
  const [runtimeInfo, setRuntimeInfo] = useState<RuntimeInfo>({
    platform: "unknown",
    mode: adapter.mode,
    connected: false,
  });
  const [stageScale, setStageScale] = useState(() => calculateStageScale(window.innerWidth, window.innerHeight));
  const toastTimeoutRef = useRef<number | null>(null);

  const syncRuntimeInfo = useCallback((info: RuntimeInfo) => {
    setRuntimeInfo((current) => (sameRuntimeInfo(current, info) ? current : info));
    if (info.connected && info.activeMods) {
      setState((current) => (sameStringList(current.enabledMods, info.activeMods)
        ? current
        : { ...current, enabledMods: info.activeMods ?? [] }));
    }
  }, []);

  const capabilities = useMemo(
    () => new Set(runtimeInfo.connected ? runtimeInfo.capabilities ?? [] : verifiedCapabilities),
    [runtimeInfo.capabilities, runtimeInfo.connected],
  );
  const visiblePlayerOptions = playerOptions.filter((option) => capabilities.has(`toggle:${option.label}`));
  const visibleQuickActions = quickActions.filter((action) => capabilities.has(`quick-action:${action.label}`));
  const visiblePlayerQuickActions = visibleQuickActions.filter((action) => action.label !== "Restore Spawned Items");
  const hasTimeControl = capabilities.has("set-time:*");
  const hasPlayerReset = capabilities.has("reset-player:*");
  const allTeleportLabels = [...capabilities]
    .filter((capability) => capability.startsWith("teleport:") && capability !== "teleport:Return")
    .map((capability) => capability.slice("teleport:".length));
  const primaryTeleportLabels = primaryTeleportLocations
    .map(({ label }) => label)
    .filter((label) => allTeleportLabels.includes(label));
  const visibleTeleportLocations = [
    ...primaryTeleportLabels,
    ...allTeleportLabels.filter((label) => !primaryTeleportLabels.includes(label)).sort((left, right) => left.localeCompare(right)),
  ].map((label) => {
    const primary = primaryTeleportLocations.find((location) => location.label === label);
    return primary ?? { label, description: "Verified world map marker", icon: teleportIcon(label) };
  });
  const hasTeleportControls = visibleTeleportLocations.length > 0;
  const hasTeleportReturn = capabilities.has("teleport:Return");
  const visibleSpawnItems = useMemo(
    () => spawnItems.filter(({ label }) => capabilities.has(`spawn-item:${label}`)),
    [capabilities],
  );
  const visibleItemCategories = useMemo(
    () => [...new Set(visibleSpawnItems.map(({ category }) => category))],
    [visibleSpawnItems],
  );
  const itemsInSelectedCategory = useMemo(
    () => visibleSpawnItems.filter(({ category }) => category === itemCategory),
    [itemCategory, visibleSpawnItems],
  );
  const hasSpawnControls = visibleSpawnItems.length > 0;

  useEffect(() => {
    let active = true;
    let refreshTimeout: number | null = null;
    let refreshInFlight = false;

    const scheduleRefresh = () => {
      if (!active) return;
      refreshTimeout = window.setTimeout(
        refreshRuntimeInfo,
        document.hidden ? RUNTIME_REFRESH_HIDDEN_MS : RUNTIME_REFRESH_VISIBLE_MS,
      );
    };

    function refreshRuntimeInfo() {
      if (!active || refreshInFlight) return;
      refreshInFlight = true;
      void adapter.getRuntimeInfo().then((info) => {
        if (active) syncRuntimeInfo(info);
      }).catch(() => {
        if (active) {
          setRuntimeInfo((current) => (current.connected ? { ...current, connected: false } : current));
        }
      }).finally(() => {
        refreshInFlight = false;
        scheduleRefresh();
      });
    }

    const handleVisibilityChange = () => {
      if (refreshTimeout !== null) {
        window.clearTimeout(refreshTimeout);
        refreshTimeout = null;
      }
      if (refreshInFlight) return;
      if (document.hidden) scheduleRefresh();
      else refreshRuntimeInfo();
    };

    refreshRuntimeInfo();
    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => {
      active = false;
      if (refreshTimeout !== null) window.clearTimeout(refreshTimeout);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [adapter, syncRuntimeInfo]);

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }, [state]);

  useEffect(() => {
    if (activeNav === "inventory" && !hasSpawnControls) setActiveNav("player");
    if (activeNav === "world" && !hasTeleportControls && !hasTimeControl) setActiveNav("player");
  }, [activeNav, hasSpawnControls, hasTeleportControls, hasTimeControl]);

  useEffect(() => {
    if (!visibleItemCategories.includes(itemCategory)) {
      setItemCategory(visibleItemCategories[0] ?? "Food & Drinks");
      return;
    }
    if (!itemsInSelectedCategory.some(({ label }) => label === selectedItem)) {
      setSelectedItem(itemsInSelectedCategory[0]?.label ?? "");
    }
  }, [itemCategory, itemsInSelectedCategory, selectedItem, visibleItemCategories]);

  useLayoutEffect(() => {
    function fitCanvasToViewport() {
      setStageScale(calculateStageScale(window.innerWidth, window.innerHeight));
    }

    fitCanvasToViewport();
    window.addEventListener("resize", fitCanvasToViewport);
    return () => window.removeEventListener("resize", fitCanvasToViewport);
  }, []);

  useEffect(() => () => {
    if (toastTimeoutRef.current !== null) window.clearTimeout(toastTimeoutRef.current);
  }, []);

  function showToast(message: string) {
    if (toastTimeoutRef.current !== null) window.clearTimeout(toastTimeoutRef.current);
    setToast(message);
    toastTimeoutRef.current = window.setTimeout(() => {
      setToast("");
      toastTimeoutRef.current = null;
    }, TOAST_DURATION_MS);
  }

  async function dispatch(action: ModAction, detail: string, enabled?: boolean): Promise<ModResult> {
    const result = await adapter.dispatch({ action, detail, enabled });
    showToast(result.message);
    void adapter.getRuntimeInfo().then(syncRuntimeInfo).catch(() => {
      setRuntimeInfo((current) => (current.connected ? { ...current, connected: false } : current));
    });
    return result;
  }

  async function toggleOption(option: OptionDefinition) {
    const isEnabled = !state.enabledMods.includes(option.id);
    const result = await dispatch("toggle", option.label, isEnabled);
    if (result.accepted) {
      setState((currentState) => ({
        ...currentState,
        enabledMods: isEnabled
          ? [...currentState.enabledMods, option.id]
          : currentState.enabledMods.filter((id) => id !== option.id),
      }));
    }
  }

  function restoreDefaults() {
    localStorage.removeItem(STORAGE_KEY);
    setState(initialState);
    setItemCategory("Food & Drinks");
    setSelectedItem("Burger");
    void dispatch("reset-interface", "Interface defaults");
  }

  async function resetPlayer() {
    const result = await dispatch("reset-player", "Player state");
    if (result.accepted) setState((currentState) => ({ ...currentState, enabledMods: [] }));
  }

  function renderSettings() {
    return (
      <section className="page-panel inner-page" aria-labelledby="settings-heading">
        <div className="inner-page-heading">
          <div><span className="eyebrow">LOCAL APPLICATION</span><h2 id="settings-heading">Settings</h2></div>
          <span className="preview-chip">VERIFIED CONTROLS ONLY</span>
        </div>
        <div className="settings-grid">
          <div className="setting-card"><Minus /><div><strong>Window hotkey</strong><small>Press F10 to minimize or restore the menu.</small></div><span>GLOBAL</span></div>
          <div className="credits-card" aria-labelledby="credits-heading">
            <div className="credits-card-heading">
              <div>
                <span className="credits-kicker">CREATIVE TEAM</span>
                <h3 id="credits-heading">Credits</h3>
              </div>
              <span className="credits-stamp">AGEFIELD CREW</span>
            </div>
            <div className="credits-roster">
              <div className="credit-person">
                <span className="credit-mark" aria-hidden="true"><Code2 /></span>
                <div><strong>Cyberfox1337x</strong><small>Full-Stack Developer</small></div>
                <span className="credit-number" aria-hidden="true">01</span>
              </div>
              <div className="credit-person">
                <span className="credit-mark" aria-hidden="true"><Palette /></span>
                <div><strong>tooka223</strong><small>Graphic Designer</small><p>Helped shape the menu design.</p></div>
                <span className="credit-number" aria-hidden="true">02</span>
              </div>
            </div>
          </div>
        </div>
        <button className="outline-button danger" type="button" onClick={restoreDefaults}><RotateCcw /> RESTORE INTERFACE DEFAULTS</button>
      </section>
    );
  }

  function renderInventory() {
    const picker = (
      <>
        <label className="select-shell">
          <span className="sr-only">Item category</span>
          <select value={itemCategory} onChange={(event) => setItemCategory(event.target.value as ItemDefinition["category"])}>
            {visibleItemCategories.map((category) => <option key={category} value={category}>{category}</option>)}
          </select>
        </label>
        <label className="select-shell">
          <span className="sr-only">Item</span>
          <select value={selectedItem} onChange={(event) => setSelectedItem(event.target.value)}>
            {itemsInSelectedCategory.map(({ label }) => <option key={label} value={label}>{label}</option>)}
          </select>
        </label>
        <button className="outline-button spawn-button" type="button" disabled={!selectedItem} onClick={() => void dispatch("spawn-item", selectedItem)}>
          <Backpack aria-hidden="true" /> SPAWN ITEM
        </button>
      </>
    );

    return (
      <section className="page-panel inner-page inventory-page" aria-labelledby="inventory-heading">
        <div className="inner-page-heading">
          <div><span className="eyebrow">VERIFIED ITEM CLASSES</span><h2 id="inventory-heading">Inventory</h2></div>
          <span className="preview-chip">{visibleSpawnItems.length} LIVE ITEMS</span>
        </div>
        <div className="inventory-workbench">{picker}</div>
        <div className="feature-grid inventory-feature-grid">
          {visibleSpawnItems.slice(0, 6).map(({ label, category, icon: Icon }) => (
            <button className="feature-card" key={label} type="button" onClick={() => void dispatch("spawn-item", label)}>
              <span className="feature-icon"><Icon aria-hidden="true" /></span>
              <span><strong>{label}</strong><small>{category}</small></span>
              <span className="feature-cta">SPAWN</span>
            </button>
          ))}
        </div>
        {capabilities.has("quick-action:Restore Spawned Items") && (
          <button className="outline-button inventory-restore" type="button" onClick={() => void dispatch("quick-action", "Restore Spawned Items")}><RotateCcw /> RESTORE ITEMS SPAWNED THIS SESSION</button>
        )}
      </section>
    );
  }

  function renderWorld() {
    return (
      <section className="page-panel inner-page world-page" aria-labelledby="world-heading">
        <div className="inner-page-heading">
          <div><span className="eyebrow">LIVE WORLD TOOLS</span><h2 id="world-heading">World</h2></div>
          <span className="preview-chip">MAP &amp; TIME</span>
        </div>
        <div className="world-dashboard-grid">
          {hasTeleportControls && (
            <section className="world-module world-teleport-module" aria-labelledby="world-teleport-heading">
              <h3 id="world-teleport-heading"><MapPin aria-hidden="true" /> TELEPORT</h3>
              <div className="teleport-list">
                {visibleTeleportLocations.map(({ label, description, icon: Icon }) => (
                  <div className="teleport-row" key={label}>
                    <Icon aria-hidden="true" />
                    <span><strong>{label}</strong><small>{description}</small></span>
                    <button type="button" onClick={() => void dispatch("teleport", label)}>TELEPORT</button>
                  </div>
                ))}
              </div>
              {hasTeleportReturn && <button className="outline-button" type="button" onClick={() => void dispatch("teleport", "Return")}><RotateCcw /> RETURN TO PREVIOUS LOCATION</button>}
            </section>
          )}
          {hasTimeControl && (
            <div className="world-side-stack">
              <section className="world-module world-time-module" aria-labelledby="world-time-heading">
                <h3 id="world-time-heading"><Moon aria-hidden="true" /> TIME OF DAY</h3>
                <div className="time-row">
                  <span>World Clock</span>
                  <output htmlFor="time-range">{formatTime(state.time)}</output>
                </div>
                <div className="range-wrap">
                  <input
                    id="time-range"
                    aria-label="Time of day"
                    type="range"
                    min="0"
                    max="24"
                    step="0.25"
                    value={state.time}
                    onChange={(event) => setState((currentState) => ({ ...currentState, time: Number(event.target.value) }))}
                    onPointerUp={(event) => void dispatch("set-time", formatTime(Number(event.currentTarget.value)))}
                    onKeyUp={(event) => void dispatch("set-time", formatTime(Number(event.currentTarget.value)))}
                  />
                  <Sun aria-hidden="true" />
                </div>
              </section>
              <section className="world-module world-schedule-module" aria-labelledby="world-schedule-heading">
                <h3 id="world-schedule-heading"><CalendarDays aria-hidden="true" /> SCHOOL DAY</h3>
                <div className="schedule-grid">
                  {schoolSchedule.map(({ label, time, icon: Icon }) => (
                    <button key={label} type="button" onClick={() => void dispatch("set-time", time)}>
                      <Icon aria-hidden="true" /><span><strong>{label}</strong><small>{time}</small></span>
                    </button>
                  ))}
                </div>
              </section>
            </div>
          )}
        </div>
      </section>
    );
  }

  function renderPlayer() {
    return (
      <div className="player-page-stack">
        <section className="page-panel player-options" aria-labelledby="player-options-heading">
          <h2 id="player-options-heading">PLAYER OPTIONS</h2>
          <div className="toggle-grid">
            {visiblePlayerOptions.map((option) => (
              <ToggleRow
                key={option.id}
                option={option}
                enabled={state.enabledMods.includes(option.id)}
                onToggle={() => void toggleOption(option)}
              />
            ))}
          </div>
          {hasPlayerReset && (
            <div className="reset-row">
              <RotateCcw aria-hidden="true" />
              <span><strong>Reset Player</strong><small>Restore supported stats &amp; mod states.</small></span>
              <button type="button" onClick={() => void resetPlayer()}>RESET</button>
            </div>
          )}
        </section>
        {visiblePlayerQuickActions.length > 0 && (
          <section className="page-panel quick-panel" aria-labelledby="quick-heading">
            <h2 id="quick-heading">QUICK ACTIONS</h2>
            <div className="quick-grid verified-quick-grid">
              {visiblePlayerQuickActions.map(({ label, description, icon: Icon }) => (
                <button key={label} type="button" onClick={() => void dispatch("quick-action", label)}>
                  <Icon aria-hidden="true" /><strong>{label}</strong><small>{description}</small>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>
    );
  }

  const visibleNavItems = navItems.filter(({ id }) => {
    if (id === "inventory") return hasSpawnControls;
    if (id === "world") return hasTeleportControls || hasTimeControl;
    return true;
  });

  return (
    <main className="app-shell">
      <div className="scale-frame" style={{ width: DESIGN_WIDTH * stageScale, height: DESIGN_HEIGHT * stageScale }}>
        <div className="app-stage" data-design-canvas data-scale={stageScale.toFixed(4)} style={{ transform: `scale(${stageScale})` }}>
          <div className="window-frame">
            <WindowTitlebar />
            <div className="app-frame">
              <header className="app-header"><BrandLogo /><TitleBlock /></header>
              <div className="app-body">
                <aside className="sidebar">
                  <nav aria-label="Mod menu sections">
                    {visibleNavItems.map(({ id, label, icon: Icon }) => (
                      <button key={id} className={activeNav === id ? "active" : ""} type="button" onClick={() => setActiveNav(id)}>
                        <Icon aria-hidden="true" /><span>{label}</span>
                      </button>
                    ))}
                  </nav>
                  <div className="school-badge"><div className="mini-crest"><Shield /><span>A</span></div><span><strong>AGEFIELD HIGH</strong><small>EST. 1987 ━</small></span></div>
                </aside>
                <div className="content-area">
                  {activeNav === "player" && renderPlayer()}
                  {activeNav === "inventory" && renderInventory()}
                  {activeNav === "world" && renderWorld()}
                  {activeNav === "settings" && renderSettings()}
                </div>
              </div>
              <footer>
                <span className="footer-message">Have fun and rock Agefield High! <span aria-hidden="true">☠</span></span>
                <span className="footer-version">v1.6.0</span>
              </footer>
            </div>
            {toast && <div className="toast" role="status" aria-live="polite">{toast}</div>}
          </div>
        </div>
      </div>
    </main>
  );
}

export default App;
