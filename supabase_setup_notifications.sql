-- ============================================================
--  MEDS — Notifications, AI summary status & notification prefs
--  Run this AFTER the other supabase_setup_*.sql files.
--  Safe to re-run (IF NOT EXISTS / CREATE OR REPLACE).
--  Run in: Supabase Dashboard → SQL Editor → New query.
-- ============================================================

-- 1. NOTIFICATIONS TABLE -------------------------------------
create table if not exists public.notifications (
  notification_id uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  session_id      uuid references public.detection_sessions(session_id) on delete set null,
  type            text not null,   -- sensorDisconnected | noFingerDetected | ...
  title           text not null,
  message         text not null,
  deep_link       text,
  metadata        jsonb default '{}'::jsonb,
  is_read         boolean default false,
  created_at      timestamptz default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications(user_id, created_at desc);

alter table public.notifications enable row level security;

-- Each user manages only their own notifications.
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select
  using (auth.uid() = user_id);

drop policy if exists "notifications_insert_own" on public.notifications;
create policy "notifications_insert_own"
  on public.notifications for insert
  with check (auth.uid() = user_id);

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update
  using (auth.uid() = user_id);

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete
  using (auth.uid() = user_id);

-- 2. AI SUMMARY TRACKING ON SESSIONS -------------------------
alter table public.detection_sessions
  add column if not exists ai_summary        jsonb,
  add column if not exists ai_summary_status text default 'pending',  -- pending | processing | completed | failed | skipped (abandoned session, self-healed)
  add column if not exists ai_summary_error  text,
  add column if not exists ai_generated_at   timestamptz;

-- 3. NOTIFICATION PREFERENCES ON PROFILES --------------------
alter table public.profiles
  add column if not exists notification_settings jsonb
    default '{"sensorCamera":true,"sessionCompleted":true,"aiSummary":true,"weeklyTrend":false}'::jsonb;

-- ============================================================
--  DONE.
--  • notifications: per-user inbox for the Notification Centre.
--  • detection_sessions.ai_summary*: stores the AI insight + status.
--  • profiles.notification_settings: the 4 preference switches (synced).
-- ============================================================
