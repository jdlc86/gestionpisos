import { supabase, getCurrentSession } from "./supabase-client.js";

const loginUrl = new URL("./login.html", window.location.href);
loginUrl.searchParams.set("next", window.location.pathname.split("/").pop() || "index.html");

async function pendingStaffOnboarding() {
  const { data, error } = await supabase.rpc("get_my_internal_staff_onboarding");
  if (error) return null;
  return data?.status === "pending" ? data : null;
}

async function requireSession() {
  try {
    const session = await getCurrentSession();
    if (!session) {
      window.location.replace(loginUrl.href);
      return;
    }

    const onboarding = await pendingStaffOnboarding();
    if (onboarding) {
      const activationUrl = new URL("./activate-account.html", window.location.href);
      window.location.replace(activationUrl.href);
      return;
    }

    document.documentElement.removeAttribute("data-auth-pending");

    const topbar = document.querySelector(".topbar");
    if (topbar && !document.getElementById("logoutBtn")) {
      const button = document.createElement("button");
      button.id = "logoutBtn";
      button.type = "button";
      button.className = "ghost";
      button.textContent = "Salir";
      button.addEventListener("click", async () => {
        button.disabled = true;
        await supabase.auth.signOut();
        window.location.replace("./login.html");
      });
      topbar.append(button);
    }
  } catch {
    window.location.replace(loginUrl.href);
  }
}

supabase.auth.onAuthStateChange((event, session) => {
  if (event === "SIGNED_OUT" || !session) {
    window.location.replace(loginUrl.href);
  }
});

requireSession();
