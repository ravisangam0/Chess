import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { corsOrigins } from './config/env.js';
import { roomRoutes } from './routes/roomRoutes.js';
import { gameRoutes } from './routes/gameRoutes.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { logger } from './utils/logger.js';

export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(
    cors({
      origin: corsOrigins,
      credentials: true,
    }),
  );
  app.use(express.json({ limit: '256kb' }));

  app.get('/health', (_req, res) => {
    res.status(200).json({ success: true, data: { status: 'ok', timestamp: new Date().toISOString() } });
  });

  app.use('/api/rooms', roomRoutes);
  app.use('/api/games', gameRoutes);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

export function logStartup(port: number) {
  logger.info('system', `Chess backend listening on port ${port}`);
}
