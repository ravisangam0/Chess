import type { Request, Response, NextFunction } from 'express';
import crypto from 'crypto';
import { env } from '../config/env.js';
import { AppError } from '../errors/AppError.js';

interface Bucket {
  count: number;
  windowStart: number;
}

const buckets = new Map<string, Bucket>();

function hashIp(ip: string): string {
  return crypto.createHmac('sha256', env.IP_HASH_SALT).update(ip).digest('hex').slice(0, 32);
}

/**
 * Fixed-window in-memory limiter. Good enough for a single-instance
 * deployment; for multi-instance production, back this with the
 * `rate_limit_buckets` table or Redis instead.
 */
export function rateLimit(maxRequests: number, windowMs: number) {
  return (req: Request, _res: Response, next: NextFunction) => {
    const ip = req.ip ?? req.socket.remoteAddress ?? 'unknown';
    const key = `${req.baseUrl}${req.path}:${hashIp(ip)}`;
    req.rateLimitKey = hashIp(ip);

    const now = Date.now();
    const bucket = buckets.get(key);

    if (!bucket || now - bucket.windowStart > windowMs) {
      buckets.set(key, { count: 1, windowStart: now });
      next();
      return;
    }

    if (bucket.count >= maxRequests) {
      next(new AppError('RATE_LIMITED', 'Too many requests. Please slow down.'));
      return;
    }

    bucket.count += 1;
    next();
  };
}

// Periodically clear old buckets so this Map doesn't grow unbounded.
setInterval(() => {
  const now = Date.now();
  for (const [key, bucket] of buckets) {
    if (now - bucket.windowStart > 10 * 60 * 1000) buckets.delete(key);
  }
}, 5 * 60 * 1000).unref();
