-- GestionPisos · WF-07 · ampliar contrato persistido de tipos de flujo
-- Corrige de forma aditiva el CHECK legacy de workflow_definitions_v2.
-- Las migraciones WF-06 ya aplicadas no se reescriben.

alter table public.workflow_definitions_v2
  drop constraint if exists workflow_definitions_v2_flow_type_check;

alter table public.workflow_definitions_v2
  add constraint workflow_definitions_v2_flow_type_check
  check (
    flow_type in (
      'cleaning',
      'inspection',
      'maintenance',
      'checkin',
      'checkout',
      'custom',
      'rent_payment',
      'rent_claim',
      'deposit_receipt',
      'deposit_review',
      'damage_claim'
    )
  );

comment on constraint workflow_definitions_v2_flow_type_check
  on public.workflow_definitions_v2 is
  'Tipos de flujo soportados por el motor transversal hasta WF-07.';
