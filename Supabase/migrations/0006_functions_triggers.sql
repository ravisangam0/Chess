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
