import { gameRepository } from '../repositories/gameRepository.js';
import { applyMove } from '../validators/chess.validator.js';
import { AppError } from '../errors/AppError.js';
import { logger } from '../utils/logger.js';
import type { GameRow } from '../types/database.types.js';

export interface MakeMoveParams {
  gameId: string;
  playerId: string;
  from: string;
  to: string;
  promotion?: string;
  clientMoveId?: string;
}

function computeStatusAndResult(applied: ReturnType<typeof applyMove>, game: GameRow): {
  status: string;
  result: string;
  winnerPlayerId: string | null;
  endReason: string | null;
} {
  if (applied.isCheckmate) {
    // The side who just moved delivered mate; turnAfter is the loser's color.
    const winnerColor = applied.turnAfter === 'white' ? 'black' : 'white';
    const winnerPlayerId = winnerColor === 'white' ? game.white_player_id : game.black_player_id;
    return { status: 'checkmate', result: `${winnerColor}_win`, winnerPlayerId, endReason: 'Checkmate' };
  }
  if (applied.isStalemate) return { status: 'stalemate', result: 'draw', winnerPlayerId: null, endReason: 'Stalemate' };
  if (applied.isThreefoldRepetition) return { status: 'draw_repetition', result: 'draw', winnerPlayerId: null, endReason: 'Threefold repetition' };
  if (applied.isInsufficientMaterial) return { status: 'draw_insufficient_material', result: 'draw', winnerPlayerId: null, endReason: 'Insufficient material' };
  if (applied.isDraw) return { status: 'draw_fifty_move', result: 'draw', winnerPlayerId: null, endReason: 'Fifty-move rule' };
  return { status: 'in_progress', result: 'ongoing', winnerPlayerId: null, endReason: null };
}

