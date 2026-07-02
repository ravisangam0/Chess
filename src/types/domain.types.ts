import type {
  PlayerColor, RoomStatus, GameStatus, GameResult, AiDifficulty,
  TimeControlCategory, GameMode,
} from './database.types.js';

export interface SessionContext {
  playerId: string;
  sessionToken: string;
  displayName: string;
}

export interface CreateRoomInput {
  hostPlayerId: string;
  hostDisplayName: string;
  timeControlCategory: TimeControlCategory;
  initialTimeSeconds: number;
  incrementSeconds: number;
  delaySeconds?: number;
  boardTheme?: string;
  pieceTheme?: string;
  hostColorPreference?: PlayerColor | 'random';
}

export interface JoinRoomInput {
  roomCode: string;
  playerId: string;
  displayName: string;
}

export interface RoomSummaryDTO {
  id: string;
  roomCode: string;
  status: RoomStatus;
  hostPlayerId: string;
  guestPlayerId: string | null;
  hostColor: PlayerColor;
  timeControlCategory: TimeControlCategory;
  initialTimeSeconds: number;
  incrementSeconds: number;
  delaySeconds: number;
  boardTheme: string;
  pieceTheme: string;
  currentPlayerCount: number;
  maxPlayers: number;
  createdAt: string;
  expiresAt: string;
}

export interface MakeMoveInput {
  gameId: string;
  playerId: string;
  from: string;
  to: string;
  promotion?: 'q' | 'r' | 'b' | 'n';
  clientMoveId?: string;
}

export interface MoveResultDTO {
  san: string;
  uci: string;
  fenAfter: string;
  isCheck: boolean;
  isCheckmate: boolean;
  isStalemate: boolean;
  isDraw: boolean;
  isThreefoldRepetition: boolean;
  isInsufficientMaterial: boolean;
  capturedPiece: string | null;
  turn: PlayerColor;
  gameStatus: GameStatus;
  gameResult: GameResult;
  whiteTimeRemainingMs: number;
  blackTimeRemainingMs: number;
}

export interface GameStateDTO {
  id: string;
  roomId: string | null;
  gameMode: GameMode;
  aiDifficulty: AiDifficulty | null;
  fen: string;
  pgn: string;
  turn: PlayerColor;
  status: GameStatus;
  result: GameResult;
  isCheck: boolean;
  isCheckmate: boolean;
  isStalemate: boolean;
  isDraw: boolean;
  whitePlayerId: string | null;
  blackPlayerId: string | null;
  whiteTimeRemainingMs: number;
  blackTimeRemainingMs: number;
  capturedWhitePieces: string[];
  capturedBlackPieces: string[];
  moveCount: number;
  winnerPlayerId: string | null;
}

export interface AiMoveRequest {
  fen: string;
  difficulty: AiDifficulty;
}

export interface AiMoveResponse {
  from: string;
  to: string;
  promotion?: 'q' | 'r' | 'b' | 'n';
  evaluationCentipawns?: number;
  depth: number;
}

export type ApiSuccess<T> = { success: true; data: T };
export type ApiFailure = { success: false; error: { code: string; message: string; details?: unknown } };
export type ApiResponse<T> = ApiSuccess<T> | ApiFailure;
