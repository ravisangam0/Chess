import { roomRepository } from '../repositories/roomRepository.js';
import { AppError } from '../errors/AppError.js';
import { logger } from '../utils/logger.js';
import { ROOM_CODE_REGEX } from '../constants/index.js';
import type { RoomRow } from '../types/database.types.js';
import type { TimeControlCategory } from '../types/database.types.js';

export interface CreateRoomParams {
  displayName: string;
  timeControlCategory: TimeControlCategory;
  initialTimeSeconds: number;
  incrementSeconds: number;
  boardTheme: string;
  pieceTheme: string;
  ipHash?: string;
  userAgent?: string;
}

export interface RoomWithSession {
  room: RoomRow;
  playerId: string;
  sessionToken: string;
}

function sanitizeDisplayName(name: string): string {
  const trimmed = (name ?? '').trim().slice(0, 40);
  return trimmed.length > 0 ? trimmed : 'Guest';
}

export const roomService = {
  async createRoom(params: CreateRoomParams): Promise<RoomWithSession> {
    const displayName = sanitizeDisplayName(params.displayName);

    const player = await roomRepository.createPlayer(displayName, params.ipHash, params.userAgent);
    const roomCode = await roomRepository.generateRoomCode();

    const hostColor: 'white' | 'black' = Math.random() < 0.5 ? 'white' : 'black';

    const room = await roomRepository.createRoom({
      roomCode,
      hostPlayerId: player.id,
      timeControlCategory: params.timeControlCategory,
      initialTimeSeconds: params.initialTimeSeconds,
      incrementSeconds: params.incrementSeconds,
      boardTheme: params.boardTheme,
      pieceTheme: params.pieceTheme,
      hostColor,
    });

    logger.info('room', 'Room created', { roomId: room.id, playerId: player.id, roomCode: room.room_code });

    return { room, playerId: player.id, sessionToken: player.session_token };
  },

  async joinRoom(roomCode: string, displayName: string, ipHash?: string, userAgent?: string): Promise<RoomWithSession & { gameId: string }> {
    const normalizedCode = roomCode.trim().toUpperCase();
    if (!ROOM_CODE_REGEX.test(normalizedCode)) {
      throw new AppError('ROOM_CODE_INVALID', 'That room code is not valid.');
    }

    const existingRoom = await roomRepository.findRoomByCode(normalizedCode);
    if (!existingRoom) {
      throw new AppError('ROOM_NOT_FOUND', 'No room found with that code.');
    }
    if (existingRoom.status !== 'waiting') {
      throw new AppError('ROOM_FULL', 'This room already has two players.');
    }
    if (new Date(existingRoom.expires_at).getTime() < Date.now()) {
      throw new AppError('ROOM_EXPIRED', 'This room has expired.');
    }

    const guestName = sanitizeDisplayName(displayName);
    const guest = await roomRepository.createPlayer(guestName, ipHash, userAgent);

    const activeRoom = await roomRepository.attachGuest(existingRoom.id, guest.id);
    const game = await roomRepository.createGameForRoom(activeRoom);

    logger.info('room', 'Player joined room', { roomId: activeRoom.id, playerId: guest.id, gameId: game.id });

    return { room: activeRoom, playerId: guest.id, sessionToken: guest.session_token, gameId: game.id };
  },

  async getRoomByCode(roomCode: string): Promise<RoomRow> {
    const room = await roomRepository.findRoomByCode(roomCode.trim().toUpperCase());
    if (!room) throw new AppError('ROOM_NOT_FOUND', 'No room found with that code.');
    return room;
  },

  async getRoomById(roomId: string): Promise<RoomRow> {
    const room = await roomRepository.findRoomById(roomId);
    if (!room) throw new AppError('ROOM_NOT_FOUND', 'Room not found.');
    return room;
  },

  async reconnect(roomId: string, playerId: string): Promise<{ room: RoomRow; gameId: string | null }> {
    const room = await roomRepository.findRoomById(roomId);
    if (!room) throw new AppError('ROOM_NOT_FOUND', 'Room not found.');
    if (room.status === 'expired' || room.status === 'abandoned') {
      throw new AppError('ROOM_EXPIRED', 'This room is no longer available.');
    }

    const isHost = room.host_player_id === playerId;
    const isGuest = room.guest_player_id === playerId;
    if (!isHost && !isGuest) {
      throw new AppError('NOT_A_PLAYER_IN_GAME', 'You are not a player in this room.');
    }

    await roomRepository.markConnection(roomId, isHost, 'connected');
    await roomRepository.touchActivity(roomId);

    const game = await roomRepository.findGameByRoomId(roomId);
    return { room, gameId: game?.id ?? null };
  },
};
