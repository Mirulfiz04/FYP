// Runs every MEDS setup SQL file (in order) + the hardening file twice on a
// real Postgres (PGlite), with Supabase's auth/storage schemas stubbed, then
// checks the security rules as a normal user and as an admin.
// Run:  cd supabase/tests  &&  npm install  &&  npm test
// Re-run it after any change to a supabase_setup_*.sql file.
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const APP = process.argv[2] ?? fileURLToPath(new URL("../..", import.meta.url));
const db = new PGlite();

await db.exec(`
  create role anon nologin; create role authenticated nologin;
  create schema auth;
  create table auth.users (id uuid primary key, email text,
    raw_user_meta_data jsonb default '{}', banned_until timestamptz);
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create schema storage;
  create table storage.buckets (id text primary key, name text, public boolean);
  create table storage.objects (id uuid primary key default gen_random_uuid(),
    bucket_id text, name text);
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql
    immutable as $$ select string_to_array(name, '/') $$;
  -- emotion_readings predates the setup files (see the schema dump)
  create table public.emotion_readings (id bigserial primary key,
    created_at timestamptz default now(), emotion text not null,
    confidence real not null, hr int default 0, spo2 int default 0,
    sensor_quality text default 'WAITING');
  -- Supabase's default grants
  grant usage on schema public, auth, storage to anon, authenticated;
  grant all on all tables in schema public, storage to anon, authenticated;
  grant all on all sequences in schema public to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant all on sequences to anon, authenticated;
`);

const files = [
  "supabase_setup.sql", "supabase_setup_sessions.sql", "supabase_setup_admin.sql",
  "supabase_setup_user_analytics.sql", "supabase_setup_notifications.sql",
  "supabase_setup_session_summary.sql", "supabase_setup_session_review.sql",
  "supabase_setup_profile_extras.sql", "supabase_setup_registration_fields.sql",
  "supabase_setup_admin_user_mgmt.sql",
  "supabase_setup_hardening.sql", "supabase_setup_hardening.sql", // re-run safe?
];
for (const f of files) {
  try { await db.exec(readFileSync(`${APP}/${f}`, "utf8")); }
  catch (e) { console.error(`FAILED in ${f}:`, e.message); process.exit(1); }
}
console.log("ok  all setup files + hardening (twice) ran");

const A = "00000000-0000-0000-0000-00000000000a"; // normal user
const B = "00000000-0000-0000-0000-00000000000b"; // admin
const C = "00000000-0000-0000-0000-00000000000c"; // victim for deletion

await db.exec(`insert into auth.users (id, email, raw_user_meta_data) values
  ('${A}','a@x.io','{"name":"Ann"}'), ('${B}','b@x.io','{}'), ('${C}','c@x.io','{}');
  update public.profiles set role = 'admin' where id = '${B}';`);

