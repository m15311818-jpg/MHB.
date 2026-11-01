-- MHB Gaming: قاعدة بيانات أولية لنظام ألعاب بنقاط افتراضية فقط.
-- نفّذ هذا الملف في Supabase SQL Editor بعد إنشاء مشروع جديد.
create extension if not exists pgcrypto;

create table if not exists public.players (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  points integer not null default 100 check (points >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.match_requests (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  game text not null check (game in ('domino','cards')),
  mode text not null check (mode in ('bot','person')),
  opponent_code text,
  status text not null default 'pending' check (status in ('pending','matched','rejected','finished')),
  created_at timestamptz not null default now()
);

alter table public.players enable row level security;
alter table public.admin_users enable row level security;
alter table public.match_requests enable row level security;

-- helper: هل المستخدم الحالي أدمن؟
create or replace function public.is_mhb_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.admin_users where user_id=auth.uid()); $$;

-- اللاعب ينشئ/يحدّث ملفه الخاص، ولا يستطيع تغيير حالة الموافقة أو النقاط.
drop policy if exists "player insert own profile" on public.players;
create policy "player insert own profile" on public.players for insert to authenticated
with check (id=auth.uid() and status='pending' and points=100);
drop policy if exists "player read own profile" on public.players;
create policy "player read own profile" on public.players for select to authenticated
using (id=auth.uid() or public.is_mhb_admin());
drop policy if exists "admin update players" on public.players;
create policy "admin update players" on public.players for update to authenticated
using (public.is_mhb_admin()) with check (public.is_mhb_admin());

drop policy if exists "admin read admins" on public.admin_users;
create policy "admin read admins" on public.admin_users for select to authenticated
using (user_id=auth.uid() or public.is_mhb_admin());

drop policy if exists "player create match request" on public.match_requests;
create policy "player create match request" on public.match_requests for insert to authenticated
with check (player_id=auth.uid() and exists(select 1 from public.players p where p.id=auth.uid() and p.status='approved'));
drop policy if exists "player read own requests" on public.match_requests;
create policy "player read own requests" on public.match_requests for select to authenticated
using (player_id=auth.uid() or public.is_mhb_admin());
drop policy if exists "admin update match requests" on public.match_requests;
create policy "admin update match requests" on public.match_requests for update to authenticated
using (public.is_mhb_admin()) with check (public.is_mhb_admin());

-- تفعيل Realtime على جدول اللاعبين لتصل الموافقة للعميل فوراً.
alter publication supabase_realtime add table public.players;
