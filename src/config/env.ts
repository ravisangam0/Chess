import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().positive().default(4000),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error', 'fatal']).default('info'),

  SUPABASE_URL: z.string().url(),
  SUPABASE_ANON_KEY: z.string().min(20),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(20),

  CORS_ALLOWED_ORIGINS: z.string().default('http://localhost:3000'),

  RATE_LIMIT_ROOM_CREATE_PER_MIN: z.coerce.number().int().positive().default(10),
  RATE_LIMIT_JOIN_PER_MIN: z.coerce.number().int().positive().default(20),
  RATE_LIMIT_MOVE_PER_SEC: z.coerce.number().int().positive().default(5),

  IP_HASH_SALT: z.string().min(8).default('dev-only-insecure-salt-change-me'),

  AI_MOVE_TIMEOUT_MS: z.coerce.number().int().positive().default(8000),

  ROOM_EXPIRY_HOURS: z.coerce.number().positive().default(2),
  ROOM_HARD_DELETE_HOURS: z.coerce.number().positive().default(24),
  RECONNECT_GRACE_SECONDS: z.coerce.number().positive().default(120),

  CLEANUP_JOB_INTERVAL_MINUTES: z.coerce.number().positive().default(15),
});

export type Env = z.infer<typeof EnvSchema>;

function loadEnv(): Env {
  const parsed = EnvSchema.safeParse(process.env);
  if (!parsed.success) {
    // eslint-disable-next-line no-console
    console.error('Invalid environment configuration:', parsed.error.flatten().fieldErrors);
    throw new Error('Environment validation failed. Check .env against .env.example.');
  }
  return parsed.data;
}

export const env = loadEnv();

export const corsOrigins = env.CORS_ALLOWED_ORIGINS.split(',').map((o) => o.trim()).filter(Boolean);

export const isProduction = env.NODE_ENV === 'production';
export const isTest = env.NODE_ENV === 'test';
