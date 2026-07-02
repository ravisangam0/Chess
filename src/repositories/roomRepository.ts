import { supabaseAdmin } from '../config/supabase.js';
import { AppError } from '../errors/AppError.js';
import { logger } from '../utils/logger.js';
import type { RoomRow, PlayerRow, GameRow } from '../types/database.types.js';

export const roomRepository = {
  async generateRoomCode(): Promise<string> {
    const { data, error } = await supabaseAdmin.rpc('generate_room_code');
    if (error || !data) {
      logger.error('database', 'Failed to generate room code', { error: error?.message });
      throw new AppError('DATABASE_ERROR', 'Could not generate a room code.');
    }
    return data as unknown as string;
  },

  async createPlayer(displayName: string, ipHash?: string, userAgent?: string): Promise<PlayerRow> {
    const { data, error } = await supabaseAdmin
      .from('players')
      .insert({ display_name: displayName, ip_hash: ipHash ?? null, user_agent: userAgent ?? null })
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to create player', { error: error?.message });
      throw new AppError('DATABASE_ERROR', 'Could not create a player session.');
    }
    return data as PlayerRow;
  },

  async createRoom(params: {
    roomCode: string;
    hostPlayerId: string;
    timeControlCategory: string;
    initialTimeSeconds: number;
    incrementSeconds: number;
    boardTheme: string;
    pieceTheme: string;
    hostColor: 'white' | 'black';
  }): Promise<RoomRow> {
    const { data, error } = await supabaseAdmin
      .from('rooms')
      .insert({
        room_code: params.roomCode,
        host_player_id: params.hostPlayerId,
        time_control_category: params.timeControlCategory as never,
        initial_time_seconds: params.initialTimeSeconds,
        increment_seconds: params.incrementSeconds,
        board_theme: params.boardTheme,
        piece_theme: params.pieceTheme,
        host_color: params.hostColor,
        status: 'waiting',
        current_player_count: 1,
      })
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to create room', { error: error?.message, roomCode: params.roomCode });
      throw new AppError('DATABASE_ERROR', 'Could not create the room.');
    }
    return data as RoomRow;
  },

  async findRoomByCode(roomCode: string): Promise<RoomRow | null> {
    const { data, error } = await supabaseAdmin
      .from('rooms')
      .select('*')
      .eq('room_code', roomCode.toUpperCase())
      .in('status', ['waiting', 'active'])
      .maybeSingle();

    if (error) {
      logger.error('database', 'Failed to look up room', { error: error.message, roomCode });
      throw new AppError('DATABASE_ERROR', 'Could not look up the room.');
    }
    return (data as RoomRow) ?? null;
  },

  async findRoomById(roomId: string): Promise<RoomRow | null> {
    const { data, error } = await supabaseAdmin.from('rooms').select('*').eq('id', roomId).maybeSingle();
    if (error) {
      logger.error('database', 'Failed to look up room by id', { error: error.message, roomId });
      throw new AppError('DATABASE_ERROR', 'Could not look up the room.');
    }
    return (data as RoomRow) ?? null;
  },

  async attachGuest(roomId: string, guestPlayerId: string): Promise<RoomRow> {
    const { data, error } = await supabaseAdmin
      .from('rooms')
      .update({ guest_player_id: guestPlayerId, current_player_count: 2, status: 'active', started_at: new Date().toISOString() })
      .eq('id', roomId)
      .eq('status', 'waiting')
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to attach guest to room', { error: error?.message, roomId });
      throw new AppError('ROOM_FULL', 'This room is no longer available to join.');
    }
    return data as RoomRow;
  },

  async createGameForRoom(room: RoomRow): Promise<GameRow> {
    const initialMs = room.initial_time_seconds * 1000;
    const { data, error } = await supabaseAdmin
      .from('games')
      .insert({
        room_id: room.id,
        game_mode: 'online_friend',
        white_player_id: room.host_color === 'white' ? room.host_player_id : room.guest_player_id,
        black_player_id: room.host_color === 'black' ? room.host_player_id : room.guest_player_id,
        status: 'in_progress',
        time_control_category: room.time_control_category,
        white_time_remaining_ms: initialMs,
        black_time_remaining_ms: initialMs,
        increment_seconds: room.increment_seconds,
        started_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to create game for room', { error: error?.message, roomId: room.id });
      throw new AppError('DATABASE_ERROR', 'Could not start the game.');
    }
    return data as GameRow;
  },

  async findGameByRoomId(roomId: string): Promise<GameRow | null> {
    const { data, error } = await supabaseAdmin
      .from('games')
      .select('*')
      .eq('room_id', roomId)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) {
      logger.error('database', 'Failed to look up game for room', { error: error.message, roomId });
      throw new AppError('DATABASE_ERROR', 'Could not look up the game.');
    }
    return (data as GameRow) ?? null;
  },

  async touchActivity(roomId: string): Promise<void> {
    const { error } = await supabaseAdmin.rpc('touch_room_activity', { p_room_id: roomId });
    if (error) {
      logger.warn('database', 'Failed to touch room activity', { error: error.message, roomId });
    }
  },

  async markConnection(roomId: string, isHost: boolean, status: 'connected' | 'disconnected' | 'reconnecting'): Promise<void> {
    const column = isHost ? 'host_connection' : 'guest_connection';
    const { error } = await supabaseAdmin.from('rooms').update({ [column]: status }).eq('id', roomId);
    if (error) {
      logger.warn('database', 'Failed to update connection status', { error: error.message, roomId });
    }
  },
};
