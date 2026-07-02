import type { Request, Response, NextFunction } from 'express';
import { supabaseAdmin } from '../config/supabase.js';
import { AppError } from '../errors/AppError.js';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      playerId?: string;
      sessionToken?: string;
      rateLimitKey?: string;
    }
  }
}

/**
 * Optional session resolution: if an Authorization: Bearer <sessionToken>
 * header is present, resolves it to a player row and attaches req.playerId.
 * Does NOT reject requests without a token — routes that require a player
 * (moves, resign, reconnect) check req.playerId themselves and throw
 * UNAUTHORIZED_SESSION if missing.
 */
export async function resolveSession(req: Request, _res: Response, next: NextFunction) {
  try {
    const header = req.headers.authorization;
    if (header?.startsWith('Bearer ')) {
      const token = header.slice('Bearer '.length).trim();
      req.sessionToken = token;

      const { data, error } = await supabaseAdmin
        .from('players')
        .select('id')
        .eq('session_token', token)
        .maybeSingle();

      if (!error && data) {
        req.playerId = (data as { id: string }).id;
      }
    }
    next();
  } catch (err) {
    next(err);
  }
}

export function requireSession(req: Request, _res: Response, next: NextFunction) {
  if (!req.playerId) {
    next(new AppError('UNAUTHORIZED_SESSION', 'A valid session token is required for this action.'));
    return;
  }
  next();
}
