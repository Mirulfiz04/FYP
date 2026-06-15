-- ============================================================
--  MEDS — Administrator setup  (run AFTER the other two SQL files)
--  Run this ONCE in the Supabase Dashboard → SQL Editor → New query.
-- ============================================================

-- 1. ACCOUNT STATUS (for enable / disable from the admin panel) ----
alter table public.profiles
  add column if not exists status text default 'active';   -- active | blocked

-- 2. is_admin() HELPER --------------------------------------------
-- SECURITY DEFINER so it can read the caller's role without tripping
-- the profiles RLS policies (avoids infinite recursion).
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- 3. ADMIN RLS POLICIES -------------------------------------------
-- Admins can read & manage every profile (normal users keep own-row only).
drop policy if exists "profiles_admin_all" on public.profiles;
create policy "profiles_admin_all"
  on public.profiles for all
  using (public.is_admin())
  with check (public.is_admin());

-- Admins can read every detection session.
drop policy if exists "sessions_admin_select" on public.detection_sessions;
create policy "sessions_admin_select"
  on public.detection_sessions for select
  using (public.is_admin());

-- ============================================================
--  MAKE YOURSELF AN ADMIN
--  Run this once with your own account's email, then log in again:
--
--    update public.profiles set role = 'admin'
--    where email = 'YOUR_EMAIL@example.com';
-- ============================================================
