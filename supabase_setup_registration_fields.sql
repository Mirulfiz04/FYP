-- ============================================================
--  MEDS — Registration fields migration
--  Adds the new sign-up fields (consent + demographics + prefs)
--  to the profiles table and updates the auto-create trigger.
--
--  RUN ORDER: run this AFTER supabase_setup.sql.
--  Safe to re-run (uses IF NOT EXISTS / CREATE OR REPLACE).
--  Run in: Supabase Dashboard → SQL Editor → New query.
-- ============================================================

-- 1. NEW COLUMNS ---------------------------------------------
alter table public.profiles
  add column if not exists age_group           text,         -- Under 18 / 18–24 / 25–34 / 35–44 / 45–54 / 55+
  add column if not exists user_category       text,         -- Student / Employee / Other
  add column if not exists user_category_other text,         -- free text when user_category = 'Other' (e.g. Doctor, Worker)
  add column if not exists monitoring_goal     text,         -- Stress monitoring / Emotional awareness / Study monitoring
  add column if not exists notification_pref text default 'All', -- All / Important only / None
  add column if not exists privacy_consent   boolean default false,
  add column if not exists research_ack      boolean default false,
  add column if not exists consent_at        timestamptz;    -- when privacy consent was given

-- 2. UPDATE THE SIGN-UP TRIGGER ------------------------------
-- Reads the fields the app stores in the new user's auth metadata and
-- populates the profile row. Replaces the function from supabase_setup.sql.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  consent boolean := coalesce((new.raw_user_meta_data->>'privacy_consent')::boolean, false);
begin
  insert into public.profiles (
    id, email, name, gender,
    -- legacy columns kept for backward compatibility (may be null)
    age, contact_number, location,
    -- new registration fields
    age_group, user_category, user_category_other, monitoring_goal, notification_pref,
    privacy_consent, research_ack, consent_at
  )
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'name',
    new.raw_user_meta_data->>'gender',
    nullif(new.raw_user_meta_data->>'age', '')::int,
    new.raw_user_meta_data->>'contact_number',
    new.raw_user_meta_data->>'location',
    new.raw_user_meta_data->>'age_group',
    new.raw_user_meta_data->>'user_category',
    nullif(new.raw_user_meta_data->>'user_category_other', ''),
    new.raw_user_meta_data->>'monitoring_goal',
    coalesce(new.raw_user_meta_data->>'notification_pref', 'All'),
    consent,
    coalesce((new.raw_user_meta_data->>'research_ack')::boolean, false),
    case when consent then now() else null end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- The trigger itself is unchanged; recreate it to be safe.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
--  DONE. New sign-ups will now store: name, email, gender,
--  age_group, user_category, monitoring_goal, notification_pref,
--  privacy_consent, research_ack (+ consent_at timestamp).
-- ============================================================
