-- Execute em um projeto novo no SQL Editor. O script não apaga dados existentes.
create table if not exists public.election_config (
  id integer primary key default 1 check (id = 1),
  title text not null default 'Presidente',
  status text not null default 'waiting' check (status in ('waiting','active','finished')),
  updated_at timestamptz not null default now()
);
insert into public.election_config(id) values (1) on conflict do nothing;
create table if not exists public.candidates (
  id uuid primary key default gen_random_uuid(),
  number text not null unique check (number ~ '^[0-9]{2}$'),
  name text not null check (length(trim(name)) > 0),
  vice_name text, party text not null, photo_url text, created_at timestamptz not null default now()
);
create table if not exists public.votes (
  id uuid primary key default gen_random_uuid(),
  candidate_number text,
  vote_type text not null check (vote_type in ('valid','blank','null')),
  created_at timestamptz not null default now(),
  check ((vote_type = 'blank' and candidate_number is null) or (vote_type in ('valid','null') and candidate_number ~ '^[0-9]{2}$'))
);
alter table public.election_config enable row level security;
alter table public.candidates enable row level security;
alter table public.votes enable row level security;
grant select on public.election_config, public.candidates to anon, authenticated;
grant insert on public.votes to anon, authenticated;
grant select, delete on public.votes to authenticated;
grant insert, update, delete on public.candidates to authenticated;
grant update on public.election_config to authenticated;

-- app_metadata é controlado pelo servidor, não pelo usuário. Marque o administrador
-- no SQL Editor: update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb) || '{"election_admin":true}'::jsonb where email = 'admin@exemplo.com';
create policy "config publica" on public.election_config for select to anon, authenticated using (true);
create policy "candidatos publicos" on public.candidates for select to anon, authenticated using (true);
create policy "administrador altera config" on public.election_config for update to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true') with check ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');
create policy "administrador gerencia candidatos" on public.candidates for all to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true') with check ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');
create policy "administrador le votos" on public.votes for select to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');
create policy "voto somente em eleicao ativa" on public.votes for insert to anon, authenticated with check (
  (select status = 'active' from public.election_config where id = 1)
  and ((vote_type = 'valid' and exists (select 1 from public.candidates where number = candidate_number))
    or (vote_type = 'null' and not exists (select 1 from public.candidates where number = candidate_number))
    or (vote_type = 'blank' and candidate_number is null))
);
create policy "administrador zera aguardando" on public.votes for delete to authenticated using ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true' and (select status = 'waiting' from public.election_config where id = 1));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('candidate-photos','candidate-photos',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy "fotos publicas" on storage.objects for select to anon, authenticated using (bucket_id = 'candidate-photos');
create policy "admin envia fotos" on storage.objects for insert to authenticated with check (bucket_id = 'candidate-photos' and (select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');
create policy "admin altera fotos" on storage.objects for update to authenticated using (bucket_id = 'candidate-photos' and (select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true') with check (bucket_id = 'candidate-photos' and (select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');
create policy "admin exclui fotos" on storage.objects for delete to authenticated using (bucket_id = 'candidate-photos' and (select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');
do $$ begin
  alter publication supabase_realtime add table public.election_config;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.candidates;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.votes;
exception when duplicate_object then null; end $$;
