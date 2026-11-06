-- إضافة تخزين متوافق مع بنية بيانات V8.1 دون حذف أو تعديل الجداول السابقة
-- شغّل هذا الملف مرة واحدة من Supabase SQL Editor.
create table if not exists public.app_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  collection text not null check (collection in ('c','p','m','f','a','audit','settings')),
  record_id text not null,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (user_id, collection, record_id)
);

create index if not exists app_records_user_collection_idx
  on public.app_records(user_id, collection);

alter table public.app_records enable row level security;

drop policy if exists "app_records_select_own" on public.app_records;
create policy "app_records_select_own" on public.app_records
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "app_records_insert_own" on public.app_records;
create policy "app_records_insert_own" on public.app_records
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "app_records_update_own" on public.app_records;
create policy "app_records_update_own" on public.app_records
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "app_records_delete_own" on public.app_records;
create policy "app_records_delete_own" on public.app_records
  for delete to authenticated using (auth.uid() = user_id);

-- لا تضع service_role key داخل التطبيق أو المتصفح.
-- لا ترفع financePin أو كلمات مرور المستخدمين المحليين ضمن payload.
