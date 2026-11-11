-- Pinned messages with role-checked mutations.
create table public.chat_pins (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  pinned_by uuid not null references public.profiles(id),
  pinned_at timestamptz not null default now(),
  unique (chat_id, message_id)
);
create index chat_pins_chat_pinned_idx on public.chat_pins(chat_id, pinned_at desc);
alter table public.chat_pins enable row level security;

create policy "Chat members can view pinned messages"
  on public.chat_pins for select to authenticated
  using (public.is_chat_member(chat_id));

create or replace function public.pin_chat_message(target_message uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  target_chat uuid;
  target_kind public.chat_kind;
  caller_role public.chat_member_role;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select chat_id into target_chat
  from public.messages where id = target_message;
  if target_chat is null then raise exception 'Message not found'; end if;

  select c.kind, m.role into target_kind, caller_role
  from public.chats c
  join public.chat_members m on m.chat_id = c.id
  where c.id = target_chat and m.user_id = caller;
  if target_kind is null then raise exception 'You are not a member of this chat'; end if;
  if target_kind <> 'direct' and caller_role not in ('owner', 'admin') then
    raise exception 'Only chat administrators can pin messages';
  end if;

  insert into public.chat_pins(chat_id, message_id, pinned_by)
  values (target_chat, target_message, caller)
  on conflict (chat_id, message_id) do nothing;
end;
$$;

create or replace function public.unpin_chat_message(
  target_chat uuid,
  target_message uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller uuid := auth.uid();
  target_kind public.chat_kind;
  caller_role public.chat_member_role;
begin
  if caller is null then raise exception 'Authentication required'; end if;
  select c.kind, m.role into target_kind, caller_role
  from public.chats c
  join public.chat_members m on m.chat_id = c.id
  where c.id = target_chat and m.user_id = caller;
  if target_kind is null then raise exception 'You are not a member of this chat'; end if;
  if target_kind <> 'direct' and caller_role not in ('owner', 'admin') then
    raise exception 'Only chat administrators can unpin messages';
  end if;
  delete from public.chat_pins
  where chat_id = target_chat and message_id = target_message;
end;
$$;

revoke all on function public.pin_chat_message(uuid) from public;
revoke all on function public.unpin_chat_message(uuid, uuid) from public;
grant execute on function public.pin_chat_message(uuid) to authenticated;
grant execute on function public.unpin_chat_message(uuid, uuid) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'chat_pins'
     ) then
    alter publication supabase_realtime add table public.chat_pins;
  end if;
end;
$$;
