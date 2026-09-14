create policy cleaning_swaps_participant_read
on public.cleaning_swap_requests_v2
for select to authenticated
using (
  requester_user_id = (select auth.uid())
  or target_user_id = (select auth.uid())
);
