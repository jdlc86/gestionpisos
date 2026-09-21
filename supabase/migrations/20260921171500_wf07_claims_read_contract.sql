-- GestionPisos · WF-07 · preservar lectura de claims bajo RLS
-- Las escrituras directas permanecen revocadas; SELECT sigue disponible para
-- los actores autorizados y las policies/RLS deciden las filas visibles.

revoke all on public.claims_v2 from anon;

revoke insert,update,delete,truncate,references,trigger
  on public.claims_v2 from authenticated;
grant select on public.claims_v2 to authenticated;

comment on table public.claims_v2 is
  'Expedientes de reclamación. Lectura authenticated bajo RLS; mutaciones sensibles solo server-side.';
