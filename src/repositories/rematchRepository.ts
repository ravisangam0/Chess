import { supabaseAdmin } from '../config/supabase.js';
import { AppError } from '../errors/AppError.js';
import { logger } from '../utils/logger.js';
import type { GameRow, RoomRow } from '../types/database.types.js';

export const rematchRepository = {
  async findRoomForGame(gameId: string): Promise<{ game: GameRow; room: RoomRow } | null> {
    const { data: game, error: gameError } = await supabaseAdmin.from('games').select('*').eq('id', gameId).maybeSingle();
    if (gameError || !game) return null;

    const gameRow = game as GameRow;
    if (!gameRow.room_id) return null;

    const { data: room, error: roomError } = await supabaseAdmin.from('rooms').select('*').eq('id', gameRow.room_id).maybeSingle();
    if (roomError || !room) return null;

    return { game: gameRow, room: room as RoomRow };
  },

  async createRematchGame(previousGame: GameRow, room: RoomRow): Promise<GameRow> {
    // Swap colors each rematch so both players get a turn with each side.
    const newWhiteId = previousGame.black_player_id;
    const newBlackId = previousGame.white_player_id;
    const initialMs = room.initial_time_seconds * 1000;

    const { data, error } = await supabaseAdmin
      .from('games')
      .insert({
        room_id: room.id,
        game_mode: 'online_friend',
        white_player_id: newWhiteId,
        black_player_id: newBlackId,
        status: 'in_progress',
        time_control_category: room.time_control_category,
        white_time_remaining_ms: initialMs,
        black_time_remaining_ms: initialMs,
        increment_seconds: room.increment_seconds,
        is_rematch_of: previousGame.id,
        started_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to create rematch game', { error: error?.message, previousGameId: previousGame.id });
      throw new AppError('DATABASE_ERROR', 'Could not start the rematch.');
    }
    return data as GameRow;
  },
};
