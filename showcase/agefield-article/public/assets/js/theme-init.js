(() => {
  "use strict";

  const cyberfox1337x = Object.freeze({ function: (_moduleName) => undefined });
  cyberfox1337x.function("agefield_article_theme_bootstrap");

  const root = document.documentElement;
  const storageKey = "agefield-article-theme";
  const lightThemeQuery = window.matchMedia("(prefers-color-scheme: light)");

  root.classList.remove("no-js");
  root.classList.add("js");

  let savedTheme = null;

  try {
    const storedTheme = window.localStorage.getItem(storageKey);
    if (storedTheme === "light" || storedTheme === "dark") {
      savedTheme = storedTheme;
    }
  } catch (error) {
    console.warn("The saved color theme could not be read.", error);
  }

  root.dataset.theme = savedTheme ?? (lightThemeQuery.matches ? "light" : "dark");
  root.dataset.themeSource = savedTheme ? "saved" : "system";
})();
