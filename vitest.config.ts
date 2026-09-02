import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("vitest_config");

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["./src/testSetup.ts"],
    css: true,
  },
});
