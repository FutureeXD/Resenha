-- Atualiza a função sem apagar votos ao executar este script.
create or replace function public.zerar_eleicao()
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  if auth.uid() is null or (auth.jwt() -> 'app_metadata' ->> 'election_admin') is distinct from 'true' then
    raise exception 'Acesso não autorizado';
  end if;
  select status into v_status from public.election_config where id = 1 for update;
  if v_status is distinct from 'waiting' then raise exception 'A eleição deve estar aguardando'; end if;
  delete from public.votes where id is not null;
  delete from public.class_participation where level is not null;
end $$;
revoke all on function public.zerar_eleicao() from public;
grant execute on function public.zerar_eleicao() to authenticated;
