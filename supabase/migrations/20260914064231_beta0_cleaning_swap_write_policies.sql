
create policy cleaning_swaps_requester_insert
on public.cleaning_swap_requests_v2
for insert to authenticated
with check (
  requester_user_id = (select auth.uid())
  and status = 'pending'
);

create policy cleaning_swaps_participant_update
on public.cleaning_swap_requests_v2
for update to authenticated
using (
  status = 'pending'
  and (
    requester_user_id = (select auth.uid())
    or target_user_id = (select auth.uid())
  )
)
with check (
  requester_user_id = (select auth.uid())
  or target_user_id = (select auth.uid())
);