async function as(uid, sql, params = []) {
  await db.exec(`set role authenticated;
    select set_config('request.jwt.claim.sub', '${uid}', false);`);
  try { return await db.query(sql, params); }
  finally { await db.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`); }
}
async function rejects(uid, sql, label) {
  await assert.rejects(() => as(uid, sql), undefined, label);
  console.log("ok ", label);
}
const one = async (sql) => (await db.query(sql)).rows[0];
const check = (cond, label) => { assert.ok(cond, label); console.log("ok ", label); };

// --- 1. no self-promotion ---------------------------------------------------
await as(A, `update public.profiles set role = 'admin', name = 'Annie' where id = $1`, [A]);
let p = await one(`select role, name from public.profiles where id = '${A}'`);
check(p.role === "user" && p.name === "Annie", "user cannot make self admin; normal edit still saves");

await as(A, `delete from public.profiles where id = $1`, [A]);
await as(A, `insert into public.profiles (id, email, role) values ($1, 'a@x.io', 'admin')`, [A]);
p = await one(`select role from public.profiles where id = '${A}'`);
check(p.role === "user", "user cannot re-insert own profile as admin");
let res = await as(A, `update public.profiles set role = 'user' where id = $1`, [B]);
p = await one(`select role from public.profiles where id = '${B}'`);
check(res.affectedRows === 0 && p.role === "admin", "user cannot edit another user's profile");
await rejects(B, `update public.profiles set role = 'superuser' where id = '${A}'`,
  "unknown role values are rejected");

// --- 2. block -> auth ban, and a blocked user cannot unblock themselves ------
await as(B, `update public.profiles set status = 'blocked' where id = $1`, [A]);
let u = await one(`select banned_until from auth.users where id = '${A}'`);
check(u.banned_until !== null, "admin block sets the auth ban");
await as(A, `update public.profiles set status = 'active' where id = $1`, [A]);
p = await one(`select status from public.profiles where id = '${A}'`);
check(p.status === "blocked", "blocked user cannot unblock self");
await as(B, `update public.profiles set status = 'active' where id = $1`, [A]);
u = await one(`select banned_until from auth.users where id = '${A}'`);
check(u.banned_until === null, "admin unblock lifts the auth ban");

// --- 3. sessions / readings isolation ---------------------------------------
const sA = (await as(A, `insert into public.detection_sessions (user_id) values ($1) returning session_id`, [A])).rows[0].session_id;
const sB = (await as(B, `insert into public.detection_sessions (user_id) values ($1) returning session_id`, [B])).rows[0].session_id;
await as(A, `insert into public.emotion_readings (emotion, confidence, user_id, session_id) values ('happy', 0.9, $1, $2)`, [A, sA]);
await as(A, `insert into public.emotion_readings (emotion, confidence, user_id) values ('sad', 0.8, $1)`, [A]);
await as(B, `insert into public.emotion_readings (emotion, confidence, user_id, session_id) values ('calm', 0.7, $1, $2)`, [B, sB]);
console.log("ok  own readings insert (with and without session)");
await rejects(A, `insert into public.emotion_readings (emotion, confidence, user_id, session_id) values ('x', 0.5, '${A}', '${sB}')`,
  "user cannot attach a reading to someone else's session");
await rejects(A, `insert into public.emotion_readings (emotion, confidence, user_id) values ('x', 0.5, '${B}')`,
  "user cannot insert a reading as someone else");
await rejects(A, `insert into public.notifications (user_id, session_id, type, title, message) values ('${A}', '${sB}', 't', 't', 'm')`,
  "user cannot attach a notification to someone else's session");

let n = (await as(A, `select count(*)::int c from public.emotion_readings`)).rows[0].c;
check(n === 2, "user reads only own readings");
n = (await as(B, `select count(*)::int c from public.emotion_readings`)).rows[0].c;
check(n === 3, "admin reads all readings");
n = (await as(A, `select count(*)::int c from public.profiles`)).rows[0].c;
check(n === 1, "user reads only own profile");
n = (await as(B, `select count(*)::int c from public.profiles`)).rows[0].c;
check(n === 3, "admin reads all profiles");

let r = await as(A, `update public.detection_sessions set notes = 'hack' where session_id = $1`, [sB]);
check(r.affectedRows === 0, "user cannot update someone else's session");
r = await as(B, `update public.detection_sessions set status = 'completed' where session_id = $1`, [sA]);
check(r.affectedRows === 1, "admin can heal another user's session");
await rejects(A, `update public.detection_sessions set user_id = '${B}' where session_id = '${sA}'`,
  "user cannot hand a session to someone else");
r = await as(B, `delete from public.detection_sessions where session_id = $1`, [sA]);
check(r.affectedRows === 0, "session delete stays owner-only");

// --- 4. storage -------------------------------------------------------------
await as(A, `insert into storage.objects (bucket_id, name) values ('avatars', '${A}/avatar.png')`);
console.log("ok  user uploads into own avatar folder");
await rejects(A, `insert into storage.objects (bucket_id, name) values ('avatars', '${B}/avatar.png')`,
  "user cannot upload into another user's folder");

// --- 5. rate limits ---------------------------------------------------------
const take = async (uid, kind, max) =>
  (await as(uid, `select public.take_rate_limit($1, $2) ok`, [kind, max])).rows[0].ok;
const got = [await take(A, "ai", 2), await take(A, "ai", 2), await take(A, "ai", 2)];
check(JSON.stringify(got) === "[true,true,false]", "rate limit allows 2 then blocks the 3rd");
check(await take(A, "email", 2) === true, "rate limit counts each kind separately");
check(await take(B, "ai", 2) === true, "rate limit is per user");
n = (await as(A, `select count(*)::int c from public.rate_limit_events`)).rows[0].c;
check(n === 0, "clients cannot read the rate-limit table");
await db.exec(`set role anon`);
await assert.rejects(() => db.query(`select public.take_rate_limit('ai', 5)`));
await db.exec(`reset role`);
console.log("ok  signed-out (anon) callers cannot use the limiter");

// --- 6. admin delete still works, only for admins ---------------------------
await rejects(A, `select public.admin_delete_user('${C}')`, "non-admin cannot delete users");
await as(B, `select public.admin_delete_user($1)`, [C]);
n = (await db.query(`select count(*)::int c from auth.users where id = '${C}'`)).rows[0].c;
check(n === 0, "admin delete removes the auth login");

console.log("\nALL CHECKS PASSED");
