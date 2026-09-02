import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("vite_config");

export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    target: "es2022",
    sourcemap: true,
  },
  server: {
    strictPort: true,
  },
});
