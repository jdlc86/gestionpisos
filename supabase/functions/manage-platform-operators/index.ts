import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://jdlc86.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const OPERATIONAL_ROLES = new Set(["root", "admin", "employee", "owner", "tenant"]);
const DEFAULT_APP_BASE_URL = "https://jdlc86.github.io/gestionpisos";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function bearerToken(authorization: string) {
  return authorization.replace(/^Bearer\s+/i, "").trim();
}

function jwtPayload(token: string): Record<string, unknown> | null {
  try {
    const part = token.split(".")[1];
    if (!part) return null;
    const base64 = part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "=");
    return JSON.parse(atob(base64));
  } catch {
    return null;
  }
}

function validUuid(value: unknown) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ""));
}

function cleanText(value: unknown, maxLength: number) {
  return String(value ?? "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanEmail(value: unknown) {
  return String(value ?? "").trim().toLowerCase().slice(0, 254);
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[char] || char));
}

function adminHeaders(serviceKey: string) {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

function appBaseUrl() {
  const configured = String(Deno.env.get("AUTH_APP_BASE_URL") || DEFAULT_APP_BASE_URL).trim();
  const url = new URL(configured);
  if (url.protocol !== "https:") throw new Error("invalid_auth_app_base_url");
  return url.href.replace(/\/$/, "");
}

async function findUserByEmail(admin: ReturnType<typeof createClient>, email: string) {
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const users = Array.isArray(data?.users) ? data.users : [];
    const match = users.find(user => String(user.email || "").trim().toLowerCase() === email);
    if (match) return match;
    if (users.length < 1000) break;
  }
  return null;
}

