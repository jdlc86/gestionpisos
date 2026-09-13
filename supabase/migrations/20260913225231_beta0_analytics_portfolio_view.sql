create or replace view public.v_portfolio_stats
with (security_invoker = true)
as
select
  p.id as property_id,
  p.organization_id,
  p.owner_id,
  coalesce(o.total_rooms,0) as total_rooms,
  coalesce(o.occupied_rooms,0) as occupied_rooms,
  greatest(coalesce(o.total_rooms,0)-coalesce(o.occupied_rooms,0),0) as vacant_rooms,
  coalesce(i.open_incidents,0) as open_incidents,
  coalesce(i.urgent_open_incidents,0) as urgent_open_incidents,
  coalesce(i.resolved_incidents,0) as resolved_incidents,
  coalesce(c.pending_cleaning,0) as pending_cleaning,
  coalesce(c.awaiting_review,0) as awaiting_review,
  coalesce(c.approved_cleaning,0) as approved_cleaning,
  coalesce(c.failed_cleaning,0) as failed_cleaning
from public.properties_v2 p
left join public.v_property_occupancy_stats o on o.property_id = p.id
left join public.v_property_incident_stats i on i.property_id = p.id
left join public.v_property_cleaning_stats c on c.property_id = p.id;