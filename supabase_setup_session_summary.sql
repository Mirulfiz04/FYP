-- ============================================================
--  MEDS — Session summary aggregates
--  Adds the per-session summary columns saved when a live session ends.
--  Run AFTER the other supabase_setup_*.sql files. Safe to re-run.
-- ============================================================

alter table public.detection_sessions
  add column if not exists dominant_emotion text,
  add column if not exists avg_confidence   numeric,
  add column if not exists baseline_bpm     int,
  add column if not exists average_bpm      int,
  add column if not exists min_bpm          int,
  add column if not exists max_bpm          int,
  add column if not exists final_state      text,
  add column if not exists camera_quality   text,   -- Good | Fair | Poor
  add column if not exists sensor_quality   text;   -- Good | Fair | Poor

-- ============================================================
--  DONE. The live session's Stop action stamps these alongside
--  end_time + status='completed' (see SupabaseService.completeSession).
-- ============================================================
