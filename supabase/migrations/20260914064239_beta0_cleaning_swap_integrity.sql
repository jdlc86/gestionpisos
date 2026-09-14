alter table public.cleaning_swap_requests_v2
  add column if not exists decided_by uuid references auth.users(id);

alter table public.cleaning_debts_v2
  add column if not exists swap_request_id uuid references public.cleaning_swap_requests_v2(id);

create unique index if not exists cleaning_one_pending_swap_per_task
  on public.cleaning_swap_requests_v2(cleaning_task_id)
  where status = 'pending';

create unique index if not exists cleaning_one_debt_per_swap
  on public.cleaning_debts_v2(swap_request_id)
  where swap_request_id is not null;

create index if not exists cleaning_swap_requester_status_idx
  on public.cleaning_swap_requests_v2(requester_user_id,status);

create index if not exists cleaning_swap_target_status_idx
  on public.cleaning_swap_requests_v2(target_user_id,status);

create policy cleaning_debts_participant_read
on public.cleaning_debts_v2
for select to authenticated
using (
  debtor_user_id = (select auth.uid())
  or creditor_user_id = (select auth.uid())
  or ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);
