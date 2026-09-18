create policy staff_v2_employee_read on public.property_staff_access_v2 for select to authenticated using (employee_user_id = (select auth.uid()));