export const gameService = {
  async makeMove(params: MakeMoveParams) {
    const game = await gameRepository.findGameById(params.gameId);
    if (!game) throw new AppError('GAME_NOT_FOUND', 'Game not found.');
    if (game.status !== 'in_progress') throw new AppError('GAME_NOT_IN_PROGRESS', 'This game has already ended.');

    const isWhite = game.white_player_id === params.playerId;
    const isBlack = game.black_player_id === params.playerId;
    if (!isWhite && !isBlack) throw new AppError('NOT_A_PLAYER_IN_GAME', 'You are not a player in this game.');

    const moverColor: 'white' | 'black' = isWhite ? 'white' : 'black';
    if (game.turn !== moverColor) throw new AppError('NOT_YOUR_TURN', "It's not your turn.");

    // Idempotency: if this exact client move was already applied (e.g. a
    // retried request after a flaky connection), return the prior result
    // instead of re-validating and double-applying it.
    if (params.clientMoveId) {
      const existing = await gameRepository.findExistingMoveByClientId(params.gameId, params.clientMoveId);
      if (existing) {
        logger.info('move', 'Duplicate move request short-circuited', { gameId: params.gameId, clientMoveId: params.clientMoveId });
        return {
          san: existing.san,
          fenAfter: existing.fen_after,
          isCheck: existing.is_check,
          isCheckmate: existing.is_checkmate,
          isStalemate: false,
          isDraw: false,
          gameStatus: game.status,
          gameResult: game.result,
          whiteTimeRemainingMs: existing.white_time_remaining_ms,
          blackTimeRemainingMs: existing.black_time_remaining_ms,
        };
      }
    }

    // THE authoritative legality check — never trust the client.
    const applied = applyMove({ fen: game.fen, from: params.from, to: params.to, promotion: params.promotion });

    const statusInfo = computeStatusAndResult(applied, game);
    const plyNumber = game.move_count + 1;

    const capturedWhite = [...game.captured_white_pieces];
    const capturedBlack = [...game.captured_black_pieces];
    if (applied.capturedPiece) {
      if (moverColor === 'white') capturedWhite.push(applied.capturedPiece);
      else capturedBlack.push(applied.capturedPiece);
    }

    // Increment applies to the player who just moved.
    const incrementMs = game.increment_seconds * 1000;
    const whiteTimeRemainingMs = moverColor === 'white' ? game.white_time_remaining_ms + incrementMs : game.white_time_remaining_ms;
    const blackTimeRemainingMs = moverColor === 'black' ? game.black_time_remaining_ms + incrementMs : game.black_time_remaining_ms;

    await gameRepository.insertMove({
      gameId: params.gameId,
      playerId: params.playerId,
      plyNumber,
      fullmoveNumber: applied.fullmoveNumber,
      color: moverColor,
      san: applied.san,
      uci: applied.uci,
      fromSquare: applied.fromSquare,
      toSquare: applied.toSquare,
      piece: applied.piece,
      capturedPiece: applied.capturedPiece,
      promotionPiece: applied.promotionPiece,
      moveType: applied.moveType,
      fenBefore: applied.fenBefore,
      fenAfter: applied.fenAfter,
      isCheck: applied.isCheck,
      isCheckmate: applied.isCheckmate,
      whiteTimeRemainingMs,
      blackTimeRemainingMs,
      thinkTimeMs: 0,
      clientMoveId: params.clientMoveId ?? null,
    });

    await gameRepository.updateGameAfterMove(params.gameId, {
      fen: applied.fenAfter,
      pgn: applied.pgn,
      turn: applied.turnAfter,
      fullmoveNumber: applied.fullmoveNumber,
      halfmoveClock: applied.halfmoveClock,
      isCheck: applied.isCheck,
      isCheckmate: applied.isCheckmate,
      isStalemate: applied.isStalemate,
      isDraw: applied.isDraw,
      isThreefoldRepetition: applied.isThreefoldRepetition,
      isInsufficientMaterial: applied.isInsufficientMaterial,
      status: statusInfo.status,
      result: statusInfo.result,
      winnerPlayerId: statusInfo.winnerPlayerId,
      endReason: statusInfo.endReason,
      whiteTimeRemainingMs,
      blackTimeRemainingMs,
      moveCount: plyNumber,
      capturedWhitePieces: capturedWhite,
      capturedBlackPieces: capturedBlack,
    });

    if (statusInfo.status !== 'in_progress') {
      await gameRepository.recordGameResult(params.gameId);
    }

    logger.info('move', 'Move applied', { gameId: params.gameId, san: applied.san, ply: plyNumber });

    return {
      san: applied.san,
      fenAfter: applied.fenAfter,
      isCheck: applied.isCheck,
      isCheckmate: applied.isCheckmate,
      isStalemate: applied.isStalemate,
      isDraw: applied.isDraw,
      gameStatus: statusInfo.status,
      gameResult: statusInfo.result,
      whiteTimeRemainingMs,
      blackTimeRemainingMs,
    };
  },

  async resign(gameId: string, playerId: string) {
    const game = await gameRepository.findGameById(gameId);
    if (!game) throw new AppError('GAME_NOT_FOUND', 'Game not found.');
    if (game.status !== 'in_progress') throw new AppError('GAME_NOT_IN_PROGRESS', 'This game has already ended.');

    const isWhite = game.white_player_id === playerId;
    const isBlack = game.black_player_id === playerId;
    if (!isWhite && !isBlack) throw new AppError('NOT_A_PLAYER_IN_GAME', 'You are not a player in this game.');

    const resignedColor = isWhite ? 'white' : 'black';
    const winnerColor = isWhite ? 'black' : 'white';
    const winnerPlayerId = winnerColor === 'white' ? game.white_player_id : game.black_player_id;

    await gameRepository.setGameTerminal(gameId, {
      status: 'resigned',
      result: `${winnerColor}_win`,
      winnerPlayerId,
      endReason: `${resignedColor === 'white' ? 'White' : 'Black'} resigned`,
    });
    await gameRepository.recordGameResult(gameId);

    logger.info('room', 'Player resigned', { gameId, playerId });
  },

  async declareTimeout(gameId: string, loserColor: 'white' | 'black') {
    const game = await gameRepository.findGameById(gameId);
    if (!game) throw new AppError('GAME_NOT_FOUND', 'Game not found.');
    if (game.status !== 'in_progress') return; // already terminal, nothing to do

    const winnerColor = loserColor === 'white' ? 'black' : 'white';
    const winnerPlayerId = winnerColor === 'white' ? game.white_player_id : game.black_player_id;

    await gameRepository.setGameTerminal(gameId, {
      status: 'timeout',
      result: `${winnerColor}_win`,
      winnerPlayerId,
      endReason: `${loserColor === 'white' ? 'White' : 'Black'} ran out of time`,
    });
    await gameRepository.recordGameResult(gameId);
  },
};
