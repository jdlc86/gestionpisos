# Login auth deadlock fix

## Incident

A newly activated external owner could not use the login form: pressing Entrar produced no visible reaction.

## Root cause

The frontend was pinned to `@supabase/supabase-js@2.57.4`. Supabase removed the browser `navigator.locks` auth mutex in `supabase-js` 2.107.0 after production deadlock reports. In the affected login code, `getCurrentSession()` also ran with top-level `await` before the submit handler was registered, so a stalled auth initialization left the form intentionally fail-closed but inert.

## Remediation

- Upgrade the browser SDK to `@supabase/supabase-js@2.116.0`.
- Register login and recovery handlers before any existing-session probe.
- Make the existing-session probe best-effort and bounded to 4 seconds.
- Bound password login and recovery calls to 12 seconds and show an explicit error instead of hanging.
- Preserve the fail-closed native-form protection and existing PWA module self-heal.

## Safety

No schema, RLS, role, Edge Function, organization membership, or live business data is changed by this fix.
