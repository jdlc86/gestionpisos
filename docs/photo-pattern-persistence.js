import { supabase, getCurrentUser } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);

if (params.get("mode") === "pattern") {
  const message = document.getElementById("cameraMessage");
  const guide = document.getElementById("cameraGuide");
  const hint = document.getElementById("alignmentHint");
  const title = document.querySelector("h1");
  const heroTitle = document.querySelector(".hero h2");
  const heroText = document.querySelector(".hero p");

  if (guide) {
    guide.hidden = true;
    guide.style.display = "none";
  }
  if (hint) hint.textContent = "Captura la vista que se usará como referencia";
  if (title) title.textContent = "Registrar patrón";
  if (heroTitle) heroTitle.textContent = "Captura la referencia de esta zona.";
  if (heroText) heroText.textContent = "Esta fotografía define el encuadre de referencia. Después podrás dibujar manualmente una o varias siluetas sobre ella.";

  const uuidLike = value => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");

  window.addEventListener("allaiso:photo-captured", event => {
    const detail = event.detail;
    if (!detail?.blob) return;

    queueMicrotask(async () => {
      const propertyId = params.get("property_id");
      const zoneLabel = (params.get("zone_label") || "").trim();

      if (!uuidLike(propertyId) || !zoneLabel || zoneLabel.length > 120) {
        message.textContent = "Contexto de patrón inválido.";
        return;
      }

      try {
        message.textContent = "Guardando referencia privada…";

        const user = await getCurrentUser();
        if (!["root", "admin"].includes(user?.app_metadata?.role)) throw new Error("not_allowed");

        const { data: property, error: propertyError } = await supabase
          .from("properties_v2")
          .select("id,organization_id,status")
          .eq("id", propertyId)
          .maybeSingle();

        if (propertyError) throw propertyError;
        if (!property || property.status === "archived") throw new Error("property_not_available");

        const patternId = crypto.randomUUID();
        const storagePath = `${property.organization_id}/patterns/${patternId}/reference.jpg`;

        const { error: insertError } = await supabase
          .from("photo_patterns_v2")
          .insert({
            id: patternId,
            organization_id: property.organization_id,
            property_id: property.id,
            name: zoneLabel,
            target_type: "zone",
            target_key: zoneLabel,
            reference_storage_path: storagePath,
            active: false,
            created_by: user.id
          });

        if (insertError) throw insertError;

        const { error: uploadError } = await supabase.storage
          .from("photo-verification")
          .upload(storagePath, detail.blob, {
            contentType: "image/jpeg",
            cacheControl: "3600",
            upsert: false
          });

        if (uploadError) throw uploadError;

        const { error: activateError } = await supabase
          .from("photo_patterns_v2")
          .update({ active: true })
          .eq("id", patternId);

        if (activateError) throw activateError;

        message.textContent = "Patrón de referencia guardado correctamente.";

        const link = document.createElement("a");
        link.className = "ghost";
        link.textContent = "Dibujar silueta";
        link.href = `./photo-pattern-editor.html?v=2026091405&pattern_id=${patternId}`;
        message.after(link);
      } catch (error) {
        console.error("pattern persistence failed", error);
        message.textContent = "No se pudo activar el patrón. La referencia no se usará en verificaciones.";
      }
    });
  });
}
