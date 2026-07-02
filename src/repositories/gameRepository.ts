import { supabaseAdmin } from '../config/supabase.js';
import { AppError } from '../errors/AppError.js';
import { logger } from '../utils/logger.js';
import type { GameRow, MoveRow } from '../types/database.types.js';

export const gameRepository = {
  async findGameById(gameId: string): Promise<GameRow | null> {
    const { data, error } = await supabaseAdmin.from('games').select('*').eq('id', gameId).maybeSingle();
    if (error) {
      logger.error('database', 'Failed to look up game', { error: error.message, gameId });
      throw new AppError('DATABASE_ERROR', 'Could not look up the game.');
    }
    return (data as GameRow) ?? null;
  },

  async findExistingMoveByClientId(gameId: string, clientMoveId: string): Promise<MoveRow | null> {
    const { data, error } = await supabaseAdmin
      .from('moves')
      .select('*')
      .eq('game_id', gameId)
      .eq('client_move_id', clientMoveId)
      .maybeSingle();
    if (error) {
      logger.warn('database', 'Failed to check for duplicate move', { error: error.message, gameId });
      return null;
    }
    return (data as MoveRow) ?? null;
  },

  async insertMove(params: {
    gameId: string;
    playerId: string;
    plyNumber: number;
    fullmoveNumber: number;
    color: 'white' | 'black';
    san: string;
    uci: string;
    fromSquare: string;
    toSquare: string;
    piece: string;
    capturedPiece: string | null;
    promotionPiece: string | null;
    moveType: string;
    fenBefore: string;
    fenAfter: string;
    isCheck: boolean;
    isCheckmate: boolean;
    whiteTimeRemainingMs: number;
    blackTimeRemainingMs: number;
    thinkTimeMs: number;
    clientMoveId: string | null;
  }): Promise<MoveRow> {
    const { data, error } = await supabaseAdmin
      .from('moves')
      .insert({
        game_id: params.gameId,
        player_id: params.playerId,
        ply_number: params.plyNumber,
        fullmove_number: params.fullmoveNumber,
        color: params.color,
        san: params.san,
        uci: params.uci,
        from_square: params.fromSquare,
        to_square: params.toSquare,
        piece: params.piece,
        captured_piece: params.capturedPiece,
        promotion_piece: params.promotionPiece,
        move_type: params.moveType as never,
        fen_before: params.fenBefore,
        fen_after: params.fenAfter,
        is_check: params.isCheck,
        is_checkmate: params.isCheckmate,
        white_time_remaining_ms: params.whiteTimeRemainingMs,
        black_time_remaining_ms: params.blackTimeRemainingMs,
        think_time_ms: params.thinkTimeMs,
        client_move_id: params.clientMoveId,
      })
      .select()
      .single();

    if (error || !data) {
      // Unique violation on (game_id, client_move_id) means a retried
      // request raced us — treat as non-fatal, caller re-fetches by client id.
      if (error?.code === '23505') {
        throw new AppError('DUPLICATE_MOVE', 'This move was already submitted.');
      }
      logger.error('database', 'Failed to insert move', { error: error?.message, gameId: params.gameId });
      throw new AppError('DATABASE_ERROR', 'Could not save the move.');
    }
    return data as MoveRow;
  },

  async updateGameAfterMove(gameId: string, params: {
    fen: string;
    pgn: string;
    turn: 'white' | 'black';
    fullmoveNumber: number;
    halfmoveClock: number;
    isCheck: boolean;
    isCheckmate: boolean;
    isStalemate: boolean;
    isDraw: boolean;
    isThreefoldRepetition: boolean;
    isInsufficientMaterial: boolean;
    status: string;
    result: string;
    winnerPlayerId: string | null;
    endReason: string | null;
    whiteTimeRemainingMs: number;
    blackTimeRemainingMs: number;
    moveCount: number;
    capturedWhitePieces: string[];
    capturedBlackPieces: string[];
  }): Promise<GameRow> {
    const isTerminal = params.status !== 'in_progress';
    const { data, error } = await supabaseAdmin
      .from('games')
      .update({
        fen: params.fen,
        pgn: params.pgn,
        turn: params.turn,
        fullmove_number: params.fullmoveNumber,
        halfmove_clock: params.halfmoveClock,
        is_check: params.isCheck,
        is_checkmate: params.isCheckmate,
        is_stalemate: params.isStalemate,
        is_draw: params.isDraw,
        is_threefold_repetition: params.isThreefoldRepetition,
        is_insufficient_material: params.isInsufficientMaterial,
        status: params.status as never,
        result: params.result as never,
        winner_player_id: params.winnerPlayerId,
        end_reason: params.endReason,
        white_time_remaining_ms: params.whiteTimeRemainingMs,
        black_time_remaining_ms: params.blackTimeRemainingMs,
        move_count: params.moveCount,
        captured_white_pieces: params.capturedWhitePieces,
        captured_black_pieces: params.capturedBlackPieces,
        last_move_at: new Date().toISOString(),
        ...(isTerminal ? { ended_at: new Date().toISOString() } : {}),
      })
      .eq('id', gameId)
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to update game after move', { error: error?.message, gameId });
      throw new AppError('DATABASE_ERROR', 'Could not update the game.');
    }
    return data as GameRow;
  },

  async recordGameResult(gameId: string): Promise<void> {
    const { error } = await supabaseAdmin.rpc('record_game_result', { p_game_id: gameId });
    if (error) {
      logger.error('database', 'Failed to record game result stats', { error: error.message, gameId });
      // Non-fatal to the player-facing response — stats rollup failing
      // shouldn't block the game from ending correctly for the players.
    }
  },

  async setGameTerminal(gameId: string, params: {
    status: string;
    result: string;
    winnerPlayerId: string | null;
    endReason: string;
  }): Promise<GameRow> {
    const { data, error } = await supabaseAdmin
      .from('games')
      .update({
        status: params.status as never,
        result: params.result as never,
        winner_player_id: params.winnerPlayerId,
        end_reason: params.endReason,
        ended_at: new Date().toISOString(),
      })
      .eq('id', gameId)
      .eq('status', 'in_progress')
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to set game terminal state', { error: error?.message, gameId });
      throw new AppError('GAME_ALREADY_FINISHED', 'This game has already ended.');
    }
    return data as GameRow;
  },
};
