
create or replace function public.prevent_root_role_mutation()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if (tg_op = 'DELETE' and old.role = 'root')
     or (tg_op = 'UPDATE' and old.role = 'root'
         and (new.role is distinct from old.role
              or new.user_id is distinct from old.user_id
              or new.revoked_at is distinct from old.revoked_at)) then
    raise exception 'ROOT role is immutable';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger trg_protect_root_role
before update or delete on public.user_roles
for each row execute function public.prevent_root_role_mutation();
