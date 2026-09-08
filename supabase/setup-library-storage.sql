insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('library', 'library', false, 52428800, null)
on conflict (id) do update
set public = false,
    file_size_limit = 52428800,
    allowed_mime_types = null;

drop policy if exists "library select own files" on storage.objects;
drop policy if exists "library insert own files" on storage.objects;
drop policy if exists "library update own files" on storage.objects;
drop policy if exists "library delete own files" on storage.objects;

create policy "library select own files"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'library'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "library insert own files"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'library'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "library update own files"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'library'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'library'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "library delete own files"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'library'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
