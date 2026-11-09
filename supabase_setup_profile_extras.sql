-- ============================================================
--  MEDS — Profile extras
--  Adds profiles.display_name and the DELETE policies needed by the
--  Privacy & Security actions (delete session history / delete account).
--  Run AFTER the other supabase_setup_*.sql files. Safe to re-run.
-- ============================================================

-- 1. DISPLAY NAME --------------------------------------------
alter table public.profiles
  add column if not exists display_name text;

-- 2. DELETE POLICIES (own rows only) -------------------------
-- Lets a user delete their own session history and account data.

drop policy if exists "sessions_delete_own" on public.detection_sessions;
create policy "sessions_delete_own"
  on public.detection_sessions for delete
  using (auth.uid() = user_id);

drop policy if exists "readings_delete_own" on public.emotion_readings;
create policy "readings_delete_own"
  on public.emotion_readings for delete
  using (auth.uid() = user_id);

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own"
  on public.profiles for delete
  using (auth.uid() = id);

-- ============================================================
--  NOTE: deleting the auth login itself needs a service-role key
--  (server-side). The app's "Delete account" removes the user's data
--  and signs them out.
-- ============================================================
