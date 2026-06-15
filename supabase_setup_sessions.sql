-- ============================================================
--  MEDS — Detection Sessions setup  (run AFTER supabase_setup.sql)
--  Run this ONCE in the Supabase Dashboard → SQL Editor → New query.
-- ============================================================

-- 1. DETECTION_SESSIONS TABLE --------------------------------
create table if not exists public.detection_sessions (
  session_id uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  start_time timestamptz default now(),
  end_time   timestamptz,
  status     text default 'active',   -- active | completed | cancelled
  notes      text,
  created_at timestamptz default now()
);

alter table public.detection_sessions enable row level security;

-- Each signed-in user can read / create / update only their own sessions.
drop policy if exists "sessions_select_own" on public.detection_sessions;
create policy "sessions_select_own"
  on public.detection_sessions for select
  using (auth.uid() = user_id);

drop policy if exists "sessions_insert_own" on public.detection_sessions;
create policy "sessions_insert_own"
  on public.detection_sessions for insert
  with check (auth.uid() = user_id);

drop policy if exists "sessions_update_own" on public.detection_sessions;
create policy "sessions_update_own"
  on public.detection_sessions for update
  using (auth.uid() = user_id);

-- 2. LINK EMOTION READINGS TO A SESSION ----------------------
-- Adds a nullable column only; existing rows and the existing insert path
-- keep working unchanged.
alter table public.emotion_readings
  add column if not exists session_id uuid
  references public.detection_sessions(session_id) on delete set null;

create index if not exists emotion_readings_session_idx
  on public.emotion_readings(session_id);
