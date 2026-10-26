-- THE SATURDAY WALL — one open community, no schools or invite codes.
--
-- Apply once in the `ianroyz-class-roll` Supabase SQL Editor as the project
-- owner. The iOS app only has the publishable key, correctly; it cannot and
-- must not be able to change policy or create moderation rules itself.

-- Seed the canonical public room. The app can bootstrap this too, but making
-- it here means its identity is owned by the project rather than the first
-- person who happens to open the release.
insert into public.classes (code, name, started_at, graduation)
values ('SATURDAY', 'THE SATURDAY WALL', now(), now() + interval '20 years')
on conflict (code) do update set name = excluded.name;

-- The app's global event is one moment worldwide: Saturday at 6:40pm Houston
-- time. Compare both sides as Houston-local timestamps so UTC never exposes a
-- volume early. `class_wall` remains the only read path the app uses.
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
     and (d.week + time '18:40') <= timezone('America/Chicago', now())
   order by d.dropped_at desc
   limit p_limit;
$$;

-- Keep the existing RLS policies and three-report removal trigger from
-- class-roll.sql. Those are required for App Review 1.2 and now protect the
-- open wall rather than a school-only one.
