import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("agefield_style_contract_tests");

const styles = readFileSync(resolve(process.cwd(), "src/styles.css"), "utf8");

describe("Agefield navigation style contract", () => {
  it("keeps inactive navigation hover transparent and keyboard focus visible", () => {
    expect(styles).toMatch(
      /\.sidebar nav button:not\(\.active\):hover\s*\{[^}]*background:\s*transparent;/s,
    );
    expect(styles).toMatch(
      /\.sidebar nav button:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--violet-bright\);/s,
    );
    expect(styles).toMatch(
      /\.sidebar nav button\.active\s*\{[^}]*background:\s*linear-gradient\(/s,
    );
  });

  it("contains no removed offline badge or titlebar status styling", () => {
    expect(styles).not.toContain(".offline-badge");
    expect(styles).not.toContain(".titlebar-status");
  });

  it("styles the credits as a two-person neon roster", () => {
    expect(styles).toMatch(/\.credits-card\s*\{[^}]*border:\s*1px solid rgba\(196, 84, 255, 0\.42\);/s);
    expect(styles).toMatch(/\.credits-roster\s*\{[^}]*grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\);/s);
    expect(styles).toMatch(/\.credit-mark\s*\{[^}]*place-items:\s*center;/s);
  });
});
