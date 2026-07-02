-- =============================================================================
-- Migration 0002: Players (Anonymous Sessions)
-- =============================================================================

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  session_token uuid not null default gen_random_uuid(),
  display_name varchar(40) not null default 'Guest',
  avatar_seed varchar(64),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  is_active boolean not null default true,
  device_fingerprint varchar(128),
  ip_hash varchar(128),
  user_agent text,
  metadata jsonb not null default '{}'::jsonb,

  constraint players_display_name_len check (char_length(display_name) between 1 and 40)
);

comment on table public.players is 'Anonymous, ephemeral player sessions. No auth/login. Identified by session_token.';
comment on column public.players.session_token is 'Opaque bearer token stored client-side (localStorage) to identify the anonymous session across reconnects.';
comment on column public.players.ip_hash is 'Salted hash of client IP, never raw IP, used only for abuse/rate-limit heuristics.';

create unique index if not exists idx_players_session_token on public.players (session_token);
create index if not exists idx_players_last_seen on public.players (last_seen_at desc);
create index if not exists idx_players_active on public.players (is_active) where is_active = true;

-- Auto-update last_seen_at on row touch via trigger defined in 0006 (functions/triggers).
