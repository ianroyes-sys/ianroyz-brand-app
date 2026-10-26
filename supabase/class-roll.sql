-- THE CLASS ROLL — schema for the shared Saturday wall.
--
-- Applied to the production Supabase project (
-- us-east-1, free tier). The "wall" bucket exists and is public, and the keys
-- are read by `ClassConfig` from `Config/Secrets.xcconfig`.
--
-- Anonymous sign-ins were enabled 2026-08-07 (Auth → Sign In / Providers →
-- Anonymous Sign-Ins). That setting is platform-side, not SQL — if the wall ever
-- goes read-only for everyone at once, check it first.
--
-- Every path below was exercised against this live project on 2026-08-07:
-- create class, enroll, upload, drop, keep, note, RPC read, own-delete, the
-- three-report takedown, and a second anonymous user failing to touch the
-- first one's rows.
--
-- Two behaviours worth knowing before you debug them twice:
--   * A taken-down frame cannot be deleted by its own author. A DELETE with a
--     WHERE needs SELECT visibility, and "drops readable" hides taken_down rows,
--     so the delete matches nothing. Harmless — the app never shows a taken-down
--     frame, so nobody can reach the menu — but it is not a broken policy.
--   * PostgREST answers 204 to a DELETE that matched zero rows, so a refused
--     delete looks identical to a successful one. Always verify the row, never
--     the status code.
--   * Public storage URLs are CDN-cached: a deleted object can still serve 200
--     for a while. Check storage.objects, not the URL.
--
-- Identity: every device gets an anonymous auth user. `author_id` is the app's
-- own profile UUID (stable across a reinstall of the same class), while
-- `auth_uid` is the Supabase user — RLS is written against `auth_uid`, so a
-- device can only ever write rows it owns.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------- classes

create table if not exists public.classes (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (char_length(code) between 3 and 12),
  name        text not null,
  started_at  timestamptz not null default now(),
  graduation  timestamptz not null,
  prompt      text,
  created_at  timestamptz not null default now()
);

create table if not exists public.members (
  class_id   uuid not null references public.classes(id) on delete cascade,
  member_id  text not null,                    -- the app's profile id
  auth_uid   uuid not null default auth.uid(),
  handle     text not null,
  name       text not null,
  joined_at  timestamptz not null default now(),
  primary key (class_id, member_id)
);

-- ------------------------------------------------------------------ drops

create table if not exists public.drops (
  id            uuid primary key,
  class_id      uuid not null references public.classes(id) on delete cascade,
  author_id     text not null,
  auth_uid      uuid not null default auth.uid(),
  author_handle text not null,
  author_name   text not null,
  author_avatar text,
  -- the develop Saturday, not the day it was shot: the whole class shares the
  -- develop moment, and the wall groups on exactly this
  week          date not null,
  dropped_at    timestamptz not null default now(),
  grade_id      text not null,
  caption       text check (char_length(caption) <= 280),
  path          text not null,                 -- object path inside the "wall" bucket
  taken_down    boolean not null default false
);

create index if not exists drops_class_week_idx on public.drops (class_id, week desc, dropped_at desc);

create table if not exists public.keeps (
  drop_id    uuid not null references public.drops(id) on delete cascade,
  member_id  text not null,
  auth_uid   uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (drop_id, member_id)
);

create table if not exists public.notes (
  id            uuid primary key,
  drop_id       uuid not null references public.drops(id) on delete cascade,
  author_id     text not null,
  auth_uid      uuid not null default auth.uid(),
  author_handle text not null,
  text          text not null check (char_length(text) between 1 and 140),
  created_at    timestamptz not null default now()
);

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  drop_id     uuid not null references public.drops(id) on delete cascade,
  class_id    uuid not null references public.classes(id) on delete cascade,
  reporter_id text not null,
  reason      text,
  created_at  timestamptz not null default now(),
  handled     boolean not null default false
);

-- Reports have to be answerable, not just collectable. Three on one frame and
-- it comes off the wall on its own, which is the promise the rules screen in
-- the app makes.
create or replace function public.autoremove_reported() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.reports where drop_id = new.drop_id) >= 3 then
    update public.drops set taken_down = true where id = new.drop_id;
  end if;
  return new;
