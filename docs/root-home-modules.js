import { getCurrentSession } from "./supabase-client.js";

async function revealRootModules() {
  try {
    const session = await getCurrentSession();
    const isRoot = String(session?.user?.app_metadata?.role || "").toLowerCase() === "root";
    const card = document.getElementById("configurationResourcesCard");
    if (card) card.hidden = !isRoot;
  } catch {
    const card = document.getElementById("configurationResourcesCard");
    if (card) card.hidden = true;
  }
}

revealRootModules();
