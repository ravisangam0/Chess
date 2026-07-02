// Hand-authored to mirror supabase/migrations/*.sql exactly.
// Regenerate/update this file whenever a migration changes table shape.
// In CI, prefer: `supabase gen types typescript --linked > src/types/database.types.ts`
// and diff against this file to catch drift.

export type GameMode = 'offline' | 'vs_ai' | 'online_friend';
export type AiDifficulty = 'easy' | 'medium' | 'hard';
export type RoomStatus = 'waiting' | 'active' | 'finished' | 'abandoned' | 'expired';
export type PlayerColor = 'white' | 'black';
export type ConnectionStatus = 'connected' | 'disconnected' | 'reconnecting';
export type GameStatus =
  | 'pending' | 'in_progress' | 'checkmate' | 'stalemate' | 'draw_agreement'
  | 'draw_repetition' | 'draw_fifty_move' | 'draw_insufficient_material'
  | 'resigned' | 'timeout' | 'abandoned';
export type GameResult = 'white_win' | 'black_win' | 'draw' | 'ongoing' | 'aborted';
export type TimeControlCategory = 'bullet' | 'blitz' | 'rapid' | 'classical' | 'unlimited';
export type MoveType = 'normal' | 'capture' | 'castle_kingside' | 'castle_queenside' | 'en_passant' | 'promotion';
export type DrawRequestStatus = 'pending' | 'accepted' | 'declined' | 'expired';
export type LogLevel = 'debug' | 'info' | 'warn' | 'error' | 'fatal';
export type LogCategory =
  | 'room' | 'move' | 'realtime' | 'database' | 'api' | 'security'
  | 'performance' | 'system' | 'maintenance';

export interface PlayerRow {
  id: string;
  session_token: string;
  display_name: string;
  avatar_seed: string | null;
  created_at: string;
  last_seen_at: string;
  is_active: boolean;
  device_fingerprint: string | null;
  ip_hash: string | null;
  user_agent: string | null;
  metadata: Record<string, unknown>;
}

export interface RoomRow {
  id: string;
  room_code: string;
  status: RoomStatus;
  game_mode: GameMode;
  host_player_id: string;
  guest_player_id: string | null;
  host_color: PlayerColor;
  host_connection: ConnectionStatus;
  guest_connection: ConnectionStatus;
  time_control_category: TimeControlCategory;
  initial_time_seconds: number;
  increment_seconds: number;
  delay_seconds: number;
  board_theme: string;
  piece_theme: string;
  max_players: number;
  current_player_count: number;
  is_private: boolean;
  allow_spectators: boolean;
  created_at: string;
  updated_at: string;
  started_at: string | null;
  finished_at: string | null;
  expires_at: string;
  last_activity_at: string;
  metadata: Record<string, unknown>;
}

export interface GameRow {
  id: string;
  room_id: string | null;
  game_mode: GameMode;
  ai_difficulty: AiDifficulty | null;
  white_player_id: string | null;
  black_player_id: string | null;
  fen: string;
  pgn: string;
  initial_fen: string;
  turn: PlayerColor;
  fullmove_number: number;
  halfmove_clock: number;
  is_check: boolean;
  is_checkmate: boolean;
  is_stalemate: boolean;
  is_draw: boolean;
  is_threefold_repetition: boolean;
  is_insufficient_material: boolean;
  status: GameStatus;
  result: GameResult;
  winner_player_id: string | null;
  end_reason: string | null;
  captured_white_pieces: string[];
  captured_black_pieces: string[];
  white_time_remaining_ms: number;
  black_time_remaining_ms: number;
  increment_seconds: number;
  delay_seconds: number;
  time_control_category: TimeControlCategory;
  move_count: number;
  opening_eco: string | null;
  opening_name: string | null;
  is_rematch_of: string | null;
  created_at: string;
  updated_at: string;
  started_at: string | null;
  ended_at: string | null;
  last_move_at: string | null;
  metadata: Record<string, unknown>;
}

