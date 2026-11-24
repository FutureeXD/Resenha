-- Aplicar depois dos scripts anteriores, fora do horário de votação.
begin;
create table if not exists public.student_codes (
  ra text primary key check (ra ~ '^[0-9]{10}$'),
  level text not null check (level in ('fundamental','medio')),
  school_year integer not null,
  classroom text not null check (classroom ~ '^[A-H]$'),
  used boolean not null default false,
  check ((level='fundamental' and school_year between 6 and 9) or (level='medio' and school_year between 1 and 3))
);
alter table public.student_codes enable row level security;
revoke all on public.student_codes from public, anon, authenticated;
grant select, insert on public.student_codes to authenticated;
drop policy if exists "admin le ras" on public.student_codes;
create policy "admin le ras" on public.student_codes for select to authenticated using ((select auth.jwt()->'app_metadata'->>'election_admin') = 'true');
drop policy if exists "admin cadastra ras" on public.student_codes;
create policy "admin cadastra ras" on public.student_codes for insert to authenticated with check ((select auth.jwt()->'app_metadata'->>'election_admin') = 'true' and used = false);
create or replace function public.validar_ra(p_ra text) returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(p_ra ~ '^[0-9]{10}$' and exists(select 1 from public.student_codes where ra=p_ra and used=false) and exists(select 1 from public.election_config where id=1 and status='active'),false)
$$;
revoke all on function public.validar_ra(text) from public;
grant execute on function public.validar_ra(text) to anon, authenticated;

-- A validação e o consumo do RA e o voto são atômicos. Não salva RA na tabela de votos.
create or replace function public.votar_com_ra(p_ra text, p_candidate_number text, p_vote_type text)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.student_codes%rowtype; v_status text;
begin
  select status into v_status from public.election_config where id=1 for update;
  if v_status is distinct from 'active' then raise exception 'Votação não está ativa'; end if;
  if p_ra is null or p_ra !~ '^[0-9]{10}$' then raise exception 'Código inválido ou já utilizado'; end if;
  select * into c from public.student_codes where ra=p_ra for update;
  if not found or c.used then raise exception 'Código inválido ou já utilizado'; end if;
  if p_vote_type is null or not (coalesce(p_vote_type='blank' and p_candidate_number is null,false) or coalesce(p_vote_type='valid' and p_candidate_number ~ '^[0-9]{2,3}$' and exists(select 1 from public.candidates where number=p_candidate_number),false) or coalesce(p_vote_type='null' and p_candidate_number ~ '^[0-9]{2,3}$' and not exists(select 1 from public.candidates where number=p_candidate_number),false)) then raise exception 'Voto inválido'; end if;
  update public.student_codes set used=true where ra=p_ra;
  insert into public.votes(candidate_number,vote_type) values(p_candidate_number,p_vote_type);
  insert into public.class_participation(level,school_year,classroom,total) values(c.level,c.school_year,c.classroom,1)
    on conflict(level,school_year,classroom) do update set total=public.class_participation.total+1;
end $$;
revoke all on function public.votar_com_ra(text,text,text) from public;
grant execute on function public.votar_com_ra(text,text,text) to anon, authenticated;
revoke execute on function public.registrar_voto_aluno(text,text,text,integer,text,text) from public, anon, authenticated;
revoke execute on function public.registrar_voto_turma(text,text,text,integer,text) from public, anon, authenticated;
revoke insert, delete on public.votes from anon, authenticated;

-- Zerésima apaga votos e presença antiga e libera novamente os RAs cadastrados.
create or replace function public.zerar_eleicao() returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if auth.uid() is null or (auth.jwt()->'app_metadata'->>'election_admin') is distinct from 'true' then raise exception 'Acesso não autorizado'; end if;
  select status into v_status from public.election_config where id=1 for update;
  if v_status is distinct from 'waiting' then raise exception 'A eleição deve estar aguardando'; end if;
  delete from public.votes where id is not null;
  delete from public.class_participation where level is not null;
  delete from public.voter_attendance where id is not null;
  update public.student_codes set used=false where used=true;
end $$;
revoke all on function public.zerar_eleicao() from public;
grant execute on function public.zerar_eleicao() to authenticated;
commit;
