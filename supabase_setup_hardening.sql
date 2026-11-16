-- ============================================================
--  MEDS — Backend hardening (security + speed at scale)
--  Run AFTER all the other supabase_setup_*.sql files.
--  Safe to re-run (DROP ... IF EXISTS / CREATE OR REPLACE / IF NOT EXISTS).
--  Run in: Supabase Dashboard → SQL Editor → New query.
--  What each part does and why: see BACKEND.md.
-- ============================================================


-- 1. STOP SELF-PROMOTION TO ADMIN ----------------------------
-- The "update own profile" policy allowed every column, so any user could
-- run  update profiles set role = 'admin'  through the API. Only admins (or
-- server-side code with no signed-in user, e.g. the SQL editor or the
-- sign-up trigger) may set role / status. Everyone else keeps their old
-- values (or the defaults on insert) — no error, so normal profile saves work.
create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.role   := 'user';
    new.status := 'active';
  else
    new.role   := old.role;
    new.status := old.status;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_privileges on public.profiles;
create trigger profiles_guard_privileges
  before insert or update on public.profiles
  for each row execute function public.guard_profile_privileges();

-- Only known values (NOT VALID = existing rows are not re-checked).
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('user', 'admin')) not valid;
alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles add constraint profiles_status_check
  check (status in ('active', 'inactive', 'blocked')) not valid;


-- 2. ENFORCE BLOCK / DEACTIVATE ON THE SERVER -----------------
-- Until now only the app's router honoured status = 'blocked', so a blocked
-- user could keep calling the API. When an admin changes status, mirror it
-- onto the Supabase Auth ban: a banned user cannot sign in or refresh their
-- token (an already-issued token still works until it expires, ≤ 1 hour).
create or replace function public.sync_profile_ban()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update auth.users
  set banned_until = case when new.status = 'active' then null
                          else now() + interval '100 years' end
  where id = new.id;
  return new;
end;
$$;

drop trigger if exists profiles_sync_ban on public.profiles;
create trigger profiles_sync_ban
  after update of status on public.profiles
  for each row
  when (old.status is distinct from new.status)
  execute function public.sync_profile_ban();


-- 3. FASTER ROW-LEVEL SECURITY --------------------------------
-- `(select auth.uid())` / `(select public.is_admin())` are evaluated ONCE per
-- query instead of once per row, and one policy per action (own OR admin)
-- replaces pairs of overlapping policies. Same access rules as before, plus:
-- readings / notifications can only point at the caller's own session.

-- profiles
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_delete_own" on public.profiles;
drop policy if exists "profiles_admin_all"  on public.profiles;
drop policy if exists "profiles_select" on public.profiles;
drop policy if exists "profiles_insert" on public.profiles;
drop policy if exists "profiles_update" on public.profiles;
drop policy if exists "profiles_delete" on public.profiles;

create policy "profiles_select" on public.profiles for select
  using (id = (select auth.uid()) or (select public.is_admin()));
create policy "profiles_insert" on public.profiles for insert
  with check (id = (select auth.uid()) or (select public.is_admin()));
create policy "profiles_update" on public.profiles for update
  using      (id = (select auth.uid()) or (select public.is_admin()))
  with check (id = (select auth.uid()) or (select public.is_admin()));
create policy "profiles_delete" on public.profiles for delete
  using (id = (select auth.uid()) or (select public.is_admin()));

-- detection_sessions (admins read + update all; delete stays own-only)
drop policy if exists "sessions_select_own"   on public.detection_sessions;
drop policy if exists "sessions_admin_select" on public.detection_sessions;
drop policy if exists "sessions_insert_own"   on public.detection_sessions;
drop policy if exists "sessions_update_own"   on public.detection_sessions;
drop policy if exists "sessions_admin_update" on public.detection_sessions;
drop policy if exists "sessions_delete_own"   on public.detection_sessions;
drop policy if exists "sessions_select" on public.detection_sessions;
drop policy if exists "sessions_insert" on public.detection_sessions;
drop policy if exists "sessions_update" on public.detection_sessions;
drop policy if exists "sessions_delete" on public.detection_sessions;

create policy "sessions_select" on public.detection_sessions for select
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "sessions_insert" on public.detection_sessions for insert
  with check (user_id = (select auth.uid()));