export interface MoveRow {
  id: string;
  game_id: string;
  player_id: string | null;
  ply_number: number;
  fullmove_number: number;
  color: PlayerColor;
  san: string;
  uci: string;
  from_square: string;
  to_square: string;
  piece: string;
  captured_piece: string | null;
  promotion_piece: string | null;
  move_type: MoveType;
  fen_before: string;
  fen_after: string;
  is_check: boolean;
  is_checkmate: boolean;
  white_time_remaining_ms: number;
  black_time_remaining_ms: number;
  think_time_ms: number;
  client_move_id: string | null;
  created_at: string;
}

export interface DrawRequestRow {
  id: string;
  game_id: string;
  requested_by: string;
  status: DrawRequestStatus;
  created_at: string;
  resolved_at: string | null;
  expires_at: string;
}

export interface TimerEventRow {
  id: string;
  game_id: string;
  event_type: 'start' | 'pause' | 'resume' | 'timeout' | 'adjust';
  color: PlayerColor | null;
  white_time_remaining_ms: number;
  black_time_remaining_ms: number;
  created_at: string;
}

export interface PlayerStatisticsRow {
  player_id: string;
  games_played: number;
  wins: number;
  losses: number;
  draws: number;
  resignations: number;
  timeouts: number;
  checkmates_delivered: number;
  checkmates_received: number;
  offline_games: number;
  ai_games: number;
  friend_games: number;
  total_moves: number;
  total_duration_seconds: number;
  ai_easy_games: number;
  ai_medium_games: number;
  ai_hard_games: number;
  current_win_streak: number;
  best_win_streak: number;
  updated_at: string;
}

export interface SystemLogRow {
  id: string;
  level: LogLevel;
  category: LogCategory;
  message: string;
  context: Record<string, unknown>;
  room_id: string | null;
  game_id: string | null;
  player_id: string | null;
  request_id: string | null;
  created_at: string;
}

// Minimal Database generic shape consumed by supabase-js typings.
// Must match supabase-js's GenericTable/GenericSchema shape exactly:
// { Tables: Record<string, { Row; Insert; Update; Relationships }>,
//   Views: Record<string, ...>, Functions: Record<string, { Args; Returns }> }
type NoRelationships = { foreignKeyName: string; columns: string[]; isOneToOne?: boolean; referencedRelation: string; referencedColumns: string[] }[];

export interface Database {
  public: {
    Tables: {
      players: { Row: PlayerRow; Insert: Partial<PlayerRow>; Update: Partial<PlayerRow>; Relationships: NoRelationships };
      rooms: { Row: RoomRow; Insert: Partial<RoomRow>; Update: Partial<RoomRow>; Relationships: NoRelationships };
      games: { Row: GameRow; Insert: Partial<GameRow>; Update: Partial<GameRow>; Relationships: NoRelationships };
      moves: { Row: MoveRow; Insert: Partial<MoveRow>; Update: Partial<MoveRow>; Relationships: NoRelationships };
      draw_requests: { Row: DrawRequestRow; Insert: Partial<DrawRequestRow>; Update: Partial<DrawRequestRow>; Relationships: NoRelationships };
      timer_events: { Row: TimerEventRow; Insert: Partial<TimerEventRow>; Update: Partial<TimerEventRow>; Relationships: NoRelationships };
      player_statistics: { Row: PlayerStatisticsRow; Insert: Partial<PlayerStatisticsRow>; Update: Partial<PlayerStatisticsRow>; Relationships: NoRelationships };
      system_logs: { Row: SystemLogRow; Insert: Partial<SystemLogRow>; Update: Partial<SystemLogRow>; Relationships: NoRelationships };
    };
    Views: Record<string, never>;
    Functions: {
      generate_room_code: { Args: Record<string, never>; Returns: string };
      touch_room_activity: { Args: { p_room_id: string }; Returns: void };
      record_game_result: { Args: { p_game_id: string }; Returns: void };
      cleanup_expired_rooms: { Args: Record<string, never>; Returns: number };
      prune_old_logs: { Args: { p_retain_days?: number }; Returns: number };
      prune_stale_players: { Args: { p_retain_days?: number }; Returns: number };
    };
  };
}
