-- Execute após supabase.sql e participacao_por_turma.sql. Não apaga dados.
begin;
alter table public.candidates drop constraint if exists candidates_number_check;
alter table public.candidates add constraint candidates_number_check
  check (number ~ '^[0-9]{2,3}$');
alter table public.votes drop constraint if exists votes_check;
alter table public.votes add constraint votes_check
  check ((vote_type = 'blank' and candidate_number is null) or
    (vote_type in ('valid', 'null') and candidate_number ~ '^[0-9]{2,3}$'));

create or replace function public.registrar_voto_turma(p_candidate_number text, p_vote_type text, p_level text, p_school_year integer, p_classroom text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  select status into v_status from public.election_config where id = 1 for update;
  if v_status is distinct from 'active' then raise exception 'Votação não está ativa'; end if;
  if p_level is null or p_school_year is null or p_classroom is null or not ((p_level = 'fundamental' and p_school_year between 6 and 9) or (p_level = 'medio' and p_school_year between 1 and 3)) or p_classroom !~ '^[A-H]$' then raise exception 'Turma inválida'; end if;
  if p_vote_type is null or not (coalesce(p_vote_type = 'blank' and p_candidate_number is null, false) or coalesce(p_vote_type = 'valid' and p_candidate_number ~ '^[0-9]{2,3}$' and exists (select 1 from public.candidates where number = p_candidate_number), false) or coalesce(p_vote_type = 'null' and p_candidate_number ~ '^[0-9]{2,3}$' and not exists (select 1 from public.candidates where number = p_candidate_number), false)) then raise exception 'Voto inválido'; end if;
  insert into public.votes (candidate_number, vote_type) values (p_candidate_number, p_vote_type);
  insert into public.class_participation (level, school_year, classroom, total) values (p_level, p_school_year, p_classroom, 1)
  on conflict (level, school_year, classroom) do update set total = public.class_participation.total + 1;
end $$;
revoke all on function public.registrar_voto_turma(text,text,text,integer,text) from public;
grant execute on function public.registrar_voto_turma(text,text,text,integer,text) to anon, authenticated;
commit;
