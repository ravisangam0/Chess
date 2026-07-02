import { supabaseAdmin } from '../config/supabase.js';
import { AppError } from '../errors/AppError.js';
import { logger } from '../utils/logger.js';
import type { DrawRequestRow } from '../types/database.types.js';

export const drawRepository = {
  async createOffer(gameId: string, requestedBy: string): Promise<DrawRequestRow> {
    const { data, error } = await supabaseAdmin
      .from('draw_requests')
      .insert({ game_id: gameId, requested_by: requestedBy, status: 'pending' })
      .select()
      .single();

    if (error || !data) {
      if (error?.code === '23505') {
        throw new AppError('DRAW_REQUEST_ALREADY_PENDING', 'A draw offer is already pending for this game.');
      }
      logger.error('database', 'Failed to create draw offer', { error: error?.message, gameId });
      throw new AppError('DATABASE_ERROR', 'Could not create the draw offer.');
    }
    return data as DrawRequestRow;
  },

  async findPendingByGame(gameId: string): Promise<DrawRequestRow | null> {
    const { data, error } = await supabaseAdmin
      .from('draw_requests')
      .select('*')
      .eq('game_id', gameId)
      .eq('status', 'pending')
      .maybeSingle();

    if (error) {
      logger.error('database', 'Failed to look up pending draw offer', { error: error.message, gameId });
      throw new AppError('DATABASE_ERROR', 'Could not look up the draw offer.');
    }
    return (data as DrawRequestRow) ?? null;
  },

  async resolve(requestId: string, status: 'accepted' | 'declined'): Promise<DrawRequestRow> {
    const { data, error } = await supabaseAdmin
      .from('draw_requests')
      .update({ status, resolved_at: new Date().toISOString() })
      .eq('id', requestId)
      .select()
      .single();

    if (error || !data) {
      logger.error('database', 'Failed to resolve draw offer', { error: error?.message, requestId });
      throw new AppError('DATABASE_ERROR', 'Could not resolve the draw offer.');
    }
    return data as DrawRequestRow;
  },
};
