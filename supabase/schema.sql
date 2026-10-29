-- Secure MVP setup for Arshagon-chat.
-- Run this entire file in Supabase SQL Editor.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.chat_rooms (
  id text primary key,
  room_name text not null check (char_length(room_name) between 1 and 60),
  room_password_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id bigint generated always as identity primary key,
  room_id text not null references public.chat_rooms(id) on delete cascade,
  nickname text not null default 'ناشناس' check (char_length(nickname) between 1 and 24),
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_room_created_idx
  on public.chat_messages (room_id, created_at);

alter table public.chat_rooms enable row level security;
alter table public.chat_messages enable row level security;

-- No direct table access from browser clients.
revoke all on public.chat_rooms from anon, authenticated;
revoke all on public.chat_messages from anon, authenticated;
revoke all on sequence public.chat_messages_id_seq from anon, authenticated;

create or replace function public.create_chat_room(p_room_name text, p_password text)
returns table(room_code text, room_name text)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_code text;
begin
  if p_room_name is null or char_length(trim(p_room_name)) < 1 or char_length(p_room_name) > 60 then
    raise exception 'اسم اتاق باید بین ۱ تا ۶۰ حرف باشد';
  end if;
  if p_password is null or char_length(p_password) < 4 or char_length(p_password) > 64 then
    raise exception 'رمز باید بین ۴ تا ۶۴ کاراکتر باشد';
  end if;
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.chat_rooms(id, room_name, room_password_hash)
  values (v_code, trim(p_room_name), crypt(p_password, gen_salt('bf')));
  return query select v_code, trim(p_room_name);
end;
$$;

create or replace function public.join_chat_room(p_room_code text, p_password text)
returns table(room_code text, room_name text)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_room public.chat_rooms%rowtype;
begin
  select * into v_room from public.chat_rooms where id = upper(trim(p_room_code));
  if not found or p_password is null or v_room.room_password_hash <> crypt(p_password, v_room.room_password_hash) then
    raise exception 'کد اتاق یا رمز اشتباه است';
  end if;
  return query select v_room.id, v_room.room_name;
end;
$$;

create or replace function public.get_chat_messages(p_room_code text, p_password text, p_after_id bigint default 0)
returns table(id bigint, nickname text, body text, created_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_room public.chat_rooms%rowtype;
begin
  select * into v_room from public.chat_rooms where id = upper(trim(p_room_code));
  if not found or p_password is null or v_room.room_password_hash <> crypt(p_password, v_room.room_password_hash) then
    raise exception 'کد اتاق یا رمز اشتباه است';
  end if;
  return query
    select m.id, m.nickname, m.body, m.created_at
    from public.chat_messages m
    where m.room_id = v_room.id and m.id > coalesce(p_after_id, 0)
    order by m.id asc
    limit 100;
end;
$$;

create or replace function public.send_chat_message(p_room_code text, p_password text, p_nickname text, p_body text)
returns table(id bigint, nickname text, body text, created_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_room public.chat_rooms%rowtype;
  v_nickname text;
  v_body text;
begin
  select * into v_room from public.chat_rooms where id = upper(trim(p_room_code));
  if not found or p_password is null or v_room.room_password_hash <> crypt(p_password, v_room.room_password_hash) then
    raise exception 'کد اتاق یا رمز اشتباه است';
  end if;
  v_nickname := coalesce(nullif(trim(p_nickname), ''), 'ناشناس');
  v_body := trim(p_body);
  if char_length(v_nickname) > 24 then raise exception 'نام نمایشی حداکثر ۲۴ حرف است'; end if;
  if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 1000 then
    raise exception 'پیام باید بین ۱ تا ۱۰۰۰ کاراکتر باشد';
  end if;
  return query
    insert into public.chat_messages(room_id, nickname, body)
    values (v_room.id, v_nickname, v_body)
    returning public.chat_messages.id, public.chat_messages.nickname, public.chat_messages.body, public.chat_messages.created_at;
end;
$$;

revoke all on function public.create_chat_room(text, text) from public;
revoke all on function public.join_chat_room(text, text) from public;
revoke all on function public.get_chat_messages(text, text, bigint) from public;
revoke all on function public.send_chat_message(text, text, text, text) from public;

grant execute on function public.create_chat_room(text, text) to anon, authenticated;
grant execute on function public.join_chat_room(text, text) to anon, authenticated;
grant execute on function public.get_chat_messages(text, text, bigint) to anon, authenticated;
grant execute on function public.send_chat_message(text, text, text, text) to anon, authenticated;
