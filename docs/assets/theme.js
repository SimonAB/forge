(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var root = document.documentElement;
    var btn = document.getElementById("theme-toggle");
    if (!btn) return;

    function setIcon() {
      var dark = root.classList.contains("dark");
      var sun = btn.querySelector(".theme-toggle__icon--sun");
      var moon = btn.querySelector(".theme-toggle__icon--moon");
      if (sun) sun.hidden = dark;
      if (moon) moon.hidden = !dark;
    }

    setIcon();
    btn.addEventListener("click", function () {
      var dark = root.classList.toggle("dark");
      localStorage.setItem("forge-theme-appearance", dark ? "dark" : "light");
      setIcon();
    });
  });
})();
