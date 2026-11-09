-- ============================================================
--  MEDS — Admin user management (full account deletion)
--  Run this ONCE in the Supabase Dashboard → SQL Editor → New query,
--  AFTER supabase_setup_admin.sql (it relies on public.is_admin()).
--
--  Account block / unblock and activate / deactivate already work through
--  the admin RLS policy on `profiles` (the app just updates `status`).
--  This file adds a server-side function so an administrator can FULLY
--  delete a user — their data AND their auth login — which a client cannot
--  do on its own. The app calls it via AdminService.deleteUser() and falls
--  back to a profile-row delete if this function is not installed.
-- ============================================================

create or replace function public.admin_delete_user(target_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only administrators may delete accounts.
  if not public.is_admin() then
    raise exception 'Only administrators can delete users';
  end if;

  -- An admin cannot delete their own account through this function.
  if target_id = auth.uid() then
    raise exception 'You cannot delete your own account here';
  end if;

  -- Remove the user's data, then the profile, then the auth login.
  -- (detection_sessions / profiles also cascade from auth.users, but we
  --  delete explicitly so emotion_readings — which only "set null" on
  --  cascade — are removed too.)
  delete from public.notifications      where user_id = target_id;
  delete from public.emotion_readings   where user_id = target_id;
  delete from public.detection_sessions where user_id = target_id;
  delete from public.profiles           where id      = target_id;
  delete from auth.users                where id      = target_id;
end;
$$;

-- Lock the function down: only signed-in users may call it, and the body
-- itself enforces that the caller is an administrator.
revoke all on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_delete_user(uuid) to authenticated;
