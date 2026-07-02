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
