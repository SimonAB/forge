/**
 * Forge docs theme: default follows the OS/browser (prefers-color-scheme).
 * Toggle cycles system → light → dark → system. Legacy localStorage values
 * "light" and "dark" from older builds are unchanged.
 */
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var root = document.documentElement;
    var btn = document.getElementById("theme-toggle");
    if (!btn) return;

    var mq = window.matchMedia("(prefers-color-scheme: dark)");

    function getMode() {
      var stored = localStorage.getItem("forge-theme-appearance");
      if (stored === "light" || stored === "dark" || stored === "system") {
        return stored;
      }
      return "system";
    }

    function resolvedDark(mode) {
      return mode === "dark" || (mode === "system" && mq.matches);
    }

    function applyMode(mode) {
      var dark = resolvedDark(mode);
      root.classList.toggle("dark", dark);
      var sun = btn.querySelector(".theme-toggle__icon--sun");
      var moon = btn.querySelector(".theme-toggle__icon--moon");
      if (sun) sun.hidden = dark;
      if (moon) moon.hidden = !dark;

      if (mode === "system") {
        btn.title =
          "Theme: Match system (" + (dark ? "dark" : "light") + "). Click to always use light.";
        btn.setAttribute(
          "aria-label",
          "Colour theme follows system. Activate to pin light theme."
        );
      } else if (mode === "light") {
        btn.title = "Theme: Light (always). Click for dark.";
        btn.setAttribute("aria-label", "Colour theme is light. Activate for dark theme.");
      } else {
        btn.title = "Theme: Dark (always). Click to match system appearance.";
        btn.setAttribute(
          "aria-label",
          "Colour theme is dark. Activate to follow system light or dark mode."
        );
      }
    }

    applyMode(getMode());

    function onSystemThemeChange() {
      if (getMode() === "system") {
        applyMode("system");
      }
    }

    if (mq.addEventListener) {
      mq.addEventListener("change", onSystemThemeChange);
    } else if (mq.addListener) {
      mq.addListener(onSystemThemeChange);
    }

    var cycle = ["system", "light", "dark"];

    btn.addEventListener("click", function () {
      var current = getMode();
      var i = cycle.indexOf(current);
      if (i < 0) i = 0;
      var next = cycle[(i + 1) % cycle.length];
      localStorage.setItem("forge-theme-appearance", next);
      applyMode(next);
    });
  });
})();
