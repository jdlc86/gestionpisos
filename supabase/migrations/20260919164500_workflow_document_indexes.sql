-- GestionPisos · hardening índices evidencia documental de workflows
-- Cubre las FK señaladas por Supabase advisors tras desplegar Documento.

create index if not exists workflow_execution_documents_v2_organization_idx
  on public.workflow_execution_documents_v2(organization_id);

create index if not exists workflow_execution_documents_v2_uploaded_by_idx
  on public.workflow_execution_documents_v2(uploaded_by);

comment on index public.workflow_execution_documents_v2_organization_idx is
  'Índice de cobertura para FK/lecturas por organización de evidencia documental workflow.';
comment on index public.workflow_execution_documents_v2_uploaded_by_idx is
  'Índice de cobertura para FK/lecturas por usuario que adjunta evidencia documental workflow.';
