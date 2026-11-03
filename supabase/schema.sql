-- MCQ Arcade v3 schema (roles, permissions and per-user content access).
-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run.
-- Safe on a brand-new project AND on a database that already has the v2 tables: v2 data is kept and upgraded in place.
-- The FIRST account that signs up (or the oldest existing account when upgrading) becomes the admin.

-- ============================================================
-- 0. Upgrade v2 -> v3 (does nothing on a fresh project)
-- ============================================================
do $$
declare r record;
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='topics' and column_name='user_id') then
    -- old per-user security rules and composite foreign keys
    for r in select tablename from pg_tables where schemaname='public' and tablename in ('topics','questions','progress','notes','profiles') loop
      execute format('drop policy if exists "own rows" on public.%I', r.tablename);
    end loop;
    for r in select conrelid::regclass::text as tbl, conname from pg_constraint
             where contype='f' and conrelid in ('public.topics'::regclass,'public.questions'::regclass,'public.progress'::regclass,'public.notes'::regclass) loop
      execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    end loop;
    if exists (select 1 from public.topics group by id having count(*) > 1)
       or exists (select 1 from public.questions group by id having count(*) > 1) then
      raise exception 'Upgrade stopped: two accounts own a section or question with the same id. Delete the duplicates and run this script again.';
    end if;
    alter table public.topics    drop constraint if exists topics_pkey;
    alter table public.questions drop constraint if exists questions_pkey;
    alter table public.topics    rename column user_id to owner_id;
    alter table public.questions rename column user_id to owner_id;
    alter table public.topics    add primary key (id);
    alter table public.questions add primary key (id);
    -- everything that existed before stays private to its owner until the admin publishes it
    alter table public.topics    add column if not exists access text not null default 'hidden';
    alter table public.questions add column if not exists access text not null default 'inherit';
    alter table public.topics    add foreign key (owner_id)  references auth.users(id) on delete cascade;
    alter table public.questions add foreign key (owner_id)  references auth.users(id) on delete cascade;
    alter table public.topics    add foreign key (parent_id) references public.topics(id) on delete cascade;
    alter table public.questions add foreign key (topic_id)  references public.topics(id) on delete cascade;
    alter table public.progress  add foreign key (user_id)   references auth.users(id) on delete cascade;
    alter table public.progress  add foreign key (qid)       references public.questions(id) on delete cascade;
    alter table public.notes     add foreign key (user_id)   references auth.users(id) on delete cascade;
    alter table public.notes     add foreign key (qid)       references public.questions(id) on delete cascade;
  end if;
end $$;

-- ============================================================
-- 1. Tables
-- ============================================================
create table if not exists public.app_settings (
  key   text primary key,
  value jsonb not null
);
-- Permissions every NEW account starts with (the admin can change this, and each user, from the Admin console).
insert into public.app_settings (key, value) values
  ('default_perms', '{"tutor":true,"shuffle":true,"study":true,"mistake_log":true,"notes":true,"reset":true,"own_content":false}')
on conflict (key) do nothing;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  xp   int not null default 0,
  best int not null default 0
);
alter table public.profiles add column if not exists email      text        not null default '';
alter table public.profiles add column if not exists role       text        not null default 'user';
alter table public.profiles add column if not exists perms      jsonb       not null default '{}'::jsonb;
alter table public.profiles add column if not exists disabled   boolean     not null default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add  constraint profiles_role_check check (role in ('user','admin'));

create table if not exists public.topics (
  id        text primary key,
  parent_id text references public.topics(id) on delete cascade,   -- null = top-level section
  owner_id  uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name      text not null,
  blurb     text not null default '',
  pos       bigint not null default 0,
  access    text not null default 'hidden'                          -- everyone | selected | hidden
);
alter table public.topics drop constraint if exists topics_access_check;
alter table public.topics add  constraint topics_access_check check (access in ('everyone','selected','hidden'));

