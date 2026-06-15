-- ============================================================
--  MEDS — Auth, Profiles & Avatars backend setup
--  Run this ONCE in the Supabase Dashboard → SQL Editor → New query.
-- ============================================================

-- 1. PROFILES TABLE ------------------------------------------
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  name           text,
  email          text,
  role           text default 'user',
  age            int,
  gender         text,
  contact_number text,
  location       text,
  avatar_url     text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

alter table public.profiles enable row level security;

-- Each signed-in user can read and edit only their own row.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id);

-- 2. AUTO-CREATE A PROFILE ROW ON SIGN-UP --------------------
-- Reads the extra fields the app stores in the user's auth metadata
-- (name / age / gender / contact_number / location).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, age, gender, contact_number, location)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'name',
    nullif(new.raw_user_meta_data->>'age', '')::int,
    new.raw_user_meta_data->>'gender',
    new.raw_user_meta_data->>'contact_number',
    new.raw_user_meta_data->>'location'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 3. AVATARS STORAGE BUCKET ----------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Anyone can view avatars (bucket is public).
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- A user may only write/update/delete files inside a folder named after
-- their own user id  (the app uploads to  <uid>/avatar.<ext> ).
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ============================================================
--  AFTER RUNNING THIS:
--  Authentication → Sign In / Providers → Email → turn OFF
--  "Confirm email" so new accounts can log in immediately
--  while you are testing/demoing.
-- ============================================================
