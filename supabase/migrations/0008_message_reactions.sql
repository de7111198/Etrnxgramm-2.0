-- Secure per-user message reactions.
-- Clients can read reactions in chats they belong to; all writes go through
-- the membership-checked toggle RPC below.

create table public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (emoji in ('👍', '❤️', '😂', '😮', '😢', '🔥', '🎉')),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji)
);

create index message_reactions_chat_message_idx
  on public.message_reactions(chat_id, message_id);

alter table public.message_reactions enable row level security;

create policy "Chat members can view message reactions"
  on public.message_reactions for select to authenticated
  using (public.is_chat_member(chat_id));

create or replace function public.toggle_message_reaction(
  target_message uuid,
  reaction_emoji text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_chat uuid;
  removed_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if reaction_emoji not in ('👍', '❤️', '😂', '😮', '😢', '🔥', '🎉') then
    raise exception 'Unsupported reaction';
  end if;

  select chat_id into target_chat
  from public.messages
  where id = target_message
  for update;

  if target_chat is null then
    raise exception 'Message not found';
  end if;

  if not exists (
    select 1 from public.chat_members
    where chat_id = target_chat and user_id = current_user_id
  ) then
    raise exception 'You are not a member of this chat';
  end if;

  delete from public.message_reactions
  where message_id = target_message
    and user_id = current_user_id
    and emoji = reaction_emoji
  returning id into removed_id;

  if removed_id is not null then
    return false;
  end if;

  insert into public.message_reactions (message_id, chat_id, user_id, emoji)
  values (target_message, target_chat, current_user_id, reaction_emoji)
  on conflict (message_id, user_id, emoji) do nothing;

  return true;
end;
$$;

revoke all on function public.toggle_message_reaction(uuid, text) from public;
grant execute on function public.toggle_message_reaction(uuid, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'message_reactions'
     ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end;
$$;
