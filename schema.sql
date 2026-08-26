-- ============================================================
-- Cyber Chat — Database Schema (Supabase / PostgreSQL)
-- Owner: امیرحسین سرافرازه
-- Run this in Supabase SQL Editor, top to bottom, on an empty project.
-- ============================================================

-- ---------- extensions ----------
create extension if not exists "uuid-ossp";
create extension if not exists pg_trgm; -- for fast search

-- ============================================================
-- 1. PROFILES  (1-1 with auth.users)
-- ============================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  first_name text not null default '',
  last_name text not null default '',
  bio text default '',
  phone text unique,
  avatar_url text,
  is_online boolean default false,
  last_seen timestamptz default now(),
  is_premium boolean default false,
  premium_started_at timestamptz,
  premium_expires_at timestamptz,
  is_banned boolean default false,
  is_suspended boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_profiles_username_trgm on public.profiles using gin (username gin_trgm_ops);

-- ============================================================
-- 2. USER SETTINGS (privacy / appearance / notifications)
-- ============================================================
create table if not exists public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  theme text default 'dark',                 -- 'dark' | 'light' | custom theme key
  last_seen_privacy text default 'everyone',  -- 'everyone' | 'contacts' | 'nobody'
  online_status_privacy text default 'everyone',
  profile_photo_privacy text default 'everyone',
  who_can_message text default 'everyone',    -- 'everyone' | 'contacts'
  who_can_add_to_groups text default 'everyone',
  notifications_enabled boolean default true,
  language text default 'fa'
);

-- ============================================================
-- 3. CONTACTS / BLOCKED USERS
-- ============================================================
create table if not exists public.contacts (
  owner_id uuid references public.profiles(id) on delete cascade,
  contact_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (owner_id, contact_id)
);

create table if not exists public.blocked_users (
  owner_id uuid references public.profiles(id) on delete cascade,
  blocked_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (owner_id, blocked_id)
);

-- ============================================================
-- 4. CHATS (private 1-1 + wraps groups/channels via type)
-- ============================================================
create table if not exists public.chats (
  id uuid primary key default uuid_generate_v4(),
  type text not null default 'private',  -- 'private' | 'group' | 'channel'
  created_at timestamptz default now()
);

