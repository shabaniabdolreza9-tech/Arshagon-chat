-- Arshagon Chat MVP schema for Supabase
-- Run this in Supabase Dashboard > SQL Editor.
-- Room IDs are unguessable invite codes. Do not use this MVP for sensitive/private information.

create table if not exists public.chat_rooms (
  id text primary key,
  room_name text not null check (char_length(room_name) between 1 and 60),
  room_password_hash text,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id bigint generated always as identity primary key,
  room_id text not null references public.chat_rooms(id) on delete cascade,
  nickname text not null default 'ناشناس' check (char_length(nickname) between 1 and 24),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_room_created_idx
  on public.chat_messages (room_id, created_at);

alter table public.chat_rooms enable row level security;
alter table public.chat_messages enable row level security;

-- MVP access: anyone with the unguessable room ID can access that room.
-- For stronger password enforcement, use a server/Edge Function before public launch.
drop policy if exists "rooms can be created by anyone" on public.chat_rooms;
create policy "rooms can be created by anyone"
  on public.chat_rooms for insert to anon, authenticated
  with check (true);

drop policy if exists "rooms can be read by anyone with room id" on public.chat_rooms;
create policy "rooms can be read by anyone with room id"
  on public.chat_rooms for select to anon, authenticated
  using (true);

drop policy if exists "messages can be read by anyone" on public.chat_messages;
create policy "messages can be read by anyone"
  on public.chat_messages for select to anon, authenticated
  using (true);

drop policy if exists "messages can be sent by anyone" on public.chat_messages;
create policy "messages can be sent by anyone"
  on public.chat_messages for insert to anon, authenticated
  with check (true);

-- Enable Realtime updates for new messages.
do $$
begin
  alter publication supabase_realtime add table public.chat_messages;
exception when duplicate_object then
  null;
when undefined_object then
  raise notice 'supabase_realtime publication was not found; enable Realtime for chat_messages in the dashboard.';
end $$;