end $$;

drop trigger if exists reports_autoremove on public.reports;
create trigger reports_autoremove after insert on public.reports
  for each row execute function public.autoremove_reported();

-- ------------------------------------------------------------- the wall RPC
--
-- One call per refresh. Folds keep counts, whether this viewer kept the frame,
-- and the notes into each row.

create or replace function public.class_wall(p_class uuid, p_viewer text, p_limit int default 500)
returns table (
  id uuid, class_id uuid, author_id text, author_handle text, author_name text,
  author_avatar text, week date, dropped_at timestamptz, grade_id text,
  caption text, path text, keeps int, kept_by_me boolean, notes json
)
language sql stable set search_path = public as $$
  select d.id, d.class_id, d.author_id, d.author_handle, d.author_name,
         d.author_avatar, d.week, d.dropped_at, d.grade_id, d.caption, d.path,
         (select count(*)::int from public.keeps k where k.drop_id = d.id) as keeps,
         exists (select 1 from public.keeps k
                  where k.drop_id = d.id and k.member_id = p_viewer) as kept_by_me,
         coalesce((select json_agg(json_build_object(
                     'id', n.id, 'author_id', n.author_id,
                     'author_handle', n.author_handle, 'text', n.text,
                     'created_at', n.created_at) order by n.created_at)
                   from public.notes n where n.drop_id = d.id), '[]'::json) as notes
    from public.drops d
   where d.class_id = p_class
     and d.taken_down = false
     -- a week that has not developed yet is not on the wall, server-side too
     and (d.week + time '18:40') <= now()
   order by d.dropped_at desc
   limit p_limit;
$$;

-- ------------------------------------------------------------------- RLS

alter table public.classes enable row level security;
alter table public.members enable row level security;
alter table public.drops   enable row level security;
alter table public.keeps   enable row level security;
alter table public.notes   enable row level security;
alter table public.reports enable row level security;

-- A class is findable by code (that's how joining works) and startable by anyone.
create policy "classes readable"  on public.classes for select using (true);
create policy "classes creatable" on public.classes for insert with check (auth.uid() is not null);

create policy "members readable" on public.members for select using (true);
create policy "members write own" on public.members for insert
  with check (auth.uid() = auth_uid);
create policy "members update own" on public.members for update
  using (auth.uid() = auth_uid);

-- Reading the wall goes through the RPC, but the table stays readable for
-- anything ad hoc. Writes are locked to the row's own author.
create policy "drops readable" on public.drops for select using (taken_down = false);
create policy "drops insert own" on public.drops for insert
  with check (auth.uid() = auth_uid);
create policy "drops delete own" on public.drops for delete
  using (auth.uid() = auth_uid);

create policy "keeps readable" on public.keeps for select using (true);
create policy "keeps insert own" on public.keeps for insert
  with check (auth.uid() = auth_uid);
create policy "keeps delete own" on public.keeps for delete
  using (auth.uid() = auth_uid);

create policy "notes readable" on public.notes for select using (true);
create policy "notes insert own" on public.notes for insert
  with check (auth.uid() = auth_uid);
create policy "notes delete own" on public.notes for delete
  using (auth.uid() = auth_uid);

-- Reports are write-only from the app: you can file one, you can't read the pile.
create policy "reports insert" on public.reports for insert
  with check (auth.uid() is not null);

-- A trigger function has no business being reachable at /rest/v1/rpc — the
-- Supabase security linter flags it, correctly.
revoke execute on function public.autoremove_reported() from anon, authenticated, public;

-- --------------------------------------------------------------- storage
--
-- Bucket "wall", public read. Objects are written under <class_id>/<drop_id>.jpg.

insert into storage.buckets (id, name, public)
values ('wall', 'wall', true)
on conflict (id) do nothing;

create policy "wall readable" on storage.objects for select
  using (bucket_id = 'wall');
create policy "wall writable" on storage.objects for insert
  with check (bucket_id = 'wall' and auth.uid() is not null);
create policy "wall owner deletes" on storage.objects for delete
  using (bucket_id = 'wall' and owner = auth.uid());
