# Urna Digital

Simulador de urna eletrônica e painel administrativo com React, Vite, Tailwind CSS e Supabase. Não é uma urna oficial do TSE.

## Preparação

1. Crie um projeto Supabase e execute [supabase.sql](supabase.sql) no SQL Editor **uma única vez**, em um projeto novo.
2. Em Authentication, crie um usuário com e-mail e senha. No SQL Editor, autorize esse usuário substituindo o endereço abaixo:

   ```sql
   update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"election_admin":true}'::jsonb
   where email = 'admin@exemplo.com';
   ```

   Entre novamente para receber o JWT atualizado. Desative o cadastro público em Authentication se não for necessário.
3. Copie `.env.example` para `.env` e preencha `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` com a URL e a chave pública do projeto. Nunca use a chave `service_role` no navegador.
4. Com Node.js 20 ou superior instalado, execute `npm install` e `npm run dev`. A urna fica em `/` e o painel em `/admin`. Para produção, execute `npm run build` e configure o servidor para encaminhar `/admin` ao `index.html`.

O script cria o bucket público, habilita RLS e adiciona as tabelas à publicação Realtime. Pode ser necessário habilitar a Data API nas configurações do projeto. As sessões administrativas usam `sessionStorage`, e votos e candidatos ficam no Supabase; nenhum dado é persistido em `localStorage`.

## Operação

Cadastre candidatos com números de dois dígitos, ajuste o cargo e inicie a votação no painel. Depois de cada voto, a tela FIM permanece bloqueada até o mesário clicar em “Liberar próximo eleitor” ou usar Ctrl + Enter. A zerésima exige duas confirmações, só funciona no status “aguardando” e apaga todos os votos. O boletim e a zerésima podem ser impressos pelo navegador.

## Limitações importantes

Este projeto é um **simulador**, não um sistema eleitoral certificado. A inserção pública de votos, solicitada no escopo, permite a qualquer cliente enviar votos repetidos diretamente à API; a trava do mesário e o bloqueio de clique são controles de interface, não autenticação de eleitor nem proteção contra fraude. Não há auditoria independente, garantia de unicidade, operação offline, nem proteção de integridade equivalente à urna oficial. O registro contém data/hora, que pode permitir correlação com observação externa; não use para eleições que exijam sigilo ou integridade reais. Para uso sensível é necessário redesenhar e auditar o protocolo de votação.

O administrador pode alterar candidatos e o status durante a votação, o que pode afetar a interpretação dos resultados. Mantenha os cadastros estáveis durante uma eleição. O cálculo de resultados busca os votos em páginas e os agrega no navegador autenticado; para eleições grandes, substitua por agregação segura no banco. O script inicial não é uma migração idempotente completa: políticas existentes devem ser removidas antes de reaplicá-lo.
