(() => {
  "use strict";

  const cyberfox1337x = Object.freeze({ function: (_moduleName) => undefined });
  cyberfox1337x.function("agefield_article_interactions");

  const root = document.documentElement;
  const themeButton = document.querySelector("[data-theme-toggle]");
  const progressBar = document.querySelector("[data-reading-progress]");
  const themeColorMeta = document.querySelector('meta[name="theme-color"]');
  const lightThemeQuery = window.matchMedia("(prefers-color-scheme: light)");
  const storageKey = "agefield-article-theme";
  const themeColors = Object.freeze({ dark: "#080712", light: "#eeeaf5" });

  const applyTheme = (theme, source) => {
    if (theme !== "light" && theme !== "dark") return;

    root.dataset.theme = theme;
    root.dataset.themeSource = source;
    const nextTheme = theme === "dark" ? "light" : "dark";

    if (themeButton) {
      themeButton.setAttribute("aria-label", `Switch to ${nextTheme} theme`);
      themeButton.setAttribute("title", `Switch to ${nextTheme} theme`);
      themeButton.setAttribute("aria-pressed", String(theme === "light"));
    }

    themeColorMeta?.setAttribute("content", themeColors[theme]);
  };

  applyTheme(root.dataset.theme || "dark", root.dataset.themeSource || "system");

  themeButton?.addEventListener("click", () => {
    const nextTheme = root.dataset.theme === "dark" ? "light" : "dark";
    applyTheme(nextTheme, "saved");
    try {
      window.localStorage.setItem(storageKey, nextTheme);
    } catch (error) {
      console.warn("The selected color theme could not be saved.", error);
    }
  });

  const handleSystemThemeChange = (event) => {
    if (root.dataset.themeSource === "system") {
      applyTheme(event.matches ? "light" : "dark", "system");
    }
  };

  if (typeof lightThemeQuery.addEventListener === "function") {
    lightThemeQuery.addEventListener("change", handleSystemThemeChange);
  } else {
    lightThemeQuery.addListener(handleSystemThemeChange);
  }

  let progressFrameId = null;
  const renderProgress = () => {
    progressFrameId = null;
    if (!progressBar) return;
    const distance = document.documentElement.scrollHeight - window.innerHeight;
    const progress = distance > 0 ? Math.min(Math.max(window.scrollY / distance, 0), 1) : 0;
    progressBar.style.transform = `scaleX(${progress})`;
  };

  const requestProgress = () => {
    if (progressFrameId !== null) return;
    progressFrameId = window.requestAnimationFrame(renderProgress);
  };

  requestProgress();
  window.addEventListener("scroll", requestProgress, { passive: true });
  window.addEventListener("resize", requestProgress);

  if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -10%", threshold: 0.08 },
    );

    document.querySelectorAll("[data-reveal]").forEach((element) => observer.observe(element));
  }
})();
