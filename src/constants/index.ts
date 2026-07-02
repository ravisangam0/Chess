export const ROOM_CODE_LENGTH = 6;
export const ROOM_CODE_REGEX = /^[A-HJ-NP-Z2-9]{6}$/;

export const DEFAULT_TIME_CONTROLS = {
  bullet: { initialTimeSeconds: 60, incrementSeconds: 0 },
  blitz: { initialTimeSeconds: 300, incrementSeconds: 0 },
  rapid: { initialTimeSeconds: 600, incrementSeconds: 0 },
  classical: { initialTimeSeconds: 1800, incrementSeconds: 0 },
  unlimited: { initialTimeSeconds: 0, incrementSeconds: 0 },
} as const;

export const TIME_CONTROL_BOUNDS_SECONDS = {
  min: 0,
  max: 7200, // 2 hours per side hard ceiling
};

export const MAX_PLAYERS_PER_ROOM = 2;

export const DRAW_REQUEST_TTL_SECONDS = 60;

export const PROMOTION_PIECES = ['q', 'r', 'b', 'n'] as const;

export const STARTING_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

export const AI_DEPTH_BY_DIFFICULTY = {
  easy: 1,
  medium: 2,
  hard: 3,
} as const;

export const AI_RANDOMNESS_BY_DIFFICULTY = {
  // probability of picking a sub-optimal move from the candidate pool,
  // used to make "easy" feel beatable and "hard" feel sharp
  easy: 0.6,
  medium: 0.25,
  hard: 0.05,
} as const;

export const TIMER_TICK_TOLERANCE_MS = 250; // grace before declaring a timeout, to absorb network jitter

export const RECONNECT_GRACE_SECONDS_DEFAULT = 120;
