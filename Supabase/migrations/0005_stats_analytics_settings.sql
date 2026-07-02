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