create policy "sessions_update" on public.detection_sessions for update
  using      (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "sessions_delete" on public.detection_sessions for delete
  using (user_id = (select auth.uid()));

-- emotion_readings (admins read all; write / delete own only)
drop policy if exists "readings_select_own"   on public.emotion_readings;
drop policy if exists "readings_admin_select" on public.emotion_readings;
drop policy if exists "readings_insert_own"   on public.emotion_readings;
drop policy if exists "readings_delete_own"   on public.emotion_readings;
drop policy if exists "readings_select" on public.emotion_readings;
drop policy if exists "readings_insert" on public.emotion_readings;
drop policy if exists "readings_delete" on public.emotion_readings;

create policy "readings_select" on public.emotion_readings for select
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "readings_insert" on public.emotion_readings for insert
  with check (
    user_id = (select auth.uid())
    and (session_id is null or exists (
      select 1 from public.detection_sessions s
      where s.session_id = emotion_readings.session_id
        and s.user_id = (select auth.uid())))
  );
create policy "readings_delete" on public.emotion_readings for delete
  using (user_id = (select auth.uid()));

-- notifications (own only)
drop policy if exists "notifications_select_own" on public.notifications;
drop policy if exists "notifications_insert_own" on public.notifications;
drop policy if exists "notifications_update_own" on public.notifications;
drop policy if exists "notifications_delete_own" on public.notifications;
drop policy if exists "notifications_select" on public.notifications;
drop policy if exists "notifications_insert" on public.notifications;
drop policy if exists "notifications_update" on public.notifications;
drop policy if exists "notifications_delete" on public.notifications;

create policy "notifications_select" on public.notifications for select
  using (user_id = (select auth.uid()));
create policy "notifications_insert" on public.notifications for insert
  with check (
    user_id = (select auth.uid())
    and (session_id is null or exists (
      select 1 from public.detection_sessions s
      where s.session_id = notifications.session_id
        and s.user_id = (select auth.uid())))
  );
create policy "notifications_update" on public.notifications for update
  using      (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "notifications_delete" on public.notifications for delete
  using (user_id = (select auth.uid()));

-- avatars storage (public read stays; writes only inside <own uid>/)
drop policy if exists "avatars_insert_own" on storage.objects;
drop policy if exists "avatars_update_own" on storage.objects;
drop policy if exists "avatars_delete_own" on storage.objects;

create policy "avatars_insert_own" on storage.objects for insert
  with check (bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars_update_own" on storage.objects for update
  using (bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars_delete_own" on storage.objects for delete
  using (bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text);


-- 4. INDEXES FOR THE APP'S REAL QUERIES -----------------------
-- Each one matches a "filter + newest first" query in the app, so Postgres
-- reads only the rows it returns instead of scanning + sorting the table.

-- My sessions / baselines / admin "sessions of user X"  (+ FK on user_id)
create index if not exists detection_sessions_user_start_idx
  on public.detection_sessions (user_id, start_time desc);
-- Admin "all sessions, newest first"
create index if not exists detection_sessions_start_idx
  on public.detection_sessions (start_time desc);

-- My readings, newest first (replaces the plain user_id index)
create index if not exists emotion_readings_user_created_idx
  on public.emotion_readings (user_id, created_at desc);
drop index if exists public.emotion_readings_user_idx;
-- Readings of one session, in time order (replaces the plain session index)
create index if not exists emotion_readings_session_created_idx
  on public.emotion_readings (session_id, created_at);
drop index if exists public.emotion_readings_session_idx;
-- Admin "recent readings across everyone"
create index if not exists emotion_readings_created_idx
  on public.emotion_readings (created_at desc);

-- FK used when a session is deleted (on delete set null)
create index if not exists notifications_session_idx
  on public.notifications (session_id);


-- 5. PER-USER RATE LIMITS FOR THE EDGE FUNCTIONS --------------
-- The ai-proxy (paid Claude calls) and send-data-email functions call
-- take_rate_limit() first. It records the call and answers false once the
-- user has made max_per_hour calls of that kind in the last hour.
-- Clients cannot read or edit this table (RLS on, no policies).
create table if not exists public.rate_limit_events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null,               -- 'ai' | 'email'
  created_at timestamptz not null default now()
);

create index if not exists rate_limit_events_user_kind_idx
  on public.rate_limit_events (user_id, kind, created_at desc);

alter table public.rate_limit_events enable row level security;

create or replace function public.take_rate_limit(kind text, max_per_hour int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid  uuid := auth.uid();
  used int;
begin
  if uid is null then
    return false;
  end if;
  -- One user's calls run one at a time, so the count can't be raced.
  perform pg_advisory_xact_lock(hashtext(uid::text || ':' || kind));
  -- Keep the table small: drop this user's entries older than a day.
  delete from public.rate_limit_events e
  where e.user_id = uid and e.kind = take_rate_limit.kind
    and e.created_at < now() - interval '1 day';
  select count(*) into used from public.rate_limit_events e
  where e.user_id = uid and e.kind = take_rate_limit.kind
    and e.created_at > now() - interval '1 hour';
  if used >= max_per_hour then
    return false;
  end if;
  insert into public.rate_limit_events (user_id, kind) values (uid, take_rate_limit.kind);
  return true;
end;
$$;

revoke all on function public.take_rate_limit(text, int) from public, anon;
grant execute on function public.take_rate_limit(text, int) to authenticated;

-- ============================================================
--  DONE. Check:  Dashboard → Advisors → Security + Performance
--  should no longer list "auth_rls_initplan" or
--  "multiple_permissive_policies" for these tables.
-- ============================================================
