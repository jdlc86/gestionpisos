let installPrompt = null;
const installBtn = document.getElementById("installBtn");

window.addEventListener("beforeinstallprompt", event => {
  event.preventDefault();
  installPrompt = event;
  if (installBtn) installBtn.hidden = false;
});

if (installBtn) {
  installBtn.addEventListener("click", async () => {
    if (!installPrompt) return;
    installPrompt.prompt();
    await installPrompt.userChoice;
    installPrompt = null;
    installBtn.hidden = true;
  });
}

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => navigator.serviceWorker.register("./sw.js").catch(() => {}));
}

(() => {
  const key = "gestionpisos-theme";
  const apply = theme => {
    document.documentElement.dataset.theme = theme;
    document.querySelectorAll("[data-theme-icon]").forEach(node => {
      node.textContent = theme === "dark" ? "☀" : "☾";
    });
    document.querySelectorAll("[data-theme-menu-label]").forEach(node => {
      node.textContent = theme === "dark" ? "Modo claro" : "Modo oscuro";
    });
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = theme === "dark" ? "#0d1117" : "#ffffff";
  };

  apply(localStorage.getItem(key) || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"));
  document.addEventListener("click", event => {
    if (!event.target.closest("[data-theme-toggle]")) return;
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    localStorage.setItem(key, next);
    apply(next);
  });
})();

const premiumIcons = {
  portfolio: '<path d="M4 20V9.5L12 4l8 5.5V20"/><path d="M8 20v-6h8v6"/><path d="M6.5 10.5h11"/>',
  operations: '<path d="M5 19V11"/><path d="M12 19V5"/><path d="M19 19V9"/><path d="M3 19h18"/>',
  incidents: '<path d="M12 4 3.5 19h17L12 4Z"/><path d="M12 9v4.5"/><path d="M12 16.7h.01"/>',
  workflows: '<path d="M7 7h8a4 4 0 0 1 4 4v1"/><path d="m16 4 3 3-3 3"/><path d="M17 17H9a4 4 0 0 1-4-4v-1"/><path d="m8 20-3-3 3-3"/>',
  cleaning: '<path d="m14.5 4.5 5 5"/><path d="M16.5 6.5 8 15l-4 5 5-4 8.5-8.5"/><path d="m8 15 1 1"/><path d="M18.5 3.5v2M20.5 5.5h-2"/>',
  permissions: '<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/><path d="M12 14v2.5"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6 7 7M17 17l1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4"/>',
  inspections: '<circle cx="10.5" cy="10.5" r="5.5"/><path d="m15 15 5 5"/><path d="m8.5 10.5 1.3 1.3 2.7-3"/>',
  documents: '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5"/><path d="M9 13h6M9 17h6"/>',
  builder: '<path d="M12 5v14M5 12h14"/><path d="M18.5 3.5v3M20 5h-3"/>',
  definitions: '<path d="M5 7h14v12H5z"/><path d="M8 4h8v3"/><path d="M8 11h8M8 15h5"/>',
  camera: '<path d="M4 8h4l1.5-2h5L16 8h4v11H4z"/><circle cx="12" cy="13.5" r="3.3"/>',
  tasks: '<path d="M10 6h10M10 12h10M10 18h10"/><path d="m4 6 1.3 1.3L8 4.7M4 12l1.3 1.3L8 10.7M4 18l1.3 1.3L8 16.7"/>',
  history: '<circle cx="12" cy="12" r="8"/><path d="M12 8v5l3 2"/><path d="M4 5v4h4"/>',
  database: '<ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6"/><path d="M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6"/>',
  storage: '<path d="M4 7h6l2 2h8v10H4z"/><path d="M4 7V5h6l2 2"/>',
  users: '<circle cx="9" cy="8" r="3"/><path d="M3.5 19c.8-3.5 2.8-5 5.5-5s4.7 1.5 5.5 5"/><circle cx="17" cy="9" r="2.2"/><path d="M15.5 14.5c2.6-.3 4.3 1.1 5 3.5"/>',
  recovery: '<path d="M5 8V4h4"/><path d="M5.5 5.5A8 8 0 1 1 4 15"/><path d="M12 8v4l3 2"/>',
  emergency: '<path d="M12 3 5 6v5c0 4.6 2.8 7.9 7 10 4.2-2.1 7-5.4 7-10V6l-7-3Z"/><path d="M12 8v5M12 16h.01"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m4 7 8 6 8-6"/>',
  open: '<path d="M5 7h14v12H5z"/><path d="M8 4h8v3"/><path d="M9 11h6M9 15h4"/>',
  urgent: '<path d="M12 4 3.5 19h17L12 4Z"/><path d="M12 9v4.5"/><path d="M12 16.7h.01"/>',
  resolved: '<circle cx="12" cy="12" r="8"/><path d="m8.5 12 2.3 2.3 4.7-5"/>',
  home: '<path d="M4 20V9.5L12 4l8 5.5V20"/><path d="M8 20v-6h8v6"/>',
  admins: '<path d="M12 3 5 6v5c0 4.6 2.8 7.9 7 10 4.2-2.1 7-5.4 7-10V6l-7-3Z"/><path d="M9.5 12 11 13.5l3.5-3.5"/>',
  employees: '<circle cx="9" cy="8" r="3"/><path d="M3.5 19c.8-3.5 2.8-5 5.5-5s4.7 1.5 5.5 5"/><path d="M16 8h4M18 6v4"/>',
  capabilities: '<circle cx="8" cy="12" r="3"/><path d="M11 12h9M17 12v3M14 12v2"/>',
  rooms: '<path d="M4 5h16v14H4z"/><path d="M8 5v14M8 12h12"/><circle cx="11" cy="9" r=".7"/>',
  edit: '<path d="m5 19 3.5-.8L18 8.7 15.3 6 5.8 15.5 5 19Z"/><path d="m13.8 7.5 2.7 2.7"/>',
  archive: '<path d="M5 8h14v11H5z"/><path d="M4 5h16v3H4z"/><path d="M9 12h6"/>'
};

function renderPremiumIcons(root = document) {
  root.querySelectorAll("[data-premium-icon]").forEach(node => {
    if (node.dataset.premiumIconReady === "1") return;
    const markup = premiumIcons[node.dataset.premiumIcon];
    if (!markup) return;
    node.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + markup + "</svg>";
    node.dataset.premiumIconReady = "1";
  });
}

renderPremiumIcons();
window.AllaisoPremiumIcons = { render: renderPremiumIcons };
