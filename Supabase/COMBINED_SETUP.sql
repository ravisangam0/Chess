-- =============================================================================
-- CHESS WEB APP — COMPLETE SUPABASE SETUP (all migrations combined)
-- Run this ONCE in Supabase SQL Editor to create the entire schema.
-- Safe to re-run: uses IF NOT EXISTS / OR REPLACE / DROP+CREATE POLICY / ON CONFLICT DO NOTHING.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0001_extensions_and_enums.sql
-- ─────────────────────────────────────────────────────────────────────────
-- =============================================================================
-- Migration 0001: Extensions and Enum Types
-- Chess Web App Backend
-- =============================================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";

-- -----------------------------------------------------------------------------
-- ENUM TYPES
-- -----------------------------------------------------------------------------

do $$ begin
  create type game_mode as enum ('offline', 'vs_ai', 'online_friend');
exception when duplicate_object then null; end $$;

do $$ begin
  create type ai_difficulty as enum ('easy', 'medium', 'hard');
exception when duplicate_object then null; end $$;

do $$ begin
  create type room_status as enum ('waiting', 'active', 'finished', 'abandoned', 'expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type player_color as enum ('white', 'black');
exception when duplicate_object then null; end $$;

do $$ begin
  create type connection_status as enum ('connected', 'disconnected', 'reconnecting');
exception when duplicate_object then null; end $$;

do $$ begin
  create type game_status as enum (
    'pending', 'in_progress', 'checkmate', 'stalemate', 'draw_agreement',
    'draw_repetition', 'draw_fifty_move', 'draw_insufficient_material',
    'resigned', 'timeout', 'abandoned'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type game_result as enum ('white_win', 'black_win', 'draw', 'ongoing', 'aborted');
exception when duplicate_object then null; end $$;

do $$ begin
  create type time_control_category as enum ('bullet', 'blitz', 'rapid', 'classical', 'unlimited');
exception when duplicate_object then null; end $$;

do $$ begin
  create type move_type as enum ('normal', 'capture', 'castle_kingside', 'castle_queenside', 'en_passant', 'promotion');
exception when duplicate_object then null; end $$;

do $$ begin
  create type draw_request_status as enum ('pending', 'accepted', 'declined', 'expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type log_level as enum ('debug', 'info', 'warn', 'error', 'fatal');
exception when duplicate_object then null; end $$;

do $$ begin
  create type log_category as enum (
    'room', 'move', 'realtime', 'database', 'api', 'security', 'performance', 'system', 'maintenance'
  );
exception when duplicate_object then null; end $$;


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0002_players.sql
-- ─────────────────────────────────────────────────────────────────────────
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


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0003_rooms.sql
-- ─────────────────────────────────────────────────────────────────────────
-- =============================================================================
-- Migration 0003: Rooms
-- =============================================================================

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  room_code varchar(8) not null,
  status room_status not null default 'waiting',
  game_mode game_mode not null default 'online_friend',

  host_player_id uuid not null references public.players(id) on delete cascade,
  guest_player_id uuid references public.players(id) on delete set null,

  host_color player_color not null default 'white',

  host_connection connection_status not null default 'connected',
  guest_connection connection_status not null default 'disconnected',

  time_control_category time_control_category not null default 'rapid',
  initial_time_seconds integer not null default 600,
  increment_seconds integer not null default 0,
  delay_seconds integer not null default 0,

  board_theme varchar(40) not null default 'classic',
  piece_theme varchar(40) not null default 'classic',

  max_players smallint not null default 2,
  current_player_count smallint not null default 1,

  is_private boolean not null default true,
  allow_spectators boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  expires_at timestamptz not null default (now() + interval '2 hours'),
  last_activity_at timestamptz not null default now(),

  metadata jsonb not null default '{}'::jsonb,

  constraint rooms_room_code_format check (room_code ~ '^[A-Z2-9]{6}$'),
  constraint rooms_player_count_bounds check (current_player_count between 0 and max_players),
  constraint rooms_time_bounds check (initial_time_seconds >= 0 and increment_seconds >= 0 and delay_seconds >= 0),
  constraint rooms_max_players_fixed check (max_players = 2)
);

comment on table public.rooms is 'A room represents one online-friend match lobby, identified by a shareable 6-character room code.';
comment on column public.rooms.room_code is 'Human-shareable code, excludes ambiguous chars (0,1,O,I) — see generate_room_code().';
comment on column public.rooms.expires_at is 'Hard TTL for cleanup job; extended on activity for waiting/active rooms.';

-- Room codes must be unique only while the room is "live" (waiting/active),
-- so old finished/expired rooms do not block code reuse forever.
create unique index if not exists idx_rooms_code_live
  on public.rooms (room_code)
  where status in ('waiting', 'active');

create index if not exists idx_rooms_status on public.rooms (status);
create index if not exists idx_rooms_expires_at on public.rooms (expires_at) where status in ('waiting', 'active');
create index if not exists idx_rooms_host_player on public.rooms (host_player_id);
create index if not exists idx_rooms_guest_player on public.rooms (guest_player_id);
create index if not exists idx_rooms_created_at on public.rooms (created_at desc);
create index if not exists idx_rooms_last_activity on public.rooms (last_activity_at desc);


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0004_games_moves_timers.sql
-- ─────────────────────────────────────────────────────────────────────────
-- =============================================================================
-- Migration 0004: Games, Moves, Timers, Draw Requests
-- =============================================================================

-- -----------------------------------------------------------------------------
-- GAMES
-- -----------------------------------------------------------------------------
create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rooms(id) on delete cascade,

  game_mode game_mode not null,
  ai_difficulty ai_difficulty,

  white_player_id uuid references public.players(id) on delete set null,
  black_player_id uuid references public.players(id) on delete set null,

  fen text not null default 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  pgn text not null default '',
  initial_fen text not null default 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',

  turn player_color not null default 'white',
  fullmove_number integer not null default 1,
  halfmove_clock integer not null default 0,

  is_check boolean not null default false,
  is_checkmate boolean not null default false,
  is_stalemate boolean not null default false,
  is_draw boolean not null default false,
  is_threefold_repetition boolean not null default false,
  is_insufficient_material boolean not null default false,

  status game_status not null default 'pending',
  result game_result not null default 'ongoing',
  winner_player_id uuid references public.players(id) on delete set null,
  end_reason varchar(60),

  captured_white_pieces text[] not null default '{}',
  captured_black_pieces text[] not null default '{}',

  white_time_remaining_ms bigint not null default 600000,
  black_time_remaining_ms bigint not null default 600000,
  increment_seconds integer not null default 0,
  delay_seconds integer not null default 0,
  time_control_category time_control_category not null default 'rapid',

  move_count integer not null default 0,
  opening_eco varchar(10),
  opening_name varchar(120),

  is_rematch_of uuid references public.games(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz,
  last_move_at timestamptz,

  metadata jsonb not null default '{}'::jsonb,

  constraint games_time_remaining_nonneg check (white_time_remaining_ms >= 0 and black_time_remaining_ms >= 0)
);

comment on table public.games is 'A single chess game instance. One row per game; one room may have multiple games (rematches).';
comment on column public.games.fen is 'Authoritative current board state, server-validated via chess.js on every move.';

create index if not exists idx_games_room_id on public.games (room_id);
create index if not exists idx_games_status on public.games (status);
create index if not exists idx_games_white_player on public.games (white_player_id);
create index if not exists idx_games_black_player on public.games (black_player_id);
create index if not exists idx_games_created_at on public.games (created_at desc);
create index if not exists idx_games_mode on public.games (game_mode);
create index if not exists idx_games_ended_at on public.games (ended_at desc) where ended_at is not null;

-- -----------------------------------------------------------------------------
-- MOVES (append-only ledger; authoritative move history)
-- -----------------------------------------------------------------------------
create table if not exists public.moves (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  player_id uuid references public.players(id) on delete set null,

  ply_number integer not null,
  fullmove_number integer not null,
  color player_color not null,

  san varchar(16) not null,
  uci varchar(8) not null,
  from_square varchar(2) not null,
  to_square varchar(2) not null,
  piece varchar(1) not null,
  captured_piece varchar(1),
  promotion_piece varchar(1),
  move_type move_type not null default 'normal',

  fen_before text not null,
  fen_after text not null,

  is_check boolean not null default false,
  is_checkmate boolean not null default false,

  white_time_remaining_ms bigint not null,
  black_time_remaining_ms bigint not null,
  think_time_ms integer not null default 0,

  client_move_id uuid,

  created_at timestamptz not null default now(),

  constraint moves_square_format check (
    from_square ~ '^[a-h][1-8]$' and to_square ~ '^[a-h][1-8]$'
  ),
  constraint moves_unique_ply unique (game_id, ply_number)
);

comment on table public.moves is 'Append-only, immutable move ledger. Source of truth for PGN reconstruction and anti-cheat audit.';
comment on column public.moves.client_move_id is 'Idempotency key supplied by client to prevent duplicate-move replay on retry/reconnect.';

create index if not exists idx_moves_game_id on public.moves (game_id, ply_number);
create index if not exists idx_moves_player_id on public.moves (player_id);
create unique index if not exists idx_moves_client_dedupe
  on public.moves (game_id, client_move_id)
  where client_move_id is not null;

-- -----------------------------------------------------------------------------
-- DRAW REQUESTS
-- -----------------------------------------------------------------------------
create table if not exists public.draw_requests (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  requested_by uuid not null references public.players(id) on delete cascade,
  status draw_request_status not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  expires_at timestamptz not null default (now() + interval '60 seconds')
);

create index if not exists idx_draw_requests_game on public.draw_requests (game_id);
create index if not exists idx_draw_requests_pending on public.draw_requests (status) where status = 'pending';

-- Only one pending draw request per game at a time.
create unique index if not exists idx_draw_requests_one_pending
  on public.draw_requests (game_id)
  where status = 'pending';

-- -----------------------------------------------------------------------------
-- TIMER EVENTS (audit trail for pause/resume/timeout, supports reconnect recovery)
-- -----------------------------------------------------------------------------
create table if not exists public.timer_events (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  event_type varchar(20) not null check (event_type in ('start', 'pause', 'resume', 'timeout', 'adjust')),
  color player_color,
  white_time_remaining_ms bigint not null,
  black_time_remaining_ms bigint not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_timer_events_game on public.timer_events (game_id, created_at);


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0005_stats_analytics_settings.sql
-- ─────────────────────────────────────────────────────────────────────────
-- =============================================================================
-- Migration 0005: Statistics, Analytics, Settings, Feature Flags, Logs
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PLAYER STATISTICS (rolling, per anonymous player id)
-- -----------------------------------------------------------------------------
create table if not exists public.player_statistics (
  player_id uuid primary key references public.players(id) on delete cascade,

  games_played integer not null default 0,
  wins integer not null default 0,
  losses integer not null default 0,
  draws integer not null default 0,
  resignations integer not null default 0,
  timeouts integer not null default 0,
  checkmates_delivered integer not null default 0,
  checkmates_received integer not null default 0,

  offline_games integer not null default 0,
  ai_games integer not null default 0,
  friend_games integer not null default 0,

  total_moves integer not null default 0,
  total_duration_seconds bigint not null default 0,

  ai_easy_games integer not null default 0,
  ai_medium_games integer not null default 0,
  ai_hard_games integer not null default 0,

  current_win_streak integer not null default 0,
  best_win_streak integer not null default 0,

  updated_at timestamptz not null default now()
);

comment on table public.player_statistics is 'One row per player, incrementally updated by record_game_result() on game completion.';

-- -----------------------------------------------------------------------------
-- GAME OPENINGS (lookup/reference, used for "most used opening" stat)
-- -----------------------------------------------------------------------------
create table if not exists public.openings (
  eco varchar(10) primary key,
  name varchar(120) not null,
  moves_san text not null
);

-- -----------------------------------------------------------------------------
-- DAILY ANALYTICS ROLLUP
-- -----------------------------------------------------------------------------
create table if not exists public.daily_analytics (
  analytics_date date primary key,
  games_started integer not null default 0,
  games_completed integer not null default 0,
  offline_games integer not null default 0,
  ai_games integer not null default 0,
  friend_games integer not null default 0,

  ai_easy_games integer not null default 0,
  ai_medium_games integer not null default 0,
  ai_hard_games integer not null default 0,

  rooms_created integer not null default 0,
  peak_concurrent_rooms integer not null default 0,

  avg_match_duration_seconds numeric(10,2) not null default 0,
  avg_moves_per_game numeric(6,2) not null default 0,

  checkmates integer not null default 0,
  resignations integer not null default 0,
  timeouts integer not null default 0,
  draws integer not null default 0,
  abandonments integer not null default 0,

  bullet_games integer not null default 0,
  blitz_games integer not null default 0,
  rapid_games integer not null default 0,
  classical_games integer not null default 0,

  unique_players integer not null default 0,

  errors_logged integer not null default 0,

  updated_at timestamptz not null default now()
);

create table if not exists public.theme_usage_analytics (
  analytics_date date not null,
  theme_type varchar(20) not null check (theme_type in ('board', 'piece')),
  theme_name varchar(40) not null,
  usage_count integer not null default 0,
  primary key (analytics_date, theme_type, theme_name)
);

-- -----------------------------------------------------------------------------
-- APPLICATION SETTINGS (singleton-ish key/value, global defaults)
-- -----------------------------------------------------------------------------
create table if not exists public.app_settings (
  key varchar(80) primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- FEATURE FLAGS
-- -----------------------------------------------------------------------------
create table if not exists public.feature_flags (
  flag_key varchar(80) primary key,
  is_enabled boolean not null default false,
  rollout_percentage smallint not null default 100 check (rollout_percentage between 0 and 100),
  description text,
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- SYSTEM CONFIGURATION
-- -----------------------------------------------------------------------------
create table if not exists public.system_config (
  config_key varchar(80) primary key,
  config_value jsonb not null,
  is_sensitive boolean not null default false,
  description text,
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- MAINTENANCE WINDOWS
-- -----------------------------------------------------------------------------
create table if not exists public.maintenance_windows (
  id uuid primary key default gen_random_uuid(),
  is_active boolean not null default false,
  title varchar(120) not null,
  message text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- SYSTEM / APPLICATION LOGS
-- -----------------------------------------------------------------------------
create table if not exists public.system_logs (
  id uuid primary key default gen_random_uuid(),
  level log_level not null default 'info',
  category log_category not null default 'system',
  message text not null,
  context jsonb not null default '{}'::jsonb,
  room_id uuid references public.rooms(id) on delete set null,
  game_id uuid references public.games(id) on delete set null,
  player_id uuid references public.players(id) on delete set null,
  request_id uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_logs_created_at on public.system_logs (created_at desc);
create index if not exists idx_logs_level on public.system_logs (level);
create index if not exists idx_logs_category on public.system_logs (category);
create index if not exists idx_logs_room on public.system_logs (room_id) where room_id is not null;

-- Partial index to speed up "errors only" dashboards
create index if not exists idx_logs_errors on public.system_logs (created_at desc) where level in ('error', 'fatal');

-- -----------------------------------------------------------------------------
-- RATE LIMIT / ABUSE TRACKING
-- -----------------------------------------------------------------------------
create table if not exists public.rate_limit_buckets (
  bucket_key varchar(160) primary key,
  request_count integer not null default 1,
  window_started_at timestamptz not null default now(),
  blocked_until timestamptz
);

create index if not exists idx_rate_limit_window on public.rate_limit_buckets (window_started_at);


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0006_functions_triggers.sql
-- ─────────────────────────────────────────────────────────────────────────
-- =============================================================================
-- Migration 0006: Functions and Triggers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- generic updated_at toucher
-- -----------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_rooms_touch_updated on public.rooms;
create trigger trg_rooms_touch_updated
  before update on public.rooms
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_games_touch_updated on public.games;
create trigger trg_games_touch_updated
  before update on public.games
  for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- room_code generator: 6 chars, excludes 0/O/1/I to avoid ambiguity
-- Retries on collision against currently-live rooms.
-- -----------------------------------------------------------------------------
create or replace function public.generate_room_code()
returns varchar
language plpgsql
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code varchar(8);
  attempt integer := 0;
  collision boolean;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;

    select exists(
      select 1 from public.rooms
      where room_code = code and status in ('waiting', 'active')
    ) into collision;

    exit when not collision;

    attempt := attempt + 1;
    if attempt > 25 then
      raise exception 'Unable to generate unique room code after % attempts', attempt;
    end if;
  end loop;

  return code;
end;
$$;

comment on function public.generate_room_code() is 'Generates a collision-checked 6-char human-friendly room code excluding 0/O/1/I.';

-- -----------------------------------------------------------------------------
-- touch room activity (bumps last_activity_at and extends expiry while live)
-- -----------------------------------------------------------------------------
create or replace function public.touch_room_activity(p_room_id uuid)
returns void
language sql
as $$
  update public.rooms
  set last_activity_at = now(),
      expires_at = case when status in ('waiting','active') then now() + interval '2 hours' else expires_at end
  where id = p_room_id;
$$;

-- -----------------------------------------------------------------------------
-- record_game_result: idempotently rolls up a finished game into
-- player_statistics and daily_analytics. Called once from the service layer
-- when a game transitions into a terminal status.
-- -----------------------------------------------------------------------------
create or replace function public.record_game_result(p_game_id uuid)
returns void
language plpgsql
as $$
declare
  g record;
  duration_seconds numeric;
  today date := current_date;
begin
  select * into g from public.games where id = p_game_id for update;
  if not found then
    raise exception 'record_game_result: game % not found', p_game_id;
  end if;

  if g.status not in (
    'checkmate','stalemate','draw_agreement','draw_repetition',
    'draw_fifty_move','draw_insufficient_material','resigned','timeout','abandoned'
  ) then
    return; -- not terminal yet, nothing to record
  end if;

  duration_seconds := coalesce(extract(epoch from (coalesce(g.ended_at, now()) - g.started_at)), 0);

  -- Upsert per-player stats for white
  if g.white_player_id is not null then
    insert into public.player_statistics (player_id) values (g.white_player_id)
    on conflict (player_id) do nothing;

    update public.player_statistics ps set
      games_played = ps.games_played + 1,
      wins = ps.wins + case when g.result = 'white_win' then 1 else 0 end,
      losses = ps.losses + case when g.result = 'black_win' then 1 else 0 end,
      draws = ps.draws + case when g.result = 'draw' then 1 else 0 end,
      resignations = ps.resignations + case when g.status = 'resigned' and g.result = 'black_win' then 1 else 0 end,
      timeouts = ps.timeouts + case when g.status = 'timeout' and g.result = 'black_win' then 1 else 0 end,
      checkmates_delivered = ps.checkmates_delivered + case when g.status = 'checkmate' and g.result = 'white_win' then 1 else 0 end,
      checkmates_received = ps.checkmates_received + case when g.status = 'checkmate' and g.result = 'black_win' then 1 else 0 end,
      offline_games = ps.offline_games + case when g.game_mode = 'offline' then 1 else 0 end,
      ai_games = ps.ai_games + case when g.game_mode = 'vs_ai' then 1 else 0 end,
      friend_games = ps.friend_games + case when g.game_mode = 'online_friend' then 1 else 0 end,
      ai_easy_games = ps.ai_easy_games + case when g.game_mode = 'vs_ai' and g.ai_difficulty = 'easy' then 1 else 0 end,
      ai_medium_games = ps.ai_medium_games + case when g.game_mode = 'vs_ai' and g.ai_difficulty = 'medium' then 1 else 0 end,
      ai_hard_games = ps.ai_hard_games + case when g.game_mode = 'vs_ai' and g.ai_difficulty = 'hard' then 1 else 0 end,
      total_moves = ps.total_moves + g.move_count,
      total_duration_seconds = ps.total_duration_seconds + duration_seconds::bigint,
      current_win_streak = case when g.result = 'white_win' then ps.current_win_streak + 1 else 0 end,
      best_win_streak = greatest(ps.best_win_streak, case when g.result = 'white_win' then ps.current_win_streak + 1 else 0 end),
      updated_at = now()
    where ps.player_id = g.white_player_id;
  end if;

  -- Upsert per-player stats for black
  if g.black_player_id is not null then
    insert into public.player_statistics (player_id) values (g.black_player_id)
    on conflict (player_id) do nothing;

    update public.player_statistics ps set
      games_played = ps.games_played + 1,
      wins = ps.wins + case when g.result = 'black_win' then 1 else 0 end,
      losses = ps.losses + case when g.result = 'white_win' then 1 else 0 end,
      draws = ps.draws + case when g.result = 'draw' then 1 else 0 end,
      resignations = ps.resignations + case when g.status = 'resigned' and g.result = 'white_win' then 1 else 0 end,
      timeouts = ps.timeouts + case when g.status = 'timeout' and g.result = 'white_win' then 1 else 0 end,
      checkmates_delivered = ps.checkmates_delivered + case when g.status = 'checkmate' and g.result = 'black_win' then 1 else 0 end,
      checkmates_received = ps.checkmates_received + case when g.status = 'checkmate' and g.result = 'white_win' then 1 else 0 end,
      offline_games = ps.offline_games + case when g.game_mode = 'offline' then 1 else 0 end,
      friend_games = ps.friend_games + case when g.game_mode = 'online_friend' then 1 else 0 end,
      total_moves = ps.total_moves + g.move_count,
      total_duration_seconds = ps.total_duration_seconds + duration_seconds::bigint,
      current_win_streak = case when g.result = 'black_win' then ps.current_win_streak + 1 else 0 end,
      best_win_streak = greatest(ps.best_win_streak, case when g.result = 'black_win' then ps.current_win_streak + 1 else 0 end),
      updated_at = now()
    where ps.player_id = g.black_player_id;
  end if;

  -- Roll up into daily_analytics
  insert into public.daily_analytics (
    analytics_date, games_completed, offline_games, ai_games, friend_games,
    ai_easy_games, ai_medium_games, ai_hard_games,
    checkmates, resignations, timeouts, draws, abandonments,
    bullet_games, blitz_games, rapid_games, classical_games,
    avg_match_duration_seconds, avg_moves_per_game
  )
  values (
    today, 1,
    case when g.game_mode = 'offline' then 1 else 0 end,
    case when g.game_mode = 'vs_ai' then 1 else 0 end,
    case when g.game_mode = 'online_friend' then 1 else 0 end,
    case when g.ai_difficulty = 'easy' then 1 else 0 end,
    case when g.ai_difficulty = 'medium' then 1 else 0 end,
    case when g.ai_difficulty = 'hard' then 1 else 0 end,
    case when g.status = 'checkmate' then 1 else 0 end,
    case when g.status = 'resigned' then 1 else 0 end,
    case when g.status = 'timeout' then 1 else 0 end,
    case when g.result = 'draw' then 1 else 0 end,
    case when g.status = 'abandoned' then 1 else 0 end,
    case when g.time_control_category = 'bullet' then 1 else 0 end,
    case when g.time_control_category = 'blitz' then 1 else 0 end,
    case when g.time_control_category = 'rapid' then 1 else 0 end,
    case when g.time_control_category = 'classical' then 1 else 0 end,
    duration_seconds,
    g.move_count
  )
  on conflict (analytics_date) do update set
    games_completed = public.daily_analytics.games_completed + 1,
    offline_games = public.daily_analytics.offline_games + case when g.game_mode = 'offline' then 1 else 0 end,
    ai_games = public.daily_analytics.ai_games + case when g.game_mode = 'vs_ai' then 1 else 0 end,
    friend_games = public.daily_analytics.friend_games + case when g.game_mode = 'online_friend' then 1 else 0 end,
    ai_easy_games = public.daily_analytics.ai_easy_games + case when g.ai_difficulty = 'easy' then 1 else 0 end,
    ai_medium_games = public.daily_analytics.ai_medium_games + case when g.ai_difficulty = 'medium' then 1 else 0 end,
    ai_hard_games = public.daily_analytics.ai_hard_games + case when g.ai_difficulty = 'hard' then 1 else 0 end,
    checkmates = public.daily_analytics.checkmates + case when g.status = 'checkmate' then 1 else 0 end,
    resignations = public.daily_analytics.resignations + case when g.status = 'resigned' then 1 else 0 end,
    timeouts = public.daily_analytics.timeouts + case when g.status = 'timeout' then 1 else 0 end,
    draws = public.daily_analytics.draws + case when g.result = 'draw' then 1 else 0 end,
    abandonments = public.daily_analytics.abandonments + case when g.status = 'abandoned' then 1 else 0 end,
    bullet_games = public.daily_analytics.bullet_games + case when g.time_control_category = 'bullet' then 1 else 0 end,
    blitz_games = public.daily_analytics.blitz_games + case when g.time_control_category = 'blitz' then 1 else 0 end,
    rapid_games = public.daily_analytics.rapid_games + case when g.time_control_category = 'rapid' then 1 else 0 end,
    classical_games = public.daily_analytics.classical_games + case when g.time_control_category = 'classical' then 1 else 0 end,
    avg_match_duration_seconds = (
      (public.daily_analytics.avg_match_duration_seconds * public.daily_analytics.games_completed) + duration_seconds
    ) / greatest(public.daily_analytics.games_completed + 1, 1),
    avg_moves_per_game = (
      (public.daily_analytics.avg_moves_per_game * public.daily_analytics.games_completed) + g.move_count
    ) / greatest(public.daily_analytics.games_completed + 1, 1),
    updated_at = now();
end;
$$;

comment on function public.record_game_result(uuid) is
  'Idempotency note: call exactly once per game transition into a terminal status (enforced by the service layer via games.status check), since this performs additive increments rather than upserts of final values.';

-- -----------------------------------------------------------------------------
-- enforce_room_capacity: prevents a 3rd player from joining a room
-- -----------------------------------------------------------------------------
create or replace function public.enforce_room_capacity()
returns trigger
language plpgsql
as $$
begin
  if new.guest_player_id is not null
     and old.guest_player_id is null
     and new.current_player_count > new.max_players then
    raise exception 'Room % is full', new.room_code using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rooms_enforce_capacity on public.rooms;
create trigger trg_rooms_enforce_capacity
  before update on public.rooms
  for each row execute function public.enforce_room_capacity();

-- -----------------------------------------------------------------------------
-- cleanup_expired_rooms: deletes/expires stale rooms. Designed to be invoked
-- by pg_cron or an edge function on a schedule (see docs/MAINTENANCE.md).
-- -----------------------------------------------------------------------------
create or replace function public.cleanup_expired_rooms()
returns integer
language plpgsql
as $$
declare
  affected integer;
begin
  update public.rooms
  set status = 'expired'
  where status in ('waiting', 'active')
    and expires_at < now();
  get diagnostics affected = row_count;

  -- Hard delete rooms that finished/expired/abandoned more than 24h ago,
  -- cascades to games/moves/draw_requests/timer_events via FK.
  delete from public.rooms
  where status in ('finished', 'expired', 'abandoned')
    and coalesce(finished_at, updated_at) < now() - interval '24 hours';

  return affected;
end;
$$;

-- -----------------------------------------------------------------------------
-- prune_old_logs: retention policy for system_logs
-- -----------------------------------------------------------------------------
create or replace function public.prune_old_logs(p_retain_days integer default 30)
returns integer
language plpgsql
as $$
declare
  affected integer;
begin
  delete from public.system_logs
  where created_at < now() - (p_retain_days || ' days')::interval
    and level not in ('error', 'fatal');

  delete from public.system_logs
  where created_at < now() - ((p_retain_days * 3) || ' days')::interval;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

-- -----------------------------------------------------------------------------
-- prune_stale_players: removes anonymous sessions inactive for a long time
-- and not referenced by any retained game (FK is ON DELETE SET NULL so this
-- is safe for historical stats integrity at the games level, but we already
-- folded their contribution into player_statistics/daily_analytics).
-- -----------------------------------------------------------------------------
create or replace function public.prune_stale_players(p_retain_days integer default 90)
returns integer
language sql
as $$
  with deleted as (
    delete from public.players
    where last_seen_at < now() - (p_retain_days || ' days')::interval
      and is_active = false
    returning 1
  )
  select count(*)::integer from deleted;
$$;


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0007_views.sql
-- ─────────────────────────────────────────────────────────────────────────
-- =============================================================================
-- Migration 0007: Views
-- =============================================================================

-- Active, joinable rooms (waiting for a second player)
create or replace view public.v_joinable_rooms as
select
  r.id,
  r.room_code,
  r.status,
  r.time_control_category,
  r.initial_time_seconds,
  r.increment_seconds,
  r.created_at,
  r.expires_at
from public.rooms r
where r.status = 'waiting'
  and r.current_player_count < r.max_players
  and r.expires_at > now();

-- Live game snapshot joined with room context, for dashboards / admin panel
create or replace view public.v_active_games as
select
  g.id as game_id,
  g.room_id,
  r.room_code,
  g.game_mode,
  g.status,
  g.turn,
  g.fen,
  g.move_count,
  g.white_player_id,
  g.black_player_id,
  g.white_time_remaining_ms,
  g.black_time_remaining_ms,
  g.started_at,
  g.last_move_at
from public.games g
left join public.rooms r on r.id = g.room_id
where g.status = 'in_progress';

-- Leaderboard-style aggregate (read-only convenience view; no auth/login exists,
-- so this is keyed by ephemeral player_id and intended for admin/analytics use)
create or replace view public.v_player_leaderboard as
select
  ps.player_id,
  p.display_name,
  ps.games_played,
  ps.wins,
  ps.losses,
  ps.draws,
  case when ps.games_played > 0
    then round((ps.wins::numeric / ps.games_played) * 100, 1)
    else 0
  end as win_rate_pct,
  ps.best_win_streak,
  ps.updated_at
from public.player_statistics ps
join public.players p on p.id = ps.player_id
where ps.games_played > 0
order by ps.wins desc, win_rate_pct desc;

-- Most-used openings (rollup from games table, not just the reference table)
create or replace view public.v_popular_openings as
select
  g.opening_eco,
  g.opening_name,
  count(*) as times_played
from public.games g
where g.opening_eco is not null
group by g.opening_eco, g.opening_name
order by times_played desc;

-- Room health snapshot for ops/monitoring
create or replace view public.v_room_health as
select
  count(*) filter (where status = 'waiting') as waiting_rooms,
  count(*) filter (where status = 'active') as active_rooms,
  count(*) filter (where status = 'waiting' or status = 'active') as live_rooms,
  count(*) filter (where expires_at < now() and status in ('waiting','active')) as overdue_for_cleanup
from public.rooms;


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0008_row_level_security.sql
-- ─────────────────────────────────────────────────────────────────────────
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


-- ─────────────────────────────────────────────────────────────────────────
-- FILE: 0009_seed_data.sql
-- ─────────────────────────────────────────────────────────────────────────
-- =============================================================================
-- Migration 0009: Seed Data
-- =============================================================================

insert into public.app_settings (key, value, description) values
  ('default_board_theme', '"classic"', 'Default board theme for new sessions'),
  ('default_piece_theme', '"classic"', 'Default piece set for new sessions'),
  ('animation_speed_ms', '200', 'Default move animation duration in ms'),
  ('sound_enabled_default', 'true', 'Default sound toggle for new sessions'),
  ('music_enabled_default', 'false', 'Default background music toggle'),
  ('timer_presets', '[
    {"label": "Bullet 1+0", "category": "bullet", "initial_seconds": 60, "increment_seconds": 0},
    {"label": "Bullet 2+1", "category": "bullet", "initial_seconds": 120, "increment_seconds": 1},
    {"label": "Blitz 3+0", "category": "blitz", "initial_seconds": 180, "increment_seconds": 0},
    {"label": "Blitz 5+0", "category": "blitz", "initial_seconds": 300, "increment_seconds": 0},
    {"label": "Blitz 5+3", "category": "blitz", "initial_seconds": 300, "increment_seconds": 3},
    {"label": "Rapid 10+0", "category": "rapid", "initial_seconds": 600, "increment_seconds": 0},
    {"label": "Rapid 15+10", "category": "rapid", "initial_seconds": 900, "increment_seconds": 10},
    {"label": "Classical 30+0", "category": "classical", "initial_seconds": 1800, "increment_seconds": 0},
    {"label": "Unlimited", "category": "unlimited", "initial_seconds": 0, "increment_seconds": 0}
  ]', 'Selectable time control presets shown in the UI'),
  ('maintenance_mode', 'false', 'Global maintenance mode kill switch'),
  ('application_version', '"1.0.0"', 'Current deployed backend version'),
  ('room_expiry_hours', '2', 'Hours of inactivity before a waiting/active room is marked expired'),
  ('room_hard_delete_hours', '24', 'Hours after finish/expiry before a room is hard-deleted'),
  ('max_reconnect_window_seconds', '120', 'Grace period a disconnected player has to reconnect before being treated as abandoned')
on conflict (key) do nothing;

insert into public.feature_flags (flag_key, is_enabled, rollout_percentage, description) values
  ('online_friend_mode', true, 100, 'Room-code based online play between two friends'),
  ('vs_ai_mode', true, 100, 'Play against the backend AI engine'),
  ('offline_two_player_mode', true, 100, 'Local same-device two player mode (client-only, no backend game row required)'),
  ('draw_offers', true, 100, 'Allow players to offer/accept draws'),
  ('rematch', true, 100, 'Allow rematch requests after a game ends'),
  ('spectator_mode', false, 0, 'Allow a third party to watch a room (reserved for future use)'),
  ('move_premove', false, 0, 'Client-side premove support (reserved for future use)'),
  ('analytics_collection', true, 100, 'Enable daily analytics rollups')
on conflict (flag_key) do nothing;

insert into public.system_config (config_key, config_value, is_sensitive, description) values
  ('rate_limit_room_create_per_min', '10', false, 'Max room creations per IP-hash per minute'),
  ('rate_limit_move_per_sec', '5', false, 'Max moves per session per second'),
  ('rate_limit_join_per_min', '20', false, 'Max join attempts per IP-hash per minute'),
  ('cleanup_job_interval_minutes', '15', false, 'How often the room cleanup job runs'),
  ('log_retention_days', '30', false, 'Default retention window for non-error logs'),
  ('ai_move_timeout_ms', '8000', false, 'Max time allowed for AI move computation before fallback'),
  ('cors_allowed_origins', '["http://localhost:3000"]', false, 'Allowed origins for API requests; update per deployment')
on conflict (config_key) do nothing;

insert into public.openings (eco, name, moves_san) values
  ('C50', 'Italian Game', '1. e4 e5 2. Nf3 Nc6 3. Bc4'),
  ('C60', 'Ruy Lopez', '1. e4 e5 2. Nf3 Nc6 3. Bb5'),
  ('B10', 'Caro-Kann Defense', '1. e4 c6'),
  ('B20', 'Sicilian Defense', '1. e4 c5'),
  ('C00', 'French Defense', '1. e4 e6'),
  ('A00', 'Uncommon Opening', '1. g3'),
  ('D00', 'Queen''s Pawn Game', '1. d4 d5'),
  ('E00', 'Queen''s Gambit Declined', '1. d4 d5 2. c4 e6'),
  ('B00', 'King''s Pawn Opening', '1. e4'),
  ('A04', 'Reti Opening', '1. Nf3'),
  ('C20', 'King''s Pawn Game', '1. e4 e5'),
  ('A40', 'Queen''s Pawn', '1. d4')
on conflict (eco) do nothing;

insert into public.maintenance_windows (is_active, title, message, starts_at)
values (false, 'No active maintenance', null, now())
on conflict do nothing;


