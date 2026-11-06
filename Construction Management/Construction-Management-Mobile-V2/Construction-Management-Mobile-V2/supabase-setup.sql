-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor
create table if not exists public.app_records (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.app_records enable row level security;
drop policy if exists "Users manage own construction record" on public.app_records;
create policy "Users manage own construction record" on public.app_records
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('construction-files','construction-files',false,52428800,null)
on conflict (id) do update set public=false;
drop policy if exists "Users access own construction files" on storage.objects;
create policy "Users access own construction files" on storage.objects
for all to authenticated
using (bucket_id='construction-files' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='construction-files' and (storage.foldername(name))[1]=auth.uid()::text);
