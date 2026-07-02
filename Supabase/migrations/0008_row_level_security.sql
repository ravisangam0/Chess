-- =============================================================================
-- Migration 0008: Row Level Security
--
-- Design decision: there is no Supabase Auth / login in this product (per spec:
-- "No Login, No Signup"). Anonymous players are identified by an opaque
-- session_token generated server-side and stored client-side.
--
-- Because Postgres RLS has no reliable way to verify a bearer token supplied
-- by an untrusted anon-key client, ALL writes (room create/join, moves,
-- resign, draw requests, timers, stats) MUST go through the backend service
-- layer (src/services/*) using the Supabase service_role key, which bypasses
-- RLS by design. The anon key is restricted to safe, narrow, read-only access
-- needed for Realtime subscriptions and public dashboards.
--
-- This is the standard, secure pattern for "anonymous sessions without auth":
-- treat the anon key as semi-public and never grant it direct write access.
-- =============================================================================

alter table public.players enable row level security;
alter table public.rooms enable row level security;
alter table public.games enable row level security;
alter table public.moves enable row level security;
alter table public.draw_requests enable row level security;
alter table public.timer_events enable row level security;
alter table public.player_statistics enable row level security;
alter table public.daily_analytics enable row level security;
alter table public.theme_usage_analytics enable row level security;
alter table public.app_settings enable row level security;
alter table public.feature_flags enable row level security;
alter table public.system_config enable row level security;
alter table public.maintenance_windows enable row level security;
alter table public.system_logs enable row level security;
alter table public.rate_limit_buckets enable row level security;
alter table public.openings enable row level security;

-- -----------------------------------------------------------------------------
-- anon: read-only, narrow surface for Realtime + public widgets.
-- The frontend reads room/game/move state via Realtime (postgres_changes),
-- which respects RLS, so SELECT must be permitted on rows the client is
-- legitimately subscribed to. We allow SELECT broadly on the low-sensitivity
-- gameplay tables (rooms/games/moves are not secret once you have the code)
-- and lock everything else (settings, logs, config, stats internals) to
-- service_role only.
-- -----------------------------------------------------------------------------

drop policy if exists anon_select_rooms on public.rooms;
create policy anon_select_rooms on public.rooms
  for select to anon, authenticated
  using (true);

drop policy if exists anon_select_games on public.games;
create policy anon_select_games on public.games
  for select to anon, authenticated
  using (true);

drop policy if exists anon_select_moves on public.moves;
create policy anon_select_moves on public.moves
  for select to anon, authenticated
  using (true);

drop policy if exists anon_select_draw_requests on public.draw_requests;
create policy anon_select_draw_requests on public.draw_requests
  for select to anon, authenticated
  using (true);

drop policy if exists anon_select_timer_events on public.timer_events;
create policy anon_select_timer_events on public.timer_events
  for select to anon, authenticated
  using (true);

drop policy if exists anon_select_openings on public.openings;
create policy anon_select_openings on public.openings
  for select to anon, authenticated
  using (true);

drop policy if exists anon_select_leaderboard_stats on public.player_statistics;
create policy anon_select_leaderboard_stats on public.player_statistics
  for select to anon, authenticated
  using (true);

drop policy if exists anon_select_public_settings on public.app_settings;
create policy anon_select_public_settings on public.app_settings
  for select to anon, authenticated
  using (key not like 'internal_%');

drop policy if exists anon_select_feature_flags on public.feature_flags;
create policy anon_select_feature_flags on public.feature_flags
  for select to anon, authenticated
  using (true);

-- players: a session row contains a device fingerprint / ip hash, which is
-- sensitive — do not expose other players' rows broadly. We only expose
-- display_name + id implicitly through joins handled server-side; direct
-- anon SELECT on players is disabled entirely. The frontend gets player
-- display info via the room/game payload assembled by the backend instead.
-- (No policy created => RLS default-deny for anon/authenticated on players.)

-- No anon policies on: daily_analytics, theme_usage_analytics, system_config,
-- maintenance_windows (except an explicit "is there an active maintenance
-- window" read below), system_logs, rate_limit_buckets.

drop policy if exists anon_select_active_maintenance on public.maintenance_windows;
create policy anon_select_active_maintenance on public.maintenance_windows
  for select to anon, authenticated
  using (is_active = true);

-- -----------------------------------------------------------------------------
-- service_role: full access (bypasses RLS by default in Supabase, but we add
-- explicit policies for clarity/portability in case RLS enforcement mode
-- changes, and for any future use of the postgres role directly).
-- -----------------------------------------------------------------------------

drop policy if exists service_role_all_players on public.players;
create policy service_role_all_players on public.players for all to service_role using (true) with check (true);
drop policy if exists service_role_all_rooms on public.rooms;
create policy service_role_all_rooms on public.rooms for all to service_role using (true) with check (true);
drop policy if exists service_role_all_games on public.games;
create policy service_role_all_games on public.games for all to service_role using (true) with check (true);
drop policy if exists service_role_all_moves on public.moves;
create policy service_role_all_moves on public.moves for all to service_role using (true) with check (true);
drop policy if exists service_role_all_draw_requests on public.draw_requests;
create policy service_role_all_draw_requests on public.draw_requests for all to service_role using (true) with check (true);
drop policy if exists service_role_all_timer_events on public.timer_events;
create policy service_role_all_timer_events on public.timer_events for all to service_role using (true) with check (true);
drop policy if exists service_role_all_player_statistics on public.player_statistics;
create policy service_role_all_player_statistics on public.player_statistics for all to service_role using (true) with check (true);
drop policy if exists service_role_all_daily_analytics on public.daily_analytics;
create policy service_role_all_daily_analytics on public.daily_analytics for all to service_role using (true) with check (true);
drop policy if exists service_role_all_theme_usage on public.theme_usage_analytics;
create policy service_role_all_theme_usage on public.theme_usage_analytics for all to service_role using (true) with check (true);
drop policy if exists service_role_all_app_settings on public.app_settings;
create policy service_role_all_app_settings on public.app_settings for all to service_role using (true) with check (true);
drop policy if exists service_role_all_feature_flags on public.feature_flags;
create policy service_role_all_feature_flags on public.feature_flags for all to service_role using (true) with check (true);
drop policy if exists service_role_all_system_config on public.system_config;
create policy service_role_all_system_config on public.system_config for all to service_role using (true) with check (true);
drop policy if exists service_role_all_maintenance on public.maintenance_windows;
create policy service_role_all_maintenance on public.maintenance_windows for all to service_role using (true) with check (true);
drop policy if exists service_role_all_logs on public.system_logs;
create policy service_role_all_logs on public.system_logs for all to service_role using (true) with check (true);
drop policy if exists service_role_all_rate_limit on public.rate_limit_buckets;
create policy service_role_all_rate_limit on public.rate_limit_buckets for all to service_role using (true) with check (true);
drop policy if exists service_role_all_openings on public.openings;
create policy service_role_all_openings on public.openings for all to service_role using (true) with check (true);
