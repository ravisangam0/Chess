import { Router } from 'express';
import { gameController } from '../controllers/gameController.js';
import { resolveSession, requireSession } from '../middleware/sessionAuth.js';
import { rateLimit } from '../middleware/rateLimit.js';
import { env } from '../config/env.js';

export const gameRoutes = Router();

gameRoutes.use(resolveSession);

gameRoutes.post(
  '/:gameId/moves',
  requireSession,
  rateLimit(env.RATE_LIMIT_MOVE_PER_SEC, 1_000),
  gameController.makeMove,
);

gameRoutes.post('/:gameId/resign', requireSession, gameController.resign);
gameRoutes.post('/:gameId/draw-offer', requireSession, gameController.offerDraw);
gameRoutes.post('/:gameId/draw-response', requireSession, gameController.respondToDraw);
gameRoutes.post('/:gameId/rematch', requireSession, gameController.requestRematch);
