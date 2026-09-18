delete from public.access_requests;
delete from public.admin_capability_requests;
delete from public.admin_capability_holders;
delete from public.internal_staff_onboarding_access_snapshot;
delete from public.internal_staff_onboarding;
delete from public.external_account_onboarding;
delete from public.property_qr_tokens;
delete from public.property_staff_access_v3;
delete from public.property_staff_access_v2;
delete from public.property_staff_assignments;

delete from public.tenant_task_actions_v2;
delete from public.tenant_task_history_v2;
delete from public.tenant_tasks_v2;
delete from public.tenant_privacy_events_v2;
delete from public.tenant_documents_v2;

delete from public.cleaning_audit_items_v2;
delete from public.cleaning_audits_v2;
delete from public.cleaning_photo_requests_v2;
delete from public.cleaning_debts_v2;
delete from public.cleaning_swap_requests_v2;
delete from public.photo_verification_items_v2;
delete from public.random_photo_requests_v2;
delete from public.photo_verification_runs_v2;
delete from public.cleaning_tasks_v2;
delete from public.cleaning_plans_v2;
delete from public.photo_patterns_v2;
delete from public.incident_evidence_v2;
delete from public.incident_updates_v2;
delete from public.incidents_v2;
delete from public.claims_v2;
delete from public.payment_obligations_v2;
delete from public.notifications_v2;
delete from public.broadcasts_v2;
delete from public.reminder_rules_v2;
delete from public.verification_policies_v2;
delete from public.cleaning_audit_policies_v2;
delete from public.cleaning_photo_request_policies_v2;

delete from public.occupancies_v2;
delete from public.tenancies;
delete from public.rooms;
delete from public.rooms_v2;
delete from public.properties;
delete from public.properties_v2;
delete from public.owners;
delete from public.tenants_v2;

delete from public.audit_log_v2;

delete from public.user_roles
where user_id not in (
  select id from auth.users where lower(coalesce(raw_app_meta_data->>'role','')) = 'root'
);

delete from public.profiles
where user_id not in (
  select id from auth.users where lower(coalesce(raw_app_meta_data->>'role','')) = 'root'
);
