import { Router } from 'express';
import { roomController } from '../controllers/roomController.js';
import { rateLimit } from '../middleware/rateLimit.js';
import { resolveSession } from '../middleware/sessionAuth.js';
import { env } from '../config/env.js';

export const roomRoutes = Router();

roomRoutes.post(
  '/',
  rateLimit(env.RATE_LIMIT_ROOM_CREATE_PER_MIN, 60_000),
  roomController.create,
);

roomRoutes.post(
  '/:roomCode/join',
  rateLimit(env.RATE_LIMIT_JOIN_PER_MIN, 60_000),
  roomController.join,
);

roomRoutes.get('/:roomCode', roomController.getByCode);

roomRoutes.post('/:roomId/reconnect', resolveSession, roomController.reconnect);
