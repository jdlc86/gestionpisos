const PRIVILEGED_ROLES = new Set(["root", "admin"]);
const AUTH_PAGES = new Set([
  "login.html",
  "reset-password.html",
  "activate-account.html",
  "activate-external-account.html",
  "accept-invitation.html",
  "mfa-setup.html",
  "mfa-challenge.html"
]);

export function sessionRole(session) {
  return String(session?.user?.app_metadata?.role || "").toLowerCase();
}

export function requiresPrivilegedMfa(session) {
  return PRIVILEGED_ROLES.has(sessionRole(session));
}

export function sanitizeNext(raw, fallback = "index.html") {
  const value = String(raw || "").trim().replace(/^\.\//, "").replace(/^\//, "");
  if (!value || value.includes("://") || value.startsWith("//") || value.includes("..")) return fallback;
  const [pathname] = value.split(/[?#]/, 1);
  if (!pathname || pathname.includes("/") || AUTH_PAGES.has(pathname)) return fallback;
  return pathname;
}

export function requestedNext(fallback = "index.html") {
  const params = new URLSearchParams(window.location.search);
  return sanitizeNext(params.get("next"), fallback);
}

export function currentPageNext(fallback = "index.html") {
  const filename = window.location.pathname.split("/").pop() || fallback;
  return sanitizeNext(filename, fallback);
}

export function protectedTarget(next = requestedNext()) {
  return new URL(`./${sanitizeNext(next)}`, window.location.href).href;
}

export function authFlowUrl(page, next = requestedNext()) {
  const url = new URL(`./${page}`, window.location.href);
  url.searchParams.set("next", sanitizeNext(next));
  return url.href;
}

export async function getMfaAssurance(supabase) {
  const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (error) throw error;
  return data;
}

export async function privilegedMfaRoute(supabase, session, { requireEnrollment = false } = {}) {
  if (!requiresPrivilegedMfa(session)) return { route: null, enrolled: false, assurance: null };

  const assurance = await getMfaAssurance(supabase);
  if (assurance?.currentLevel === "aal2") {
    return { route: null, enrolled: true, assurance };
  }

  if (assurance?.nextLevel === "aal2") {
    return { route: "mfa-challenge.html", enrolled: true, assurance };
  }

  return {
    route: requireEnrollment ? "mfa-setup.html" : null,
    enrolled: false,
    assurance
  };
}
