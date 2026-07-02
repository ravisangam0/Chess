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