create table if not exists public.chat_members (
  chat_id uuid references public.chats(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text default 'member',           -- 'member' | 'admin' | 'owner'
  joined_at timestamptz default now(),
  last_read_at timestamptz default now(),
  is_pinned boolean default false,
  primary key (chat_id, user_id)
);

-- ============================================================
-- 5. MESSAGES
-- ============================================================
create table if not exists public.messages (
  id uuid primary key default uuid_generate_v4(),
  chat_id uuid references public.chats(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  reply_to uuid references public.messages(id) on delete set null,
  forwarded_from uuid references public.messages(id) on delete set null,
  content text,
  message_type text default 'text',   -- 'text'|'image'|'video'|'file'|'voice'|'sticker'
  status text default 'sent',         -- 'sending'|'sent'|'delivered'|'read'
  is_edited boolean default false,
  is_deleted boolean default false,
  is_pinned boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_messages_chat_created on public.messages (chat_id, created_at desc);
create index if not exists idx_messages_content_trgm on public.messages using gin (content gin_trgm_ops);

create table if not exists public.message_attachments (
  id uuid primary key default uuid_generate_v4(),
  message_id uuid references public.messages(id) on delete cascade,
  storage_path text not null,
  file_name text,
  file_type text,
  file_size bigint,
  duration_seconds int,     -- for voice/video
  width int,
  height int
);

create table if not exists public.message_reactions (
  message_id uuid references public.messages(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz default now(),
  primary key (message_id, user_id, emoji)
);

-- ============================================================
-- 6. GROUPS
-- ============================================================
create table if not exists public.groups (
  id uuid primary key default uuid_generate_v4(),
  chat_id uuid unique references public.chats(id) on delete cascade,
  name text not null,
  description text default '',
  avatar_url text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.group_members (
  group_id uuid references public.groups(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text default 'member',   -- 'member'|'admin'|'owner'
  is_banned boolean default false,
  joined_at timestamptz default now(),
  primary key (group_id, user_id)
);

-- ============================================================
-- 7. CHANNELS
-- ============================================================
create table if not exists public.channels (
  id uuid primary key default uuid_generate_v4(),
  chat_id uuid unique references public.chats(id) on delete cascade,
  name text not null,
  username text unique not null,
  description text default '',
  avatar_url text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists public.channel_members (
  channel_id uuid references public.channels(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text default 'subscriber',  -- 'subscriber'|'admin'|'owner'
  joined_at timestamptz default now(),
  primary key (channel_id, user_id)
);

create table if not exists public.channel_posts (
  id uuid primary key default uuid_generate_v4(),
  channel_id uuid references public.channels(id) on delete cascade,
  author_id uuid references public.profiles(id),
  content text,
  is_pinned boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ============================================================
-- 8. NOTIFICATIONS
-- ============================================================
create table if not exists public.notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id) on delete cascade,
  type text not null,          -- 'message'|'mention'|'reply'|'group'|'channel'
  title text,
  body text,
  data jsonb default '{}',
  is_read boolean default false,
  created_at timestamptz default now()
);

-- ============================================================
-- 9. REPORTS
-- ============================================================
create table if not exists public.reports (
  id uuid primary key default uuid_generate_v4(),
  reporter_id uuid references public.profiles(id),
  target_type text not null,   -- 'user'|'message'|'group'|'channel'
  target_id uuid not null,
  reason text,
  status text default 'pending',  -- 'pending'|'reviewing'|'resolved'|'rejected'
  created_at timestamptz default now(),
  resolved_at timestamptz
);

-- ============================================================
-- 10. SUBSCRIPTIONS / PREMIUM (mock payment — no real card data ever)
-- ============================================================
create table if not exists public.subscriptions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid references public.profiles(id) on delete cascade,
  plan text default 'free',    -- 'free'|'premium'
  status text default 'active',
  started_at timestamptz default now(),
  expires_at timestamptz,
  activated_by uuid references public.profiles(id) -- admin who manually activated it
);

create table if not exists public.premium_features (
  key text primary key,
  label text not null,
  description text
);

-- ============================================================
-- 11. ADMIN ROLES / PERMISSIONS / AUDIT LOG
-- ============================================================
create table if not exists public.admin_roles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  role text not null default 'moderator',  -- 'owner'|'super_admin'|'moderator'|'support'
  granted_by uuid references public.profiles(id),
  granted_at timestamptz default now()
);

create table if not exists public.admin_permissions (
  role text not null,
  permission text not null,
  primary key (role, permission)
);

create table if not exists public.audit_logs (
  id uuid primary key default uuid_generate_v4(),
  admin_id uuid references public.profiles(id),
  action text not null,
  target_type text,
  target_id text,
  ip_address text,
  created_at timestamptz default now()
);

-- ============================================================
-- HELPER FUNCTION: is current user an admin (any role)?
-- ============================================================
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (select 1 from public.admin_roles where user_id = uid);
$$;

create or replace function public.is_owner(uid uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (select 1 from public.admin_roles where user_id = uid and role = 'owner');
$$;

-- ============================================================
-- TRIGGER: auto-create profile + settings row on signup
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, username, first_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)),
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    new.raw_user_meta_data->>'phone'
  );
  insert into public.user_settings (user_id) values (new.id);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.contacts enable row level security;
alter table public.blocked_users enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;
alter table public.message_reactions enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.channels enable row level security;
alter table public.channel_members enable row level security;
alter table public.channel_posts enable row level security;
alter table public.notifications enable row level security;
alter table public.reports enable row level security;
alter table public.subscriptions enable row level security;
alter table public.admin_roles enable row level security;
alter table public.audit_logs enable row level security;

-- profiles: everyone can read (needed for search/usernames), only owner can update own row
create policy "profiles_select_all" on public.profiles for select using (true);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id);
create policy "profiles_admin_update" on public.profiles for update using (public.is_admin(auth.uid()));

-- user_settings: only owner
create policy "settings_owner_all" on public.user_settings for all using (auth.uid() = user_id);

-- contacts / blocked: only owner
create policy "contacts_owner_all" on public.contacts for all using (auth.uid() = owner_id);
create policy "blocked_owner_all" on public.blocked_users for all using (auth.uid() = owner_id);

-- chats: visible only to members
create policy "chats_member_select" on public.chats for select using (
  exists (select 1 from public.chat_members cm where cm.chat_id = id and cm.user_id = auth.uid())
);
create policy "chats_member_insert" on public.chats for insert with check (auth.uid() is not null);

-- chat_members: visible to members of the same chat
create policy "chat_members_select" on public.chat_members for select using (
  exists (select 1 from public.chat_members cm2 where cm2.chat_id = chat_id and cm2.user_id = auth.uid())
);
create policy "chat_members_insert_self" on public.chat_members for insert with check (auth.uid() is not null);

-- messages: only chat members can read/write; sender must be self
create policy "messages_select_member" on public.messages for select using (
  exists (select 1 from public.chat_members cm where cm.chat_id = messages.chat_id and cm.user_id = auth.uid())
);
create policy "messages_insert_member" on public.messages for insert with check (
  sender_id = auth.uid() and
  exists (select 1 from public.chat_members cm where cm.chat_id = messages.chat_id and cm.user_id = auth.uid())
);
create policy "messages_update_own_or_admin" on public.messages for update using (
  sender_id = auth.uid() or public.is_admin(auth.uid())
);

-- attachments/reactions follow message visibility
create policy "attachments_select" on public.message_attachments for select using (
  exists (select 1 from public.messages m join public.chat_members cm on cm.chat_id = m.chat_id
          where m.id = message_id and cm.user_id = auth.uid())
);
create policy "attachments_insert" on public.message_attachments for insert with check (auth.uid() is not null);

create policy "reactions_select" on public.message_reactions for select using (
  exists (select 1 from public.messages m join public.chat_members cm on cm.chat_id = m.chat_id
          where m.id = message_id and cm.user_id = auth.uid())
);
create policy "reactions_owner_all" on public.message_reactions for all using (auth.uid() = user_id);

-- groups/channels: members can read; owners/admins manage
create policy "groups_member_select" on public.groups for select using (
  exists (select 1 from public.group_members gm where gm.group_id = id and gm.user_id = auth.uid())
);
create policy "groups_insert" on public.groups for insert with check (auth.uid() is not null);
create policy "groups_admin_update" on public.groups for update using (
  exists (select 1 from public.group_members gm where gm.group_id = id and gm.user_id = auth.uid() and gm.role in ('admin','owner'))
  or public.is_admin(auth.uid())
);

create policy "group_members_select" on public.group_members for select using (
  exists (select 1 from public.group_members gm2 where gm2.group_id = group_id and gm2.user_id = auth.uid())
);
create policy "group_members_insert" on public.group_members for insert with check (auth.uid() is not null);

create policy "channels_select_all" on public.channels for select using (true); -- channels are discoverable
create policy "channels_insert" on public.channels for insert with check (auth.uid() is not null);
create policy "channels_admin_update" on public.channels for update using (
  exists (select 1 from public.channel_members chm where chm.channel_id = id and chm.user_id = auth.uid() and chm.role in ('admin','owner'))
  or public.is_admin(auth.uid())
);

create policy "channel_members_select" on public.channel_members for select using (true);
create policy "channel_members_insert" on public.channel_members for insert with check (auth.uid() is not null);

create policy "channel_posts_select" on public.channel_posts for select using (true);
create policy "channel_posts_write_admin" on public.channel_posts for insert with check (
  exists (select 1 from public.channel_members chm where chm.channel_id = channel_id and chm.user_id = auth.uid() and chm.role in ('admin','owner'))
);

-- notifications: only owner
create policy "notifications_owner_all" on public.notifications for all using (auth.uid() = user_id);

-- reports: reporter can insert/read own; admins read all
create policy "reports_insert" on public.reports for insert with check (auth.uid() = reporter_id);
create policy "reports_select_own_or_admin" on public.reports for select using (
  auth.uid() = reporter_id or public.is_admin(auth.uid())
);
create policy "reports_update_admin" on public.reports for update using (public.is_admin(auth.uid()));

-- subscriptions: owner reads own; only admins can write (manual premium activation)
create policy "subscriptions_select_own_or_admin" on public.subscriptions for select using (
  auth.uid() = user_id or public.is_admin(auth.uid())
);
create policy "subscriptions_admin_write" on public.subscriptions for insert with check (public.is_admin(auth.uid()));
create policy "subscriptions_admin_update" on public.subscriptions for update using (public.is_admin(auth.uid()));

-- admin_roles: only owner can grant/revoke; admins can read the list
create policy "admin_roles_select" on public.admin_roles for select using (public.is_admin(auth.uid()));
create policy "admin_roles_owner_write" on public.admin_roles for insert with check (public.is_owner(auth.uid()));
create policy "admin_roles_owner_update" on public.admin_roles for update using (public.is_owner(auth.uid()));
create policy "admin_roles_owner_delete" on public.admin_roles for delete using (
  public.is_owner(auth.uid()) and role <> 'owner'
);

-- audit logs: admins can read; inserts happen via security-definer RPC only in real deployment
create policy "audit_logs_select_admin" on public.audit_logs for select using (public.is_admin(auth.uid()));
create policy "audit_logs_insert_admin" on public.audit_logs for insert with check (public.is_admin(auth.uid()));

-- ============================================================
-- SEED: default premium features + first Owner
-- ============================================================
insert into public.premium_features (key, label, description) values
  ('badge', 'نشان پرمیوم', 'نمایش نشان ویژه کنار نام کاربری'),
  ('themes', 'تم‌های ویژه', 'دسترسی به تم‌های اختصاصی پرمیوم'),
  ('larger_uploads', 'آپلود بزرگ‌تر', 'حجم مجاز آپلود فایل بیشتر'),
  ('animated_profile', 'پروفایل متحرک', 'آواتار و پروفایل انیمیشنی'),
  ('special_username', 'یوزرنیم اختصاصی', 'رزرو یوزرنیم‌های کوتاه/خاص')
on conflict do nothing;

-- NOTE: after your own first signup, run this manually with your real user id
-- to become the Owner (see README → "Admin Setup"):
--
-- insert into public.admin_roles (user_id, role) values ('<YOUR-AUTH-UID>', 'owner');
