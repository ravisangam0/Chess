export type ErrorCode =
  | 'ROOM_NOT_FOUND'
  | 'ROOM_EXPIRED'
  | 'ROOM_FULL'
  | 'ROOM_CODE_INVALID'
  | 'ROOM_ALREADY_JOINED'
  | 'GAME_NOT_FOUND'
  | 'GAME_NOT_IN_PROGRESS'
  | 'GAME_ALREADY_FINISHED'
  | 'ILLEGAL_MOVE'
  | 'NOT_YOUR_TURN'
  | 'NOT_A_PLAYER_IN_GAME'
  | 'DUPLICATE_MOVE'
  | 'PROMOTION_REQUIRED'
  | 'INVALID_PROMOTION_PIECE'
  | 'DRAW_REQUEST_ALREADY_PENDING'
  | 'DRAW_REQUEST_NOT_FOUND'
  | 'TIMER_EXPIRED'
  | 'VALIDATION_ERROR'
  | 'RATE_LIMITED'
  | 'UNAUTHORIZED_SESSION'
  | 'AI_ENGINE_ERROR'
  | 'AI_TIMEOUT'
  | 'DATABASE_ERROR'
  | 'REALTIME_ERROR'
  | 'MAINTENANCE_MODE'
  | 'INTERNAL_ERROR';

const STATUS_BY_CODE: Record<ErrorCode, number> = {
  ROOM_NOT_FOUND: 404,
  ROOM_EXPIRED: 410,
  ROOM_FULL: 409,
  ROOM_CODE_INVALID: 400,
  ROOM_ALREADY_JOINED: 409,
  GAME_NOT_FOUND: 404,
  GAME_NOT_IN_PROGRESS: 409,
  GAME_ALREADY_FINISHED: 409,
  ILLEGAL_MOVE: 422,
  NOT_YOUR_TURN: 403,
  NOT_A_PLAYER_IN_GAME: 403,
  DUPLICATE_MOVE: 409,
  PROMOTION_REQUIRED: 422,
  INVALID_PROMOTION_PIECE: 422,
  DRAW_REQUEST_ALREADY_PENDING: 409,
  DRAW_REQUEST_NOT_FOUND: 404,
  TIMER_EXPIRED: 410,
  VALIDATION_ERROR: 400,
  RATE_LIMITED: 429,
  UNAUTHORIZED_SESSION: 401,
  AI_ENGINE_ERROR: 502,
  AI_TIMEOUT: 504,
  DATABASE_ERROR: 500,
  REALTIME_ERROR: 500,
  MAINTENANCE_MODE: 503,
  INTERNAL_ERROR: 500,
};

export class AppError extends Error {
  readonly code: ErrorCode;
  readonly httpStatus: number;
  readonly details?: unknown;
  readonly isOperational: boolean;

  constructor(code: ErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.httpStatus = STATUS_BY_CODE[code];
    this.details = details;
    this.isOperational = true;
    Error.captureStackTrace?.(this, AppError);
  }

  toJSON() {
    return {
      success: false as const,
      error: { code: this.code, message: this.message, details: this.details },
    };
  }
}

export function isAppError(err: unknown): err is AppError {
  return err instanceof AppError;
}
