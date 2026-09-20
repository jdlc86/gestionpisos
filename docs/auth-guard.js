import { supabase, getCurrentSession } from "./supabase-client.js";
import {
  authFlowUrl,
  currentPageNext,
  privilegedMfaRoute,
  requiresPrivilegedMfa
} from "./mfa-common.js?v=2026091701";
import { mountBottomNavigation } from "./bottom-nav.js?v=2026091901";
import { mountNotificationCenter } from "./notification-center.js?v=2026092001";

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

async function currentPlatformAccess() {
  const { data, error } = await supabase.rpc("has_current_platform_access_v1");
  if (error) throw error;
  return data === true;
}

async function revokeLocalSessionAndReturnToLogin() {
  try {
    const { error } = await supabase.auth.signOut({ scope: "global" });
    if (error) throw error;
  } catch {
    await supabase.auth.signOut({ scope: "local" }).catch(() => {});
  }
  const deniedUrl = new URL("./login.html", window.location.href);
  deniedUrl.searchParams.set("access", "revoked");
  window.location.replace(deniedUrl.href);
}

function setupHomeAccountMenu(session) {
  const root = document.getElementById("homeAccount");
  const trigger = document.getElementById("homeAccountAction");
  const menu = document.getElementById("homeAccountMenu");
  const themeAction = document.getElementById("homeThemeAction");
  const mfaAction = document.getElementById("mfaSetupAction");
  const logoutAction = document.getElementById("logoutBtn");
  if (!root || !trigger || !menu || !logoutAction) return;

  const closeMenu = () => {
    menu.hidden = true;
    trigger.setAttribute("aria-expanded", "false");
  };
  const openMenu = () => {
    menu.hidden = false;
    trigger.setAttribute("aria-expanded", "true");
  };

  trigger.addEventListener("click", event => {
    event.stopPropagation();
    if (menu.hidden) openMenu();
    else closeMenu();
  });
  document.addEventListener("click", event => {
    if (!root.contains(event.target)) closeMenu();
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && !menu.hidden) {
      closeMenu();
      trigger.focus();
    }
  });

  themeAction?.addEventListener("click", closeMenu);

  if (mfaAction) {
    mfaAction.hidden = !requiresPrivilegedMfa(session);
    if (!mfaAction.hidden) {
      mfaAction.addEventListener("click", () => {
        window.location.assign(authFlowUrl("mfa-setup.html", currentPageNext()));
      });
    }
  }

  logoutAction.addEventListener("click", async () => {
    logoutAction.disabled = true;
    await supabase.auth.signOut();
    window.location.replace("./login.html");
  });
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

    if (!await currentPlatformAccess()) {
      await revokeLocalSessionAndReturnToLogin();
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

    mountNotificationCenter({ supabase, session }).catch(error => {
      console.error("notification_center_failed", error);
    });

    if (isHomePage) {
      setupHomeAccountMenu(session);
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
