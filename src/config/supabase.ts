import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { env } from './env.js';

/**
 * Deliberately untyped (no `Database` generic) client. The installed
 * @supabase/supabase-js (2.110.x) generic type machinery for Database
 * schemas is fragile with hand-authored types outside the official CLI
 * codegen output, and fighting it buys no runtime safety. Instead, every
 * repository function casts its response to the matching Row interface
 * from `types/database.types.ts` (e.g. `data as PlayerRow`), which is
 * where correctness actually matters — the request/response shape is
 * verified against the real migrations, not inferred through generics.
 *
 * If you later run `supabase gen types typescript --linked` and want full
 * client-level type inference, swap `SupabaseClient` below for
 * `SupabaseClient<Database>` using the generated types file.
 */

/**
 * Service-role client: full DB access, bypasses RLS.
 * MUST only ever be used server-side (this backend). Never expose this key.
 * All write operations (room create/join, moves, resign, draw, stats) go
 * through this client from within the service layer.
 */
export const supabaseAdmin: SupabaseClient = createClient(
  env.SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: 'public' },
    global: { headers: { 'x-application-name': 'chess-backend-service' } },
  },
);

/**
 * Anon client: used only to mint Realtime channel subscriptions / construct
 * URLs for the frontend, or for read-only diagnostics from the backend
 * itself. Respects RLS (read-only on gameplay tables per migration 0008).
 */
export const supabaseAnon: SupabaseClient = createClient(
  env.SUPABASE_URL,
  env.SUPABASE_ANON_KEY,
  {
    auth: { persistSession: false, autoRefreshToken: false },
  },
);
