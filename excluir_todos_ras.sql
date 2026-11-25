-- Cria a função de exclusão, sem apagar RAs ao executar este script.
create or replace function public.excluir_todos_ras()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_status text; v_total integer;
begin
  if auth.uid() is null or (auth.jwt()->'app_metadata'->>'election_admin') is distinct from 'true' then
    raise exception 'Acesso não autorizado';
  end if;
  select status into v_status from public.election_config where id=1 for update;
  if v_status is distinct from 'waiting' then raise exception 'A eleição deve estar aguardando'; end if;
  lock table public.student_codes in share row exclusive mode;
  if exists (select 1 from public.votes) or exists (select 1 from public.student_codes where used=true) then
    raise exception 'Não é possível excluir os RAs enquanto houver votos ou códigos utilizados';
  end if;
  delete from public.student_codes where ra is not null;
  get diagnostics v_total = row_count;
  return v_total;
end $$;
revoke all on function public.excluir_todos_ras() from public, anon;
grant execute on function public.excluir_todos_ras() to authenticated;
