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
