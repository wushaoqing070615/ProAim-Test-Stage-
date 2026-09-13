-- 在 Supabase 的 SQL Editor 中完整运行一次。

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_]{3,24}$'),
  username_key text generated always as (lower(username)) stored unique,
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.calibration_runs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  original_dpi integer not null default 0 check (original_dpi = 0 or original_dpi between 100 and 3200),
  original_sensitivity numeric(8,4) not null default 0 check (original_sensitivity = 0 or original_sensitivity between 0.01 and 10),
  recommended_sensitivity numeric(8,4) not null default 0 check (recommended_sensitivity = 0 or recommended_sensitivity between 0.01 and 10),
  recommended_edpi integer not null default 0 check (recommended_edpi >= 0),
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists calibration_runs_user_started_idx on public.calibration_runs (user_id, started_at desc);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'username', ''), split_part(new.email, '@', 1)));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin');
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.calibration_runs enable row level security;
revoke all on public.profiles, public.calibration_runs from anon, authenticated;
grant select on public.profiles to authenticated;
grant select, insert, update on public.calibration_runs to authenticated;

drop policy if exists "profile self or admin read" on public.profiles;
create policy "profile self or admin read" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id or (select public.is_admin()));

drop policy if exists "admin run read" on public.calibration_runs;
create policy "admin run read" on public.calibration_runs
  for select to authenticated
  using ((select public.is_admin()));

drop policy if exists "owner run insert" on public.calibration_runs;
create policy "owner run insert" on public.calibration_runs
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "owner run update" on public.calibration_runs;
create policy "owner run update" on public.calibration_runs
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- 管理员创建方法：
-- 1. Authentication > Users > Add user
-- 2. Email 填 bluestamp@users.proaim.invalid，设置一个新的强密码并勾选 Auto Confirm User。
-- 3. 创建后回到 SQL Editor，只运行下面这条语句：
-- update public.profiles set username = 'BlueStamp', role = 'admin' where username_key = 'bluestamp';
