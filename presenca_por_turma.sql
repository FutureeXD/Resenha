-- Execute após supabase.sql, participacao_por_turma.sql e chapas_2_ou_3_digitos.sql.
-- Não apaga dados. Votos anteriores não possuem nome recuperável.
begin;
create table if not exists public.voter_attendance (
  id uuid primary key default gen_random_uuid(),
  student_name text not null check (char_length(btrim(student_name)) between 1 and 150),
  level text not null check (level in ('fundamental','medio')),
  school_year integer not null,
  classroom text not null check (classroom ~ '^[A-H]$'),
  check ((level = 'fundamental' and school_year between 6 and 9) or (level = 'medio' and school_year between 1 and 3))
);
create index if not exists voter_attendance_class_name_idx on public.voter_attendance (level, school_year, classroom, student_name);
alter table public.voter_attendance enable row level security;
revoke all on public.voter_attendance from public, anon, authenticated;
grant select on public.voter_attendance to authenticated;
drop policy if exists "admin le presenca" on public.voter_attendance;
create policy "admin le presenca" on public.voter_attendance for select to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'election_admin') = 'true');

-- As tabelas não compartilham ID. O nome e a escolha, porém, transitam na
-- mesma chamada; logs ou observação externa podem permitir correlação.
create or replace function public.registrar_voto_aluno(p_candidate_number text, p_vote_type text, p_level text, p_school_year integer, p_classroom text, p_student_name text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  select status into v_status from public.election_config where id = 1 for update;
  if v_status is distinct from 'active' then raise exception 'Votação não está ativa'; end if;
  if p_student_name is null or char_length(btrim(p_student_name)) not between 1 and 150 then raise exception 'Nome inválido'; end if;
  if p_level is null or p_school_year is null or p_classroom is null or not ((p_level = 'fundamental' and p_school_year between 6 and 9) or (p_level = 'medio' and p_school_year between 1 and 3)) or p_classroom !~ '^[A-H]$' then raise exception 'Turma inválida'; end if;
  if p_vote_type is null or not (coalesce(p_vote_type = 'blank' and p_candidate_number is null, false) or coalesce(p_vote_type = 'valid' and p_candidate_number ~ '^[0-9]{2,3}$' and exists (select 1 from public.candidates where number = p_candidate_number), false) or coalesce(p_vote_type = 'null' and p_candidate_number ~ '^[0-9]{2,3}$' and not exists (select 1 from public.candidates where number = p_candidate_number), false)) then raise exception 'Voto inválido'; end if;
  insert into public.votes (candidate_number, vote_type) values (p_candidate_number, p_vote_type);
  insert into public.class_participation (level, school_year, classroom, total) values (p_level, p_school_year, p_classroom, 1)
    on conflict (level, school_year, classroom) do update set total = public.class_participation.total + 1;
  insert into public.voter_attendance (student_name, level, school_year, classroom)
    values (btrim(p_student_name), p_level, p_school_year, p_classroom);
end $$;
revoke all on function public.registrar_voto_aluno(text,text,text,integer,text,text) from public;
grant execute on function public.registrar_voto_aluno(text,text,text,integer,text,text) to anon, authenticated;
revoke execute on function public.registrar_voto_turma(text,text,text,integer,text) from anon, authenticated;

-- Zerésima também apaga a lista nominal. Exige administrador e status waiting.
create or replace function public.zerar_eleicao()
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if auth.uid() is null or (auth.jwt() -> 'app_metadata' ->> 'election_admin') is distinct from 'true' then raise exception 'Acesso não autorizado'; end if;
  select status into v_status from public.election_config where id = 1 for update;
  if v_status is distinct from 'waiting' then raise exception 'A eleição deve estar aguardando'; end if;
  delete from public.votes where id is not null;
  delete from public.class_participation where level is not null;
  delete from public.voter_attendance where id is not null;
end $$;
revoke all on function public.zerar_eleicao() from public;
grant execute on function public.zerar_eleicao() to authenticated;
commit;
