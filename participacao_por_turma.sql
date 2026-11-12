-- Execute após supabase.sql no SQL Editor. Não apaga votos anteriores.
begin;
create table if not exists public.class_participation (
  level text not null check (level in ('fundamental', 'medio')),
  school_year integer not null,
  classroom text not null check (classroom ~ '^[A-H]$'),
  total integer not null default 0 check (total >= 0),
  primary key (level, school_year, classroom),
  check ((level = 'fundamental' and school_year between 6 and 9) or (level = 'medio' and school_year between 1 and 3))
);
alter table public.class_participation enable row level security;
revoke all on public.class_participation from anon, authenticated;
grant select on public.class_participation to authenticated;
drop policy if exists "admin le participacao" on public.class_participation;
create policy "admin le participacao" on public.class_participation for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');

-- A operação pública é limitada a registrar um voto e incrementar uma contagem
-- na mesma transação. Não grava nome, identificador ou relação voto/turma.
create or replace function public.registrar_voto_turma(p_candidate_number text, p_vote_type text, p_level text, p_school_year integer, p_classroom text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  select status into v_status from public.election_config where id = 1 for update;
  if v_status is distinct from 'active' then raise exception 'Votação não está ativa'; end if;
  if p_level is null or p_school_year is null or p_classroom is null or not ((p_level = 'fundamental' and p_school_year between 6 and 9) or (p_level = 'medio' and p_school_year between 1 and 3)) or p_classroom !~ '^[A-H]$' then raise exception 'Turma inválida'; end if;
  if p_vote_type is null or not (coalesce(p_vote_type = 'blank' and p_candidate_number is null, false) or coalesce(p_vote_type = 'valid' and p_candidate_number ~ '^[0-9]{2}$' and exists (select 1 from public.candidates where number = p_candidate_number), false) or coalesce(p_vote_type = 'null' and p_candidate_number ~ '^[0-9]{2}$' and not exists (select 1 from public.candidates where number = p_candidate_number), false)) then raise exception 'Voto inválido'; end if;
  insert into public.votes (candidate_number, vote_type) values (p_candidate_number, p_vote_type);
  insert into public.class_participation (level, school_year, classroom, total) values (p_level, p_school_year, p_classroom, 1)
  on conflict (level, school_year, classroom) do update set total = public.class_participation.total + 1;
end $$;
revoke all on function public.registrar_voto_turma(text,text,text,integer,text) from public;
grant execute on function public.registrar_voto_turma(text,text,text,integer,text) to anon, authenticated;
revoke insert, delete on public.votes from anon, authenticated;

-- A zerésima limpa as duas tabelas em uma única transação, apenas para ADM.
create or replace function public.zerar_eleicao()
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if auth.uid() is null or (auth.jwt() -> 'app_metadata' ->> 'election_admin') is distinct from 'true' then raise exception 'Acesso não autorizado'; end if;
  select status into v_status from public.election_config where id = 1 for update;
  if v_status is distinct from 'waiting' then raise exception 'A eleição deve estar aguardando'; end if;
  delete from public.votes where id is not null;
  delete from public.class_participation where level is not null;
end $$;
revoke all on function public.zerar_eleicao() from public;
grant execute on function public.zerar_eleicao() to authenticated;
do $$ begin
  alter publication supabase_realtime add table public.class_participation;
exception when duplicate_object then null; end $$;
commit;
