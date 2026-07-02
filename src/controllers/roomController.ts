import type { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { roomService } from '../services/roomService.js';
import { AppError } from '../errors/AppError.js';
import type { RoomRow } from '../types/database.types.js';

const createRoomSchema = z.object({
  displayName: z.string().min(1).max(40),
  timeControl: z.object({
    category: z.enum(['bullet', 'blitz', 'rapid', 'classical', 'unlimited']),
    initialSeconds: z.number().int().min(0).max(7200),
    incrementSeconds: z.number().int().min(0).max(60),
  }),
  boardTheme: z.string().max(40).default('classic'),
  pieceTheme: z.string().max(40).default('classic'),
});

const joinRoomSchema = z.object({
  displayName: z.string().min(1).max(40),
});

function serializeRoom(room: RoomRow) {
  return {
    id: room.id,
    roomCode: room.room_code,
    status: room.status,
    hostPlayerId: room.host_player_id,
    guestPlayerId: room.guest_player_id,
    hostColor: room.host_color,
    timeControl: {
      category: room.time_control_category,
      initialSeconds: room.initial_time_seconds,
      incrementSeconds: room.increment_seconds,
    },
    boardTheme: room.board_theme,
    pieceTheme: room.piece_theme,
    createdAt: room.created_at,
    expiresAt: room.expires_at,
  };
}

export const roomController = {
  async create(req: Request, res: Response, next: NextFunction) {
    try {
      const parsed = createRoomSchema.safeParse(req.body);
      if (!parsed.success) {
        throw new AppError('VALIDATION_ERROR', 'Invalid request body.', parsed.error.flatten());
      }
      const body = parsed.data;

      const result = await roomService.createRoom({
        displayName: body.displayName,
        timeControlCategory: body.timeControl.category,
        initialTimeSeconds: body.timeControl.initialSeconds,
        incrementSeconds: body.timeControl.incrementSeconds,
        boardTheme: body.boardTheme,
        pieceTheme: body.pieceTheme,
        ipHash: req.rateLimitKey,
        userAgent: req.headers['user-agent'],
      });

      res.status(201).json({
        success: true,
        data: {
          ...serializeRoom(result.room),
          playerId: result.playerId,
          playerSessionToken: result.sessionToken,
        },
      });
    } catch (err) {
      next(err);
    }
  },

  async join(req: Request, res: Response, next: NextFunction) {
    try {
      const { roomCode } = req.params;
      const parsed = joinRoomSchema.safeParse(req.body);
      if (!parsed.success) {
        throw new AppError('VALIDATION_ERROR', 'Invalid request body.', parsed.error.flatten());
      }

      const result = await roomService.joinRoom(roomCode, parsed.data.displayName, req.rateLimitKey, req.headers['user-agent']);

      res.status(200).json({
        success: true,
        data: {
          ...serializeRoom(result.room),
          playerId: result.playerId,
          playerSessionToken: result.sessionToken,
          gameId: result.gameId,
        },
      });
    } catch (err) {
      next(err);
    }
  },

  async getByCode(req: Request, res: Response, next: NextFunction) {
    try {
      const room = await roomService.getRoomByCode(req.params.roomCode);
      res.status(200).json({ success: true, data: serializeRoom(room) });
    } catch (err) {
      next(err);
    }
  },

  async reconnect(req: Request, res: Response, next: NextFunction) {
    try {
      const { roomId } = req.params;
      const playerId = req.playerId;
      if (!playerId) throw new AppError('UNAUTHORIZED_SESSION', 'Missing or invalid session token.');

      const result = await roomService.reconnect(roomId, playerId);
      res.status(200).json({ success: true, data: { ...serializeRoom(result.room), gameId: result.gameId } });
    } catch (err) {
      next(err);
    }
  },
};
