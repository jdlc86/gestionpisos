const SUPABASE_MODULE_SOURCES = [
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.57.4/+esm",
  "https://esm.sh/@supabase/supabase-js@2.57.4"
];

let createClient = null;
let moduleLoadError = null;

for (const source of SUPABASE_MODULE_SOURCES) {
  try {
    const module = await import(source);
    if (typeof module.createClient === "function") {
      createClient = module.createClient;
      break;
    }
  } catch (error) {
    moduleLoadError = error;
  }
}

if (!createClient) {
  console.error("supabase_client_module_load_failed", moduleLoadError);
  throw moduleLoadError || new Error("supabase_client_module_unavailable");
}

const SUPABASE_URL = "https://qsxtmmkftsohkqqmytbb.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_InXekvnoNNlI1BX_pRWUBw_UMGnzgxR";

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});

export async function getCurrentSession() {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  return data.session;
}

export async function getCurrentUser() {
  const { data, error } = await supabase.auth.getUser();
  if (error) throw error;
  return data.user;
}