create table if not exists public.questions (
  id       text primary key,
  topic_id text not null references public.topics(id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  n        int  not null default 0,
  data     jsonb not null,                                           -- question text, options, answer, explanation...
  access   text not null default 'inherit'                           -- inherit (follow the section) | selected | hidden
);
alter table public.questions drop constraint if exists questions_access_check;
alter table public.questions add  constraint questions_access_check check (access in ('inherit','selected','hidden'));
create index if not exists questions_topic_idx on public.questions (topic_id);
create index if not exists topics_parent_idx   on public.topics (parent_id);

-- Which users may open a section / question when its access is "selected"
create table if not exists public.topic_access (
  topic_id text not null references public.topics(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  primary key (topic_id, user_id)
);
create table if not exists public.question_access (
  question_id text not null references public.questions(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  primary key (question_id, user_id)
);
create index if not exists topic_access_user_idx    on public.topic_access (user_id);
create index if not exists question_access_user_idx on public.question_access (user_id);

create table if not exists public.progress (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  qid     text not null references public.questions(id) on delete cascade,
  s int not null default 0,   -- attempts
  c int not null default 0,   -- correct
  w int not null default 0,   -- wrong
  l int,                      -- last result: 1 right, 0 wrong
  t bigint,                   -- last attempt time (ms)
  wp jsonb,                   -- last wrong pick
  primary key (user_id, qid)
);
create table if not exists public.notes (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  qid     text not null references public.questions(id) on delete cascade,
  note    text not null,
  primary key (user_id, qid)
);

-- Personal notes a person writes under a topic. Always private to that person.
create table if not exists public.topic_notes (
  id         text primary key,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  topic_id   text not null references public.topics(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 8000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists topic_notes_user_idx on public.topic_notes (user_id, topic_id);

-- ============================================================
-- 2. Helper functions (run with definer rights so the security rules can look people up safely)
-- ============================================================
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' from public.profiles where user_id = auth.uid() and not disabled), false)
$$;

create or replace function public.has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select pr.role = 'admin' or coalesce(
             (pr.perms ->> p)::boolean,
             (select (s.value ->> p)::boolean from public.app_settings s where s.key = 'default_perms'),
             false)
    from public.profiles pr where pr.user_id = auth.uid() and not pr.disabled
  ), false)
$$;

-- True when the signed-in person created this section (used by the policies below; avoids a policy referring to itself).
create or replace function public.owns_topic(tid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.topics where id = tid and owner_id = auth.uid())
$$;

-- Creates the profile row for a user (first ever user becomes admin). Internal: not callable from the browser.
create or replace function public.make_profile(p_uid uuid, p_email text) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare r public.profiles; dp jsonb;
begin
  perform pg_advisory_xact_lock(727001);
  select * into r from public.profiles where user_id = p_uid;
  if found then
    if r.email = '' and coalesce(p_email,'') <> '' then update public.profiles set email = p_email where user_id = p_uid returning * into r; end if;
    return r;
  end if;
  select value into dp from public.app_settings where key = 'default_perms';
  insert into public.profiles (user_id, email, role, perms)
  values (p_uid, coalesce(p_email,''), case when exists (select 1 from public.profiles where role = 'admin') then 'user' else 'admin' end, coalesce(dp, '{}'::jsonb))
  returning * into r;
  return r;
end $$;
revoke all on function public.make_profile(uuid, text) from public, anon, authenticated;

create or replace function public.ensure_profile() returns public.profiles
language sql security definer set search_path = public as $$
  select * from public.make_profile(auth.uid(), auth.jwt() ->> 'email')
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public.make_profile(new.id, new.email); return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Never let the last active admin be demoted or disabled (that would lock everyone out of the console).
create or replace function public.guard_admins() returns trigger language plpgsql as $$
begin
  if old.role = 'admin' and not old.disabled and (new.role <> 'admin' or new.disabled)
     and not exists (select 1 from public.profiles where role = 'admin' and not disabled and user_id <> old.user_id) then
    raise exception 'There must always be at least one active admin.';
  end if;
  return new;
end $$;
drop trigger if exists profiles_guard_admins on public.profiles;
create trigger profiles_guard_admins before update on public.profiles for each row execute function public.guard_admins();

-- Every section the signed-in person may open. A section is reachable only if every section above it is too.
create or replace function public.visible_topic_ids() returns setof text
language sql stable security definer set search_path = public as $$
  with recursive ok(id) as (
    select t.id from public.topics t where t.parent_id is null and (
        t.owner_id = auth.uid() or t.access = 'everyone'
        or (t.access = 'selected' and exists (select 1 from public.topic_access a where a.topic_id = t.id and a.user_id = auth.uid())))
    union
    select c.id from public.topics c join ok on c.parent_id = ok.id where (
        c.owner_id = auth.uid() or c.access = 'everyone'
        or (c.access = 'selected' and exists (select 1 from public.topic_access a where a.topic_id = c.id and a.user_id = auth.uid())))
  )
  select id from ok where not exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.disabled)
  union
  select id from public.topics where public.is_admin()
$$;

-- ============================================================
-- 3. Row Level Security
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['app_settings','profiles','topics','questions','topic_access','question_access','progress','notes','topic_notes'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- profiles: you can read your own row; only an admin can change roles, permissions or disable accounts.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- settings
drop policy if exists settings_select on public.app_settings;
create policy settings_select on public.app_settings for select to authenticated using (true);
drop policy if exists settings_write on public.app_settings;
create policy settings_write on public.app_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- topics
drop policy if exists topics_select on public.topics;
create policy topics_select on public.topics for select to authenticated using (public.is_admin() or id in (select public.visible_topic_ids()));
drop policy if exists topics_insert on public.topics;
create policy topics_insert on public.topics for insert to authenticated with check (
  public.is_admin() or (
    owner_id = auth.uid() and access = 'hidden' and public.has_perm('own_content')
    and (parent_id is null or public.owns_topic(parent_id))));
drop policy if exists topics_update on public.topics;
create policy topics_update on public.topics for update to authenticated
  using (public.is_admin() or (owner_id = auth.uid() and public.has_perm('own_content')))
  with check (public.is_admin() or (
    owner_id = auth.uid() and access = 'hidden' and public.has_perm('own_content')
    and (parent_id is null or public.owns_topic(parent_id))));
drop policy if exists topics_delete on public.topics;
create policy topics_delete on public.topics for delete to authenticated
  using (public.is_admin() or (owner_id = auth.uid() and public.has_perm('own_content')));

-- questions: visible when the section is visible AND the question itself is not narrowed away from you
drop policy if exists questions_select on public.questions;
create policy questions_select on public.questions for select to authenticated using (
  public.is_admin() or (
    topic_id in (select public.visible_topic_ids())
    and (owner_id = auth.uid() or access = 'inherit'
         or (access = 'selected' and exists (select 1 from public.question_access a where a.question_id = questions.id and a.user_id = auth.uid())))));
drop policy if exists questions_insert on public.questions;
create policy questions_insert on public.questions for insert to authenticated with check (
  public.is_admin() or (
    owner_id = auth.uid() and access = 'inherit' and public.has_perm('own_content')
    and public.owns_topic(topic_id)));
drop policy if exists questions_update on public.questions;
create policy questions_update on public.questions for update to authenticated
  using (public.is_admin() or (owner_id = auth.uid() and public.has_perm('own_content')))
  with check (public.is_admin() or (
    owner_id = auth.uid() and access = 'inherit' and public.has_perm('own_content')
    and public.owns_topic(topic_id)));
drop policy if exists questions_delete on public.questions;
create policy questions_delete on public.questions for delete to authenticated
  using (public.is_admin() or (owner_id = auth.uid() and public.has_perm('own_content')));

-- access lists: admin manages them, people can read their own entries
drop policy if exists topic_access_select on public.topic_access;
create policy topic_access_select on public.topic_access for select to authenticated using (public.is_admin() or user_id = auth.uid());
drop policy if exists topic_access_write on public.topic_access;
create policy topic_access_write on public.topic_access for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists question_access_select on public.question_access;
create policy question_access_select on public.question_access for select to authenticated using (public.is_admin() or user_id = auth.uid());
drop policy if exists question_access_write on public.question_access;
create policy question_access_write on public.question_access for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- progress + notes: private to each person; clearing progress / writing notes needs the matching permission
drop policy if exists progress_select on public.progress;
create policy progress_select on public.progress for select to authenticated using (user_id = auth.uid());
drop policy if exists progress_insert on public.progress;
create policy progress_insert on public.progress for insert to authenticated with check (user_id = auth.uid());
drop policy if exists progress_update on public.progress;
create policy progress_update on public.progress for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists progress_delete on public.progress;
create policy progress_delete on public.progress for delete to authenticated using (user_id = auth.uid() and public.has_perm('reset'));

drop policy if exists notes_select on public.notes;
create policy notes_select on public.notes for select to authenticated using (user_id = auth.uid());
drop policy if exists notes_write on public.notes;
create policy notes_write on public.notes for all to authenticated using (user_id = auth.uid() and public.has_perm('notes')) with check (user_id = auth.uid() and public.has_perm('notes'));

-- topic notes: yours alone; writing needs the "notes" permission and a section you can actually see
drop policy if exists topic_notes_select on public.topic_notes;
create policy topic_notes_select on public.topic_notes for select to authenticated using (user_id = auth.uid());
drop policy if exists topic_notes_insert on public.topic_notes;
create policy topic_notes_insert on public.topic_notes for insert to authenticated with check (
  user_id = auth.uid() and public.has_perm('notes') and (public.is_admin() or topic_id in (select public.visible_topic_ids())));
drop policy if exists topic_notes_update on public.topic_notes;
create policy topic_notes_update on public.topic_notes for update to authenticated
  using (user_id = auth.uid() and public.has_perm('notes'))
  with check (user_id = auth.uid() and public.has_perm('notes') and (public.is_admin() or topic_id in (select public.visible_topic_ids())));
drop policy if exists topic_notes_delete on public.topic_notes;
create policy topic_notes_delete on public.topic_notes for delete to authenticated using (user_id = auth.uid());

-- ============================================================
-- 4. Functions the app calls
-- ============================================================
-- XP is added on the server so two browsers never overwrite each other.
create or replace function public.add_xp(gain int, streak int) returns int
language plpgsql security definer set search_path = public as $$
declare r int;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  perform public.make_profile(auth.uid(), auth.jwt() ->> 'email');
  update public.profiles set xp = xp + least(greatest(gain, 0), 50), best = greatest(best, least(greatest(streak, 0), 100000))
   where user_id = auth.uid() returning xp into r;
  return r;
end $$;

create or replace function public.reset_my_xp() returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.has_perm('reset') then raise exception 'Resetting progress is turned off for your account.'; end if;
  update public.profiles set xp = 0, best = 0 where user_id = auth.uid();
end $$;

-- Admin: set who can open a section (optionally everything inside it too).
create or replace function public.set_topic_access(p_topic text, p_mode text, p_users uuid[] default '{}', p_cascade boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare ids text[];
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_mode not in ('everyone','selected','hidden') then raise exception 'Bad access mode'; end if;
  with recursive d(id) as (
    select id from public.topics where id = p_topic
    union all
    select t.id from public.topics t join d on t.parent_id = d.id where p_cascade)
  select array_agg(id) into ids from d;
  if ids is null then return; end if;
  update public.topics set access = p_mode where id = any(ids);
  delete from public.topic_access where topic_id = any(ids);
  if p_mode = 'selected' then
    insert into public.topic_access (topic_id, user_id) select i, u from unnest(ids) i, unnest(p_users) u on conflict do nothing;
  end if;
end $$;

-- Admin: narrow one question (inherit = follows its section, selected = only these people, hidden = nobody but admins).
create or replace function public.set_question_access(p_question text, p_mode text, p_users uuid[] default '{}') returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if p_mode not in ('inherit','selected','hidden') then raise exception 'Bad access mode'; end if;
  update public.questions set access = p_mode where id = p_question;
  delete from public.question_access where question_id = p_question;
  if p_mode = 'selected' then
    insert into public.question_access (question_id, user_id) select p_question, u from unnest(p_users) u on conflict do nothing;
  end if;
end $$;

-- ============================================================
-- 5. Profiles for accounts that already exist (upgrade) + first admin
-- ============================================================
insert into public.profiles (user_id, email, perms)
select u.id, coalesce(u.email,''), (select value from public.app_settings where key = 'default_perms')
from auth.users u on conflict (user_id) do nothing;
update public.profiles p set email = u.email from auth.users u where u.id = p.user_id and p.email = '' and coalesce(u.email,'') <> '';
update public.profiles set role = 'admin'
 where user_id = (select user_id from public.profiles order by created_at, user_id limit 1)
   and not exists (select 1 from public.profiles where role = 'admin');
