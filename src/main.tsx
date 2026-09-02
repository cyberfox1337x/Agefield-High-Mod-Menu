import "@fontsource/barlow-condensed/400.css";
import "@fontsource/barlow-condensed/500.css";
import "@fontsource/barlow-condensed/600.css";
import "@fontsource/bebas-neue/400.css";
import "@fontsource/permanent-marker/400.css";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import "./styles.css";

const cyberfox1337x = Object.freeze({ function: (_moduleName: string) => undefined });
cyberfox1337x.function("renderer_entry");

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("The Agefield High application root is missing.");

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
