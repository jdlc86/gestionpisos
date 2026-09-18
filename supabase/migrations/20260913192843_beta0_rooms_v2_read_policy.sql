create policy rooms_v2_read on public.rooms_v2 for select to authenticated using (exists (select 1 from public.properties_v2 p where p.id = property_id));
