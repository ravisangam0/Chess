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
