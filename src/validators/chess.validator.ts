import { Chess } from 'chess.js';
import { AppError } from '../errors/AppError.js';
import { PROMOTION_PIECES, STARTING_FEN } from '../constants/index.js';
import type { PlayerColor } from '../types/database.types.js';

export interface AppliedMove {
  san: string;
  uci: string;
  fromSquare: string;
  toSquare: string;
  piece: string;
  capturedPiece: string | null;
  promotionPiece: string | null;
  moveType: 'normal' | 'capture' | 'castle_kingside' | 'castle_queenside' | 'en_passant' | 'promotion';
  fenBefore: string;
  fenAfter: string;
  pgn: string;
  isCheck: boolean;
  isCheckmate: boolean;
  isStalemate: boolean;
  isDraw: boolean;
  isThreefoldRepetition: boolean;
  isInsufficientMaterial: boolean;
  turnAfter: PlayerColor;
  fullmoveNumber: number;
  halfmoveClock: number;
}

function colorFromChessJs(c: 'w' | 'b'): PlayerColor {
  return c === 'w' ? 'white' : 'black';
}

function classifyMoveType(flags: string): AppliedMove['moveType'] {
  // chess.js flag chars: n(normal) b(big pawn) e(en passant) c(capture)
  // p(promotion) k(kingside castle) q(queenside castle)
  if (flags.includes('k')) return 'castle_kingside';
  if (flags.includes('q')) return 'castle_queenside';
  if (flags.includes('e')) return 'en_passant';
  if (flags.includes('p')) return 'promotion';
  if (flags.includes('c')) return 'capture';
  return 'normal';
}

/**
 * Loads a position from FEN, validates the FEN is well-formed, and returns
 * a chess.js instance. Throws AppError(VALIDATION_ERROR) on malformed FEN —
 * never trust a FEN pulled from the DB or client without re-validating here.
 */
export function loadPosition(fen: string): Chess {
  try {
    return new Chess(fen);
  } catch (err) {
    throw new AppError('VALIDATION_ERROR', `Malformed FEN: ${(err as Error).message}`, { fen });
  }
}

export function createNewGamePosition(): Chess {
  return new Chess(STARTING_FEN);
}

export interface ApplyMoveParams {
  fen: string;
  from: string;
  to: string;
  promotion?: string;
}

/**
 * The single authoritative move-legality gate. Never trust frontend-supplied
 * legality; this function re-derives everything (check/mate/stalemate/draw)
 * from chess.js after applying the move server-side.
 */
export function applyMove(params: ApplyMoveParams): AppliedMove {
  const { fen, from, to, promotion } = params;
  const chess = loadPosition(fen);

  if (promotion && !PROMOTION_PIECES.includes(promotion as (typeof PROMOTION_PIECES)[number])) {
    throw new AppError('INVALID_PROMOTION_PIECE', `Invalid promotion piece: ${promotion}`);
  }

  // Detect "promotion required but not supplied": a pawn move to the back
  // rank without a promotion piece is illegal in chess.js and will throw,
  // but we want a clearer error code for the client in that specific case.
  const pieceBefore = chess.get(from as never);
  const isPawnToBackRank =
    pieceBefore?.type === 'p' &&
    ((pieceBefore.color === 'w' && to.endsWith('8')) || (pieceBefore.color === 'b' && to.endsWith('1')));
  if (isPawnToBackRank && !promotion) {
    throw new AppError('PROMOTION_REQUIRED', 'A promotion piece must be specified for this move.');
  }

  const fenBefore = chess.fen();
  let moveResult;
  try {
    moveResult = chess.move({ from, to, promotion: promotion as 'q' | 'r' | 'b' | 'n' | undefined });
  } catch (err) {
    throw new AppError('ILLEGAL_MOVE', `Illegal move ${from}-${to}: ${(err as Error).message}`, { from, to, promotion });
  }

  if (!moveResult) {
    throw new AppError('ILLEGAL_MOVE', `Illegal move ${from}-${to}`, { from, to, promotion });
  }

  const fenAfter = chess.fen();
  const fenParts = fenAfter.split(' ');
  const halfmoveClock = Number(fenParts[4] ?? 0);
  const fullmoveNumber = Number(fenParts[5] ?? 1);

  return {
    san: moveResult.san,
    uci: `${moveResult.from}${moveResult.to}${moveResult.promotion ?? ''}`,
    fromSquare: moveResult.from,
    toSquare: moveResult.to,
    piece: moveResult.piece,
    capturedPiece: moveResult.captured ?? null,
    promotionPiece: moveResult.promotion ?? null,
    moveType: classifyMoveType(moveResult.flags),
    fenBefore,
    fenAfter,
    pgn: chess.pgn(),
    isCheck: chess.isCheck(),
    isCheckmate: chess.isCheckmate(),
    isStalemate: chess.isStalemate(),
    isDraw: chess.isDraw(),
    isThreefoldRepetition: chess.isThreefoldRepetition(),
    isInsufficientMaterial: chess.isInsufficientMaterial(),
    turnAfter: colorFromChessJs(chess.turn()),
    fullmoveNumber,
    halfmoveClock,
  };
}

export function getLegalMoves(fen: string, square?: string): string[] {
  const chess = loadPosition(fen);
  const moves = chess.moves({ square: square as never, verbose: true });
  return moves.map((m) => `${m.from}${m.to}${m.promotion ?? ''}`);
}

export function isMoverTurn(fen: string, color: PlayerColor): boolean {
  const chess = loadPosition(fen);
  return colorFromChessJs(chess.turn()) === color;
}

export function isGameOverPosition(fen: string): boolean {
  const chess = loadPosition(fen);
  return chess.isGameOver();
}