async function verifiedFactorCount(supabaseUrl: string, serviceKey: string, userId: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}/factors`, {
    headers: adminHeaders(serviceKey),
  });
  if (!response.ok) return null;
  const body = await response.json();
  const factors = Array.isArray(body) ? body : [];
  return factors.filter((factor: Record<string, unknown>) => factor?.status === "verified").length;
}

async function sendOperatorActivationEmail(
  admin: ReturnType<typeof createClient>,
  input: { email: string; displayName: string },
) {
  const resendKey = String(Deno.env.get("RESEND_API_KEY") || "").trim();
  const sender = String(Deno.env.get("AUTH_EMAIL_FROM") || "").trim();
  if (!resendKey || !sender) return { status: "not_configured" as const };

  let actionLink = "";
  try {
    const redirectTo = `${appBaseUrl()}/operator-activate.html?operator=1`;
    const { data, error } = await admin.auth.admin.generateLink({
      type: "recovery",
      email: input.email,
      options: { redirectTo },
    });
    if (error) throw error;
    actionLink = String(data?.properties?.action_link || "");
    if (!actionLink) throw new Error("empty_action_link");
  } catch (error) {
    console.error("platform_operator_activation_link_failed", String((error as Error)?.message || error));
    return { status: "failed" as const };
  }

  const continueUrl = new URL(`${appBaseUrl()}/accept-invitation.html`);
  continueUrl.searchParams.set("continue", actionLink);
  const name = escapeHtml(input.displayName || "operador");
  const html = `<!doctype html><html><body style="font-family:Arial,sans-serif;line-height:1.5;color:#18212b"><div style="max-width:560px;margin:auto;padding:28px"><p style="font-size:12px;letter-spacing:.16em;font-weight:700">ALLAISO · PLATAFORMA</p><h1 style="font-size:24px">Activa tu acceso de operador</h1><p>Hola ${name},</p><p>ROOT te ha designado como operador de emergencia de la plataforma Allaiso.</p><p>Para proteger el acceso, nadie ha definido una contraseña por ti. Confirma que controlas este correo y crea tu propia contraseña desde el botón siguiente.</p><p style="margin:28px 0"><a href="${escapeHtml(continueUrl.href)}" style="display:inline-block;padding:12px 18px;background:#111827;color:white;text-decoration:none;border-radius:8px">Activar acceso de operador</a></p><p>Después deberás registrar MFA antes de poder gestionar recuperaciones.</p><p style="font-size:12px;color:#667085">El enlace es de un solo uso. Allaiso nunca envía contraseñas temporales por correo.</p></div></body></html>`;

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: sender,
        to: [input.email],
        subject: "Activa tu acceso de operador Allaiso",
        html,
      }),
    });
    const responseText = await response.text();
    if (!response.ok) throw new Error(`resend_${response.status}:${responseText.slice(0, 120)}`);
    let providerMessageId: string | null = null;
    try {
      providerMessageId = String(JSON.parse(responseText)?.id || "") || null;
    } catch {
      providerMessageId = null;
    }
    return { status: "sent" as const, provider_message_id: providerMessageId };
  } catch (error) {
    console.error("platform_operator_activation_email_failed", String((error as Error)?.message || error));
    return { status: "failed" as const };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get(["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"));
  const authorization = req.headers.get("Authorization") || "";
  const accessToken = bearerToken(authorization);

  if (!supabaseUrl || !anonKey || !serviceKey || !accessToken) {
    return json(401, { error: "authentication_required" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  const actor = userData?.user;
  if (userError || !actor) return json(401, { error: "invalid_session" });

  const role = String(actor.app_metadata?.role || "").toLowerCase();
  if (role !== "root") return json(403, { error: "root_required" });

  const payload = jwtPayload(accessToken);
  if (String(payload?.aal || "") !== "aal2") return json(403, { error: "aal2_required" });

  let body: {
    action?: string;
    email?: string;
    display_name?: string;
    target_user_id?: string;
    active?: boolean;
    can_recover_root?: boolean;
  } = {};
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const action = cleanText(body.action || "list", 32).toLowerCase();
  const organizationId = validUuid(actor.app_metadata?.organization_id) ? String(actor.app_metadata.organization_id) : null;

  async function mutateOperator(input: {
    mutationAction: "upsert" | "update";
    targetUserId: string;
    displayName: string;
    active: boolean;
    canRecoverRoot: boolean;
    email: string;
  }) {
    const { data, error } = await admin.rpc("manage_platform_operator_service", {
      p_action: input.mutationAction,
      p_target_user_id: input.targetUserId,
      p_display_name: input.displayName,
      p_active: input.active,
      p_can_recover_root: input.canRecoverRoot,
      p_actor_user_id: actor.id,
      p_organization_id: organizationId,
      p_email: input.email,
    });
    if (error) {
      console.error("platform_operator_atomic_mutation_failed", error.message);
      throw new Error("operator_mutation_failed");
    }
    return data as Record<string, unknown>;
  }

  if (action === "list") {
    const { data: rows, error } = await admin
      .from("platform_operators")
      .select("user_id,display_name,active,can_recover_root,identity_email,created_at,updated_at")
      .order("created_at", { ascending: true });
    if (error) return json(500, { error: "operator_list_failed" });

    const operators: Record<string, unknown>[] = [];
    let readyRootRecoveryCount = 0;
    for (const row of rows || []) {
      const { data: targetData } = await admin.auth.admin.getUserById(row.user_id);
      const target = targetData?.user;
      const factorCount = target ? await verifiedFactorCount(supabaseUrl, serviceKey, row.user_id) : null;
      const mfaReady = typeof factorCount === "number" ? factorCount > 0 : null;
      if (row.active === true && row.can_recover_root === true && mfaReady === true) readyRootRecoveryCount += 1;
      const authEmail = String(target?.email || "").trim().toLowerCase();
      const identityEmail = String(row.identity_email || "").trim().toLowerCase();
      operators.push({
        ...row,
        email: authEmail,
        identity_email: identityEmail,
        email_consistent: Boolean(authEmail && identityEmail && authEmail === identityEmail),
        auth_user_exists: Boolean(target),
        invitation_pending: target?.user_metadata?.platform_operator_invitation_pending === true,
        mfa_ready: mfaReady,
        verified_factor_count: factorCount,
      });
    }

    return json(200, {
      ok: true,
      operators,
      active_root_recovery_count: readyRootRecoveryCount,
    });
  }

  if (action === "add") {
    const email = cleanEmail(body.email);
    const displayName = cleanText(body.display_name, 120);
    const canRecoverRoot = body.can_recover_root !== false;
    if (!email || !email.includes("@")) return json(400, { error: "valid_email_required" });
    if (displayName.length < 2) return json(400, { error: "display_name_required" });

    let target;
    let createdNewIdentity = false;
    try {
      target = await findUserByEmail(admin, email);
      if (!target) {
        const { data: created, error: createError } = await admin.auth.admin.createUser({
          email,
          email_confirm: true,
          user_metadata: {
            display_name: displayName,
            platform_operator_invitation_pending: true,
          },
        });
        if (createError || !created?.user) throw createError || new Error("auth_user_create_failed");
        target = created.user;
        createdNewIdentity = true;
      }
    } catch (error) {
      console.error("platform_operator_user_prepare_failed", String((error as Error)?.message || error));
      return json(500, { error: "operator_auth_identity_prepare_failed" });
    }

    if (target.id === actor.id) {
      if (createdNewIdentity) await admin.auth.admin.deleteUser(target.id).catch(() => {});
      return json(403, { error: "self_operator_forbidden" });
    }
    if (!target.email_confirmed_at) {
      if (createdNewIdentity) await admin.auth.admin.deleteUser(target.id).catch(() => {});
      return json(409, { error: "operator_email_not_confirmed" });
    }

    const targetRole = String(target.app_metadata?.role || "").toLowerCase();
    if (OPERATIONAL_ROLES.has(targetRole)) {
      if (createdNewIdentity) await admin.auth.admin.deleteUser(target.id).catch(() => {});
      return json(409, { error: "dedicated_platform_identity_required" });
    }

    let result: Record<string, unknown>;
    try {
      result = await mutateOperator({
        mutationAction: "upsert",
        targetUserId: target.id,
        displayName,
        active: true,
        canRecoverRoot,
        email,
      });
    } catch (error) {
      if (createdNewIdentity) await admin.auth.admin.deleteUser(target.id).catch(() => {});
      return json(500, { error: String((error as Error)?.message || "operator_mutation_failed") });
    }

    const invitationPending = createdNewIdentity || target.user_metadata?.platform_operator_invitation_pending === true;
    const invitation = invitationPending
      ? await sendOperatorActivationEmail(admin, { email, displayName })
      : { status: "not_needed" as const };

    return json(200, {
      ...result,
      operator: {
        user_id: target.id,
        email,
        display_name: displayName,
        active: true,
        can_recover_root: canRecoverRoot,
      },
      created_auth_identity: createdNewIdentity,
      invitation_status: invitation.status,
      invitation_provider_message_id: "provider_message_id" in invitation ? invitation.provider_message_id : null,
    });
  }

  if (action === "update") {
    const targetUserId = String(body.target_user_id || "").trim();
    if (!validUuid(targetUserId)) return json(400, { error: "invalid_target_user_id" });
    if (targetUserId === actor.id) return json(403, { error: "self_operator_forbidden" });

    const { data: existing, error: existingError } = await admin
      .from("platform_operators")
      .select("user_id,display_name,active,can_recover_root")
      .eq("user_id", targetUserId)
      .maybeSingle();
    if (existingError) return json(500, { error: "operator_lookup_failed" });
    if (!existing) return json(404, { error: "operator_not_found" });

    const displayName = body.display_name === undefined ? existing.display_name : cleanText(body.display_name, 120);
    if (String(displayName).trim().length < 2) return json(400, { error: "display_name_required" });
    const active = typeof body.active === "boolean" ? body.active : existing.active;
    const canRecoverRoot = typeof body.can_recover_root === "boolean" ? body.can_recover_root : existing.can_recover_root;
    const { data: targetData } = await admin.auth.admin.getUserById(targetUserId);
    const target = targetData?.user;
    if (!target) return json(404, { error: "auth_user_not_found" });
    const targetRole = String(target.app_metadata?.role || "").toLowerCase();
    if (OPERATIONAL_ROLES.has(targetRole)) {
      return json(409, { error: "dedicated_platform_identity_required" });
    }

    try {
      const result = await mutateOperator({
        mutationAction: "update",
        targetUserId,
        displayName,
        active,
        canRecoverRoot,
        email: String(target.email || ""),
      });
      return json(200, result);
    } catch (error) {
      return json(500, { error: String((error as Error)?.message || "operator_mutation_failed") });
    }
  }

  return json(400, { error: "unsupported_action" });
});
