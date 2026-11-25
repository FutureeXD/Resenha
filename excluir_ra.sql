-- Autoriza administradores a excluir apenas RAs não utilizados enquanto
-- a eleição estiver aguardando. Este script não exclui nenhum registro.
grant delete on public.student_codes to authenticated;
drop policy if exists "admin exclui ra disponivel" on public.student_codes;
create policy "admin exclui ra disponivel" on public.student_codes
for delete to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'election_admin') = 'true'
  and used = false
  and (select status from public.election_config where id = 1) = 'waiting'
);
