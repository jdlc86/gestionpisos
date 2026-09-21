-- GestionPisos · WF-07 · deuda de contrato descubierta al ejecutar WF-06 completo
-- WF-06 modela una obligación de alquiler y, al escalar, una segunda ejecución
-- rent_claim referencia esa misma obligación. El índice WF-06 original hacía
-- payment_obligation_id globalmente único y bloqueaba esa transición.
--
-- Conservamos la unicidad que sí importa: una obligación solo puede pertenecer
-- a una ejecución rent_payment. La reclamación mantiene su propia unicidad por
-- claims_v2(obligation_id) y workflow_executions_v2(rent_claim_id).

drop index if exists public.workflow_executions_v2_payment_obligation_uq;

create unique index workflow_executions_v2_payment_obligation_uq
  on public.workflow_executions_v2(payment_obligation_id)
  where payment_obligation_id is not null
    and spec_snapshot->>'flowType'='rent_payment';

comment on index public.workflow_executions_v2_payment_obligation_uq is
  'WF-06/WF-07: una ejecución rent_payment por obligación; rent_claim puede referenciar la misma obligación mediante su expediente único.';
