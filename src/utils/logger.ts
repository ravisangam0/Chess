import { supabaseAdmin } from '../config/supabase.js';
import { env } from '../config/env.js';
import type { LogCategory, LogLevel } from '../types/database.types.js';

const LEVEL_RANK: Record<LogLevel, number> = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 };

interface LogContext {
  roomId?: string;
  gameId?: string;
  playerId?: string;
  requestId?: string;
  [key: string]: unknown;
}

function shouldLog(level: LogLevel): boolean {
  return LEVEL_RANK[level] >= LEVEL_RANK[env.LOG_LEVEL];
}

function consoleWrite(level: LogLevel, category: LogCategory, message: string, context: LogContext) {
  const line = JSON.stringify({ ts: new Date().toISOString(), level, category, message, ...context });
  if (level === 'error' || level === 'fatal') {
    // eslint-disable-next-line no-console
    console.error(line);
  } else if (level === 'warn') {
    // eslint-disable-next-line no-console
    console.warn(line);
  } else {
    // eslint-disable-next-line no-console
    console.log(line);
  }
}

/**
 * Fire-and-forget persistence to system_logs. Never throws — logging must
 * never be the cause of a request failure. Errors writing logs are swallowed
 * after one console fallback.
 */
function persist(level: LogLevel, category: LogCategory, message: string, context: LogContext) {
  const { roomId, gameId, playerId, requestId, ...rest } = context;
  void supabaseAdmin
    .from('system_logs')
    .insert({
      level,
      category,
      message,
      context: rest,
      room_id: roomId ?? null,
      game_id: gameId ?? null,
      player_id: playerId ?? null,
      request_id: requestId ?? null,
    })
    .then(({ error }) => {
      if (error) {
        // eslint-disable-next-line no-console
        console.error('logger: failed to persist log row', error.message);
      }
    });
}

function log(level: LogLevel, category: LogCategory, message: string, context: LogContext = {}) {
  if (!shouldLog(level)) return;
  consoleWrite(level, category, message, context);
  // Persist warn+ always; persist info only for room/move/system categories to limit volume.
  if (LEVEL_RANK[level] >= LEVEL_RANK.warn || ['room', 'move', 'system'].includes(category)) {
    persist(level, category, message, context);
  }
}

export const logger = {
  debug: (category: LogCategory, message: string, context?: LogContext) => log('debug', category, message, context),
  info: (category: LogCategory, message: string, context?: LogContext) => log('info', category, message, context),
  warn: (category: LogCategory, message: string, context?: LogContext) => log('warn', category, message, context),
  error: (category: LogCategory, message: string, context?: LogContext) => log('error', category, message, context),
  fatal: (category: LogCategory, message: string, context?: LogContext) => log('fatal', category, message, context),
};
