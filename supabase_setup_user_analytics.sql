-- ============================================================
--  MEDS — Per-user analytics  (run AFTER the other three SQL files)
--  Attributes every emotion reading to a user so each person has
--  their own emotion + heart-rate analytics.
--  Run ONCE in the Supabase Dashboard → SQL Editor → New query.
-- ============================================================

-- 1. ADD user_id TO emotion_readings -------------------------
alter table public.emotion_readings
  add column if not exists user_id uuid
  references auth.users(id) on delete set null;

-- Backfill old rows from their linked session where possible.
update public.emotion_readings r
set user_id = s.user_id
from public.detection_sessions s
where r.session_id = s.session_id
  and r.user_id is null;

create index if not exists emotion_readings_user_idx
  on public.emotion_readings(user_id);

-- 2. ROW-LEVEL SECURITY --------------------------------------
-- Each user sees & inserts only their own readings; admins read all.
alter table public.emotion_readings enable row level security;

drop policy if exists "readings_insert_own" on public.emotion_readings;
create policy "readings_insert_own"
  on public.emotion_readings for insert
  with check (auth.uid() = user_id);

drop policy if exists "readings_select_own" on public.emotion_readings;
create policy "readings_select_own"
  on public.emotion_readings for select
  using (auth.uid() = user_id);

drop policy if exists "readings_admin_select" on public.emotion_readings;
create policy "readings_admin_select"
  on public.emotion_readings for select
  using (public.is_admin());

-- NOTE: existing rows with no session (user_id stays NULL) remain visible
-- only to admins. New readings are always tagged with the signed-in user.
