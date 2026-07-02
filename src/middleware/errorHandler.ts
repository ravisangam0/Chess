import type { Request, Response, NextFunction } from 'express';
import { AppError, isAppError } from '../errors/AppError.js';
import { logger } from '../utils/logger.js';

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  if (isAppError(err)) {
    if (err.httpStatus >= 500) {
      logger.error('api', err.message, { code: err.code, path: req.path, details: err.details });
    } else {
      logger.warn('api', err.message, { code: err.code, path: req.path });
    }
    res.status(err.httpStatus).json(err.toJSON());
    return;
  }

  const error = err as Error;
  logger.error('api', 'Unhandled error', { message: error?.message, stack: error?.stack, path: req.path });
  const fallback = new AppError('INTERNAL_ERROR', 'Something went wrong on our end.');
  res.status(fallback.httpStatus).json(fallback.toJSON());
}

export function notFoundHandler(req: Request, res: Response) {
  res.status(404).json({
    success: false,
    error: { code: 'INTERNAL_ERROR', message: `No route matches ${req.method} ${req.path}` },
  });
}
