-- =============================================================================
-- Migration 0009: Seed Data
-- =============================================================================

insert into public.app_settings (key, value, description) values
  ('default_board_theme', '"classic"', 'Default board theme for new sessions'),
  ('default_piece_theme', '"classic"', 'Default piece set for new sessions'),
  ('animation_speed_ms', '200', 'Default move animation duration in ms'),
  ('sound_enabled_default', 'true', 'Default sound toggle for new sessions'),
  ('music_enabled_default', 'false', 'Default background music toggle'),
  ('timer_presets', '[
    {"label": "Bullet 1+0", "category": "bullet", "initial_seconds": 60, "increment_seconds": 0},
    {"label": "Bullet 2+1", "category": "bullet", "initial_seconds": 120, "increment_seconds": 1},
    {"label": "Blitz 3+0", "category": "blitz", "initial_seconds": 180, "increment_seconds": 0},
    {"label": "Blitz 5+0", "category": "blitz", "initial_seconds": 300, "increment_seconds": 0},
    {"label": "Blitz 5+3", "category": "blitz", "initial_seconds": 300, "increment_seconds": 3},
    {"label": "Rapid 10+0", "category": "rapid", "initial_seconds": 600, "increment_seconds": 0},
    {"label": "Rapid 15+10", "category": "rapid", "initial_seconds": 900, "increment_seconds": 10},
    {"label": "Classical 30+0", "category": "classical", "initial_seconds": 1800, "increment_seconds": 0},
    {"label": "Unlimited", "category": "unlimited", "initial_seconds": 0, "increment_seconds": 0}
  ]', 'Selectable time control presets shown in the UI'),
  ('maintenance_mode', 'false', 'Global maintenance mode kill switch'),
  ('application_version', '"1.0.0"', 'Current deployed backend version'),
  ('room_expiry_hours', '2', 'Hours of inactivity before a waiting/active room is marked expired'),
  ('room_hard_delete_hours', '24', 'Hours after finish/expiry before a room is hard-deleted'),
  ('max_reconnect_window_seconds', '120', 'Grace period a disconnected player has to reconnect before being treated as abandoned')
on conflict (key) do nothing;

insert into public.feature_flags (flag_key, is_enabled, rollout_percentage, description) values
  ('online_friend_mode', true, 100, 'Room-code based online play between two friends'),
  ('vs_ai_mode', true, 100, 'Play against the backend AI engine'),
  ('offline_two_player_mode', true, 100, 'Local same-device two player mode (client-only, no backend game row required)'),
  ('draw_offers', true, 100, 'Allow players to offer/accept draws'),
  ('rematch', true, 100, 'Allow rematch requests after a game ends'),
  ('spectator_mode', false, 0, 'Allow a third party to watch a room (reserved for future use)'),
  ('move_premove', false, 0, 'Client-side premove support (reserved for future use)'),
  ('analytics_collection', true, 100, 'Enable daily analytics rollups')
on conflict (flag_key) do nothing;

insert into public.system_config (config_key, config_value, is_sensitive, description) values
  ('rate_limit_room_create_per_min', '10', false, 'Max room creations per IP-hash per minute'),
  ('rate_limit_move_per_sec', '5', false, 'Max moves per session per second'),
  ('rate_limit_join_per_min', '20', false, 'Max join attempts per IP-hash per minute'),
  ('cleanup_job_interval_minutes', '15', false, 'How often the room cleanup job runs'),
  ('log_retention_days', '30', false, 'Default retention window for non-error logs'),
  ('ai_move_timeout_ms', '8000', false, 'Max time allowed for AI move computation before fallback'),
  ('cors_allowed_origins', '["http://localhost:3000"]', false, 'Allowed origins for API requests; update per deployment')
on conflict (config_key) do nothing;

insert into public.openings (eco, name, moves_san) values
  ('C50', 'Italian Game', '1. e4 e5 2. Nf3 Nc6 3. Bc4'),
  ('C60', 'Ruy Lopez', '1. e4 e5 2. Nf3 Nc6 3. Bb5'),
  ('B10', 'Caro-Kann Defense', '1. e4 c6'),
  ('B20', 'Sicilian Defense', '1. e4 c5'),
  ('C00', 'French Defense', '1. e4 e6'),
  ('A00', 'Uncommon Opening', '1. g3'),
  ('D00', 'Queen''s Pawn Game', '1. d4 d5'),
  ('E00', 'Queen''s Gambit Declined', '1. d4 d5 2. c4 e6'),
  ('B00', 'King''s Pawn Opening', '1. e4'),
  ('A04', 'Reti Opening', '1. Nf3'),
  ('C20', 'King''s Pawn Game', '1. e4 e5'),
  ('A40', 'Queen''s Pawn', '1. d4')
on conflict (eco) do nothing;

insert into public.maintenance_windows (is_active, title, message, starts_at)
values (false, 'No active maintenance', null, now())
on conflict do nothing;
