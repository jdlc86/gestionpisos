
create or replace view public.v_property_incident_stats
with (security_invoker = true)
as
select
  property_id,
  count(*) filter (where status not in ('resolved','closed','rejected')) as open_incidents,
  count(*) filter (where priority = 'urgent' and status not in ('resolved','closed','rejected')) as urgent_open_incidents,
  count(*) filter (where status in ('resolved','closed')) as resolved_incidents
from public.incidents_v2
group by property_id;

create or replace view public.v_property_cleaning_stats
with (security_invoker = true)
as
select
  property_id,
  count(*) filter (where status in ('pending','accepted','in_progress')) as pending_cleaning,
  count(*) filter (where status = 'submitted') as awaiting_review,
  count(*) filter (where status = 'approved') as approved_cleaning,
  count(*) filter (where status in ('rejected','missed')) as failed_cleaning
from public.cleaning_tasks_v2
group by property_id;

create or replace view public.v_property_occupancy_stats
with (security_invoker = true)
as
select
  p.id as property_id,
  count(distinct r.id) as total_rooms,
  count(distinct o.room_id) filter (
    where o.status = 'active'
      and o.starts_on <= current_date
      and (o.ends_on is null or o.ends_on >= current_date)
  ) as occupied_rooms
from public.properties_v2 p
left join public.rooms_v2 r on r.property_id = p.id and r.archived_at is null
left join public.occupancies_v2 o on o.property_id = p.id
group by p.id;
