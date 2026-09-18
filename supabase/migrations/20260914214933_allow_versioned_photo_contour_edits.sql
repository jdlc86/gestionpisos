create or replace function private.enforce_photo_pattern_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Published pattern identity and reference image remain immutable.
  if new.organization_id is distinct from old.organization_id
     or new.property_id is distinct from old.property_id
     or new.name is distinct from old.name
     or new.target_type is distinct from old.target_type
     or new.target_key is distinct from old.target_key
     or new.reference_storage_path is distinct from old.reference_storage_path
     or new.silhouette_storage_path is distinct from old.silhouette_storage_path
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'published photo pattern identity/reference is immutable';
  end if;

  -- Manual contour authoring is versioned. A contour change must increment
  -- version by exactly one; version cannot change on its own.
  if new.contour_data is distinct from old.contour_data then
    if new.version is distinct from old.version + 1 then
      raise exception 'photo pattern contour changes must increment version by exactly one';
    end if;
  elsif new.version is distinct from old.version then
    raise exception 'photo pattern version may change only with contour_data';
  end if;

  return new;
end;
$function$;
