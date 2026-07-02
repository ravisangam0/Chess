import type { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { gameService } from '../services/gameService.js';
import { gameRepository } from '../repositories/gameRepository.js';
import { drawRepository } from '../repositories/drawRepository.js';
import { rematchRepository } from '../repositories/rematchRepository.js';
import { AppError } from '../errors/AppError.js';

const moveSchema = z.object({
  from: z.string().regex(/^[a-h][1-8]$/),
  to: z.string().regex(/^[a-h][1-8]$/),
  promotion: z.enum(['q', 'r', 'b', 'n']).optional(),
  clientMoveId: z.string().uuid().optional(),
});

function requirePlayer(req: Request): string {
  if (!req.playerId) throw new AppError('UNAUTHORIZED_SESSION', 'A valid session token is required.');
  return req.playerId;
}

export const gameController = {
  async makeMove(req: Request, res: Response, next: NextFunction) {
    try {
      const playerId = requirePlayer(req);
      const parsed = moveSchema.safeParse(req.body);
      if (!parsed.success) throw new AppError('VALIDATION_ERROR', 'Invalid move payload.', parsed.error.flatten());

      const result = await gameService.makeMove({
        gameId: req.params.gameId,
        playerId,
        from: parsed.data.from,
        to: parsed.data.to,
        promotion: parsed.data.promotion,
        clientMoveId: parsed.data.clientMoveId,
      });

      res.status(200).json({ success: true, data: result });
    } catch (err) {
      next(err);
    }
  },

  async resign(req: Request, res: Response, next: NextFunction) {
    try {
      const playerId = requirePlayer(req);
      await gameService.resign(req.params.gameId, playerId);
      res.status(200).json({ success: true, data: null });
    } catch (err) {
      next(err);
    }
  },

  async offerDraw(req: Request, res: Response, next: NextFunction) {
    try {
      const playerId = requirePlayer(req);
      const game = await gameRepository.findGameById(req.params.gameId);
      if (!game) throw new AppError('GAME_NOT_FOUND', 'Game not found.');
      if (game.status !== 'in_progress') throw new AppError('GAME_NOT_IN_PROGRESS', 'This game has already ended.');

      const offer = await drawRepository.createOffer(req.params.gameId, playerId);
      res.status(201).json({ success: true, data: { id: offer.id, status: offer.status } });
    } catch (err) {
      next(err);
    }
  },

  async respondToDraw(req: Request, res: Response, next: NextFunction) {
    try {
      requirePlayer(req);
      const accept = Boolean(req.body?.accept);
      const pending = await drawRepository.findPendingByGame(req.params.gameId);
      if (!pending) throw new AppError('DRAW_REQUEST_NOT_FOUND', 'No pending draw offer for this game.');

      await drawRepository.resolve(pending.id, accept ? 'accepted' : 'declined');

      if (accept) {
        await gameRepository.setGameTerminal(req.params.gameId, {
          status: 'draw_agreement',
          result: 'draw',
          winnerPlayerId: null,
          endReason: 'Draw agreed',
        });
        await gameRepository.recordGameResult(req.params.gameId);
      }

      res.status(200).json({ success: true, data: { accepted: accept } });
    } catch (err) {
      next(err);
    }
  },

  async requestRematch(req: Request, res: Response, next: NextFunction) {
    try {
      const playerId = requirePlayer(req);
      const found = await rematchRepository.findRoomForGame(req.params.gameId);
      if (!found) throw new AppError('GAME_NOT_FOUND', 'Game not found.');

      const { game, room } = found;
      const isPlayerInGame = game.white_player_id === playerId || game.black_player_id === playerId;
      if (!isPlayerInGame) throw new AppError('NOT_A_PLAYER_IN_GAME', 'You are not a player in this game.');
      if (game.status === 'in_progress') throw new AppError('GAME_NOT_IN_PROGRESS', 'The current game has not finished yet.');

      const newGame = await rematchRepository.createRematchGame(game, room);
      res.status(201).json({ success: true, data: { newGameId: newGame.id } });
    } catch (err) {
      next(err);
    }
  },
};
