-- ============================================================
--  MEDS — Session review flag
--  Adds the columns used by the Session Details "Mark for Review" action.
--  Run AFTER the other supabase_setup_*.sql files. Safe to re-run.
-- ============================================================

alter table public.detection_sessions
  add column if not exists flagged_for_review boolean default false,
  add column if not exists review_note        text;

-- ============================================================
--  DONE. The app writes these via SupabaseService.setSessionReview
--  (best-effort — a missing column never blocks the page).
-- ============================================================
