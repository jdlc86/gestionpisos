import { supabase, getCurrentSession } from "./supabase-client.js";
import {
  authFlowUrl,
  currentPageNext,
  privilegedMfaRoute,
  requiresPrivilegedMfa
} from "./mfa-common.js?v=2026091701";
import { mountBottomNavigation } from "./bottom-nav.js?v=2026091901";

const loginUrl = new URL("./login.html", window.location.href);
loginUrl.searchParams.set("next", window.location.pathname.split("/").pop() || "index.html");
const currentPage = window.location.pathname.split("/").pop() || "index.html";
const isHomePage = currentPage === "index.html";


async function pendingStaffOnboarding() {
  const { data, error } = await supabase.rpc("get_my_internal_staff_onboarding");
  if (error) return null;
  return data?.status === "pending" ? data : null;
}

async function pendingExternalOnboarding() {
  const { data, error } = await supabase.rpc("get_my_external_account_onboarding");
  if (error) return null;
  return data?.status === "pending" ? data : null;
}

function homeActionHost() {
  return document.querySelector(".topbar .global-actions") || document.querySelector(".topbar");
}

function addMfaSecurityAction() {
  const topbar = homeActionHost();
  if (!topbar || document.getElementById("mfaSetupAction")) return;
  const button = document.createElement("button");
  button.id = "mfaSetupAction";
  button.type = "button";
  button.className = "ghost";
  button.textContent = "MFA";
  button.setAttribute("aria-label", "Configurar MFA");
  button.title = "Configurar MFA";
  button.addEventListener("click", () => {
    window.location.assign(authFlowUrl("mfa-setup.html", currentPageNext()));
  });
  topbar.append(button);
}

async function requireSession() {
  try {
    const session = await getCurrentSession();
    if (!session) {
      window.location.replace(loginUrl.href);
      return;
    }

    const staffOnboarding = await pendingStaffOnboarding();
    if (staffOnboarding) {
      const activationUrl = new URL("./activate-account.html", window.location.href);
      window.location.replace(activationUrl.href);
      return;
    }

    const externalOnboarding = await pendingExternalOnboarding();
    if (externalOnboarding) {
      const activationUrl = new URL("./activate-external-account.html", window.location.href);
      window.location.replace(activationUrl.href);
      return;
    }

    const mfa = await privilegedMfaRoute(supabase, session, { requireEnrollment: true });
    if (mfa.route) {
      window.location.replace(authFlowUrl(mfa.route, currentPageNext()));
      return;
    }

    document.documentElement.removeAttribute("data-auth-pending");
    mountBottomNavigation({ supabase, session }).catch(error => {
      console.error("bottom_navigation_failed", error);
    });

    if (isHomePage && requiresPrivilegedMfa(session)) addMfaSecurityAction();

    const topbar = homeActionHost();
    if (isHomePage && topbar && !document.getElementById("logoutBtn")) {
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
  } catch (error) {
    console.error("auth_guard_failed", error);
    window.location.replace(loginUrl.href);
  }
}

supabase.auth.onAuthStateChange((event, session) => {
  if (event === "SIGNED_OUT" || !session) {
    window.location.replace(loginUrl.href);
  }
});

requireSession();
