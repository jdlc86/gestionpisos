import { createClient } from "npm:@supabase/supabase-js@2";

type AdminClient = ReturnType<typeof createClient>;

type RevocationResult = {
  ok?: boolean;
  status?: string;
  already_revoked?: boolean;
  subject_type?: string;
  subject_id?: string;
  old_email?: string;
  replacement_email?: string;
};

export async function disableAndRevokeExternalOnboarding(
  admin: AdminClient,
  input: {
    authUserId: string;
    actorUserId: string;
    replacementEmail: string | null;
  },
): Promise<RevocationResult> {
  const replacementEmail = input.replacementEmail == null ? null : String(input.replacementEmail).trim().toLowerCase() || null;
  if (!input.authUserId || !input.actorUserId) {
    throw new Error("external_onboarding_revoke_input_invalid");
  }

  const { data: userData, error: lookupError } = await admin.auth.admin.getUserById(input.authUserId);
  if (lookupError || !userData?.user) {
    throw new Error("external_auth_identity_lookup_failed");
  }

  const deletedAt = String((userData.user as { deleted_at?: string | null }).deleted_at || "");
  if (!deletedAt) {
    const { error: deleteError } = await admin.auth.admin.deleteUser(input.authUserId, true);
    if (deleteError) {
      throw new Error("external_auth_identity_disable_failed");
    }
  }

  const { data, error } = await admin.rpc("revoke_external_account_onboarding_v1", {
    p_auth_user_id: input.authUserId,
    p_actor_user_id: input.actorUserId,
    p_reason: "email_changed",
    p_replacement_email: replacementEmail,
  });
  if (error) {
    throw new Error(String(error.message || "external_onboarding_revoke_failed"));
  }
  if (!data?.ok || data?.status !== "revoked") {
    throw new Error("external_onboarding_revoke_incomplete");
  }
  return data as RevocationResult;
}
