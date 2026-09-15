-- Central lifecycle guard for photo patterns.
-- Draft patterns may be deleted. Referenced patterns are immutable/retirable.

create or replace function private.photo_pattern_usage_v2(p_pattern_id uuid)
returns jsonb
language sql
security definer
set search_path=public,private,pg_temp
as $$
with u as (
  select 'cleaning'::text kind, r.cleaning_task_id ref_id, t.status ref_status, t.task_date::text ref_label
  from public.cleaning_photo_requests_v2 r
  join public.cleaning_tasks_v2 t on t.id=r.cleaning_task_id
  where r.pattern_id=p_pattern_id
  union all
  select 'verification', i.run_id, coalesce(v.status,'unknown'), coalesce(v.started_at::date::text,'')
  from public.photo_verification_items_v2 i
  join public.photo_verification_runs_v2 v on v.id=i.run_id
  where i.pattern_id=p_pattern_id
  union all
  select 'random_request', r.id, coalesce(r.status,'unknown'), coalesce(r.requested_at::date::text,'')
  from public.random_photo_requests_v2 r where r.pattern_id=p_pattern_id
)
select jsonb_build_object(
 'used',exists(select 1 from u),
 'active_use',exists(select 1 from u where
   (kind='cleaning' and ref_status in ('pending','accepted','in_progress','submitted'))
   or (kind='verification' and ref_status in ('capturing','submitted','pending'))
   or (kind='random_request' and ref_status not in ('completed','cancelled','expired'))),
 'uses',coalesce((select jsonb_agg(jsonb_build_object('kind',kind,'id',ref_id,'status',ref_status,'label',ref_label)) from u),'[]'::jsonb)
);
$$;
revoke all on function private.photo_pattern_usage_v2(uuid) from public,anon,authenticated;

create or replace function private.delete_or_retire_photo_pattern_v2(p_pattern_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare v_usage jsonb;
begin
  if not exists(select 1 from public.photo_patterns_v2 where id=p_pattern_id) then
    raise exception 'pattern_not_found' using errcode='P0002';
  end if;
  v_usage:=private.photo_pattern_usage_v2(p_pattern_id);
  if coalesce((v_usage->>'active_use')::boolean,false) then
    return jsonb_build_object('ok',false,'action','blocked','reason','active_use','usage',v_usage);
  end if;
  if coalesce((v_usage->>'used')::boolean,false) then
    update public.photo_patterns_v2 set active=false,retired_at=coalesce(retired_at,now()) where id=p_pattern_id;
    return jsonb_build_object('ok',true,'action','retired','usage',v_usage);
  end if;
  delete from public.photo_patterns_v2 where id=p_pattern_id;
  return jsonb_build_object('ok',true,'action','deleted','usage',v_usage);
end;
$$;
revoke all on function private.delete_or_retire_photo_pattern_v2(uuid) from public,anon,authenticated;

create or replace function private.enforce_referenced_photo_pattern_immutable_v2()
returns trigger language plpgsql set search_path=public,private,pg_temp as $$
declare v_usage jsonb;
begin
  if new.name is distinct from old.name
     or new.target_type is distinct from old.target_type
     or new.target_key is distinct from old.target_key
     or new.reference_storage_path is distinct from old.reference_storage_path
     or new.silhouette_storage_path is distinct from old.silhouette_storage_path
     or new.contour_data is distinct from old.contour_data then
    v_usage:=private.photo_pattern_usage_v2(old.id);
    if coalesce((v_usage->>'used')::boolean,false) then
      raise exception 'referenced_pattern_is_immutable' using errcode='55000';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_referenced_photo_pattern_immutable_v2 on public.photo_patterns_v2;
create trigger trg_referenced_photo_pattern_immutable_v2
before update on public.photo_patterns_v2
for each row execute function private.enforce_referenced_photo_pattern_immutable_v2();

comment on function private.delete_or_retire_photo_pattern_v2(uuid) is
'Deletes unused drafts; blocks active references; retires historically referenced patterns.';
