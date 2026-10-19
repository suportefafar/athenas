# Athenas

Buscador de documentos em um repositório global, em português brasileiro. Cada arquivo enviado é um lote independente. Rails 8.1, PostgreSQL 17 com Full-Text Search e pgvector, Active Storage Disk, Solid Queue e embeddings locais via Ollama. Não há integrações com Drive/SEI nem geração de respostas por LLM.

## Executar pelo Olympus

O ambiente local é gerenciado por `olymctl dev` e fica em **http://athenas.farmacia.local** (HTTPS também disponível com a CA local do Caddy). No workspace FAFAR:

```sh
olymctl dev up athenas --no-pull
olymctl dev status
olymctl dev ports
olymctl dev down athenas
```

O grupo `athenas` controla web, worker, Ollama e inicializadores de banco/modelo. O banco **athenas_development** e a fila ficam no `postgres-db` compartilhado do Olympus; não há outro PostgreSQL do Athenas nessa implantação. O overlay dev usa PostgreSQL 17 com pgvector, mantendo `olympus_postgres-data` e os demais bancos. Migrations e seed rodam em um inicializador antes de web/worker; o modelo é preparado antes do worker. O primeiro download do modelo pode demorar.

As credenciais PostgreSQL vêm de `olympus/.env`. O Compose substitui `DATABASE_URL` e `TEST_DATABASE_URL` pelos endereços internos do Olympus, impedindo que dotenv use os endereços standalone do `.env` montado, e injeta host/porta/usuário/senha compartilhados. As URLs internas não contêm credenciais: elas são combinadas com usuário/senha em `config/database.yml`. Configure `ADMIN_EMAIL` e `ADMIN_PASSWORD` em `athenas/.env` antes da primeira instalação; o seed nunca redefine uma conta existente. Para esta instalação local, a senha inicial foi gerada no arquivo privado `.env`, sem incluí-la no Git ou nos logs.

Web, worker e inicializador usam o bind mount `../athenas:/rails`: código, configuração, views e assets vêm do checkout local; uploads ficam em `storage/`, e e-mails capturados em `tmp/mail/`. O Rails recarrega alterações comuns em desenvolvimento; reinicie o worker após alterar código de jobs. Gems e o perfil do LibreOffice ficam na imagem, fora desse mount; mudanças de dependências ainda exigem rebuild. O modelo usa `athenas_ollama`, reaproveitando o cache local. Parar pelo `olymctl` preserva os dados. Os volumes antigos `olympus_athenas-storage` e `olympus_athenas-mail` foram preservados para recuperação. E-mails continuam em captura local, sem envio externo.

## Produção pelo Olympus

O domínio é **https://athenas.farmacia.ufmg.br**. A implantação usa `olymctl prod --remote up athenas`; o manifesto inicia web, worker, Ollama e inicializadores e atualiza o proxy. O banco `athenas_production` usa o PostgreSQL 17 compartilhado com pgvector; uploads e modelo ficam em volumes persistentes próprios.

Antes do primeiro deploy, prepare o checkout remoto com `olymctl prod --remote up athenas --prepare-only` e configure o arquivo privado `athenas/.env` no servidor a partir de `.env.production.example`. Preencha `SECRET_KEY_BASE`, `ADMIN_EMAIL` e `ADMIN_PASSWORD` (mínimo de 12 caracteres). O arquivo deve permanecer fora do Git, com permissão `600`. O seed cria a conta inicial uma vez e não redefine a senha depois. Convites e notificações são enviados pelo Hermes via `HERMES_API_URL`; crie um cliente de API no painel do Hermes e insira o token em `HERMES_API_TOKEN` antes de habilitar o envio de e-mails. O remetente padrão é o configurado no provedor SMTP do Hermes.

`--no-pull` usa os checkouts locais com as alterações atuais. Após revisar, commitar e publicar os repositórios Athenas/Olympus/reverse-proxy, o comando normal `olymctl dev up athenas` poderá atualizá-los pelo Git. O `olymctl` também prepara a entrada em `/etc/hosts` e recarrega as rotas do proxy.

## Iniciar com Docker (Linux)

Requisitos: Docker Engine e Compose, kernel Linux 5.13+ com Landlock e seccomp habilitados, cerca de 6 GB livres para imagens/modelo e memória disponível para LibreOffice/Ollama (recomendado 8 GB). Docker Desktop depende do kernel da sua VM. O isolamento falha de forma segura se o kernel não oferecer suporte.

```sh
cp .env.example .env
# Edite .env: ADMIN_EMAIL e ADMIN_PASSWORD (mínimo de 12 caracteres).
docker compose build
docker compose up -d db ollama
docker compose run --rm web bin/rails db:prepare db:seed
docker compose exec ollama ollama pull bge-m3
docker compose up -d web worker
docker compose run --rm web bin/rails athenas:doctor
```

Abra http://localhost:3000. Entre com as credenciais provisionadas. Em **Usuários**, crie uma conta comum; o convite permite definir a senha em até 48 horas. **Reenviar convite** invalida o anterior. O seed é idempotente: nunca muda a senha nem cria outro administrador. Não existe cadastro público ou promoção de usuários.

As credenciais `athenas:example` do Compose são exclusivamente de desenvolvimento; as portas são publicadas apenas em localhost. `DATABASE_URL`, `TEST_DATABASE_URL` e `OLLAMA_BASE_URL` são substituídas no Compose pelos endereços internos. `JOB_CONCURRENCY` do worker é fixado em 1 para não multiplicar processos pesados.

### E-mails de desenvolvimento

Em desenvolvimento, Action Mailer **sempre grava arquivos**, mesmo que variáveis SMTP estejam preenchidas; não envia a destinatários reais. Convites e notificações ficam no volume `mail`, acessível também no worker:

```sh
docker compose exec worker ls -lt tmp/mail
# Substitua NOME_DO_ARQUIVO pelo arquivo listado:
docker compose exec worker cat tmp/mail/NOME_DO_ARQUIVO
```

O convite contém um link de definição de senha, nunca uma senha. Não compartilhe esses arquivos. No uso nativo, consulte `tmp/mail/`. `APP_BASE_URL` deve ser o endereço acessível pelo navegador, usado nos links dos e-mails.

### Usar o fluxo completo

1. Entre, escolha **Enviar arquivos** e observe o aviso de repositório compartilhado.
2. Envie um ou mais arquivos. Limite: 10 × 1024 × 1024 bytes por arquivo; 100 páginas/quadros/slides para documentos paginados. As variáveis de limite podem reduzir esses tetos, nunca aumentá-los.
3. A resposta confirma recebimento imediatamente. **Meus uploads** mostra o estado em texto. O worker valida páginas e processa em segundo plano.
4. Consulte a notificação capturada; pesquise palavras do conteúdo e abra o lote. Downloads e previews passam por controllers autenticados.
5. O autor ou o administrador pode excluir o lote com confirmação. A exclusão remove a visibilidade e os dados de busca imediatamente; o worker purga o arquivo original. O evento de auditoria permanece.

## Desenvolvimento nativo

Ruby 3.4.9, Bundler 2.6+, PostgreSQL 17 com extensão pgvector e cliente PostgreSQL 17 (`psql` e `pg_dump`). Em Debian 13, as dependências do `Dockerfile` são a referência: Poppler, Tesseract e idiomas `por`/`eng`, LibreOffice Writer/Calc/Impress, Python 3/Pillow e libseccomp2. Mesmo nativamente, o processamento de documentos paginados exige Linux com Landlock.

```sh
cp .env.example .env
# Configure credenciais iniciais e os endereços locais.
docker compose up -d db ollama
bundle install
# Inicialize um perfil vazio, sem abrir documentos; a imagem Docker já faz isso:
libreoffice -env:UserInstallation=file://"$PWD/tmp/libreoffice-profile" --headless --terminate_after_init --nologo --nodefault --norestore
bin/setup
docker compose exec ollama ollama pull bge-m3
bin/dev
# Em outro terminal:
bin/jobs
```

O banco local usa a porta 55432 para evitar conflito com outras instalações. `bin/setup` prepara o banco e executa o seed; não inicia o worker. Os arquivos ficam em `storage/`. Não execute dois bancos na mesma porta. Para parar os serviços preservando os dados: `docker compose down` (não use `-v`).

## Testes e verificações

A suíte usa Minitest, PostgreSQL/pgvector reais, WebMock para Ollama e extratores simulados para falhas por etapa. Os testes reais exercitam Poppler, OCR de PNG/PDF digitalizado/TIFF, LibreOffice DOCX/XLSX e isolamento de processos. PPTX e os formatos ODF também têm caminhos testados com simulação de ferramentas.

```sh
docker compose up -d db
docker compose run --rm -e RAILS_ENV=test web bin/rails db:create db:migrate
docker compose run --rm -e RAILS_ENV=test -e RUN_EXTRACTION_TESTS=1 web bin/rails test
docker compose run --rm web bin/rails zeitwerk:check
docker compose run --rm web bundle exec brakeman --no-pager
```

No ambiente nativo, use `RAILS_ENV=test bin/rails db:create db:migrate` e `bin/rails test`. Sem `RUN_EXTRACTION_TESTS=1`, quatro testes dependentes das ferramentas locais são sinalizados como pulados. A CI deve executar o conjunto completo na imagem Docker.

O esquema SQL (`db/structure.sql`) preserva a configuração textual, trigger e tipos vetoriais. As tabelas Solid Queue residem no mesmo PostgreSQL, permitindo enfileiramento transacional. Para aplicar mudanças após editar código, reconstrua as imagens e execute `db:migrate` antes de iniciar web/worker.

## Processamento e limites dos extratores

- PDF: `pdfinfo` valida a contagem; `pdftotext` é aplicado por página. Somente páginas sem texto são renderizadas e submetidas ao Tesseract. Falhas por página preservam o texto das demais, com estado `partial` ao final.
- PNG, JPEG, WebP e TIFF: Pillow valida o arquivo e os quadros; Tesseract usa `por+eng`, com aviso ao usar apenas inglês. Há proteção contra imagens de dimensões excessivas.
- TXT, MD, CSV, JSON e XML: texto UTF-8, UTF-16 com BOM ou Windows-1252; sem inventar páginas. XML textual não é executado nem resolve entidades.
- DOCX/ODT e XLSX/ODS: leitura das estruturas XML para preservar parágrafos, tabelas e células; LibreOffice headless converte a PDF **para validar páginas efetivas**. Conversor ausente, corrupção ou falha de contagem impedem publicação.
- PPTX/ODP: cada slide é uma página. A extração lê texto dos slides. Notas, imagens embutidas, gráficos e OCR dentro de Office não têm cobertura completa no MVP; documentos complexos podem exigir exportação para PDF.
- Office: somente estruturas reconhecidas são abertas, sem descompactação no filesystem. Tetos de 2.000 entradas, 50 MB descompactados no total e 10 MB por entrada; macros, objetos embutidos, caminhos perigosos e entidades XML são rejeitados.
- Formatos sem suporte ficam `partial`, pesquisáveis apenas por nome/metadados, com aviso **conteúdo não extraído**. Binários enviados nunca são executados.

Subprocessos usam argumentos separados, diretórios temporários próprios, perfil LibreOffice inicializado copiado por job, ambiente sem credenciais da aplicação, timeout, grupo de processos e limites de CPU/memória/arquivos. O helper Linux aplica `no_new_privs`, seccomp para bloquear rede e Landlock para restringir filesystem a dependências e temporários. Somente sockets Unix locais são permitidos; o IPC do LibreOffice em `/tmp` tem permissão de criação de socket, sem permissão geral de leitura/escrita de arquivos. Sockets órfãos criados durante a execução são removidos com verificação de tipo, proprietário e ausência de serviço ativo. Não há execução sem isolamento em caso de falha. Os processos continuam sujeitos a vulnerabilidades dos parsers: mantenha as imagens atualizadas e execute o worker sem privilégios. Recursos totais do worker também são limitados pelo Compose.

Chunks têm aproximadamente 375 palavras (cerca de 500 tokens), sobreposição de 60 palavras (cerca de 80 tokens) e preferência por parágrafos. É uma aproximação de tokens, sem tokenizador externo. Os dados preparados só são persistidos/publicados no fim de uma transação. Um lock advisory PostgreSQL impede processamento concorrente; a publicação revalida a existência do lote sob lock de linha. Jobs reexecutados não duplicam chunks/notificações.

Falha persistente do Ollama (até três tentativas com timeout) mantém texto e índice lexical, publicando `partial`. Depois da primeira falha persistente não são feitas chamadas para todos os chunks restantes. Nenhum embedding usa API externa. Arquivos inválidos ou sem contagem confiável ficam `failed`; limites/segurança produzem `rejected`. Todos os estados finais geram notificação operacional sem o conteúdo do documento.

## Busca e embeddings

A trigger materializa um `tsvector` único por lote: conteúdo (A), nome (B) e metadados (C). A configuração portuguesa combina `unaccent` e stemming. `plainto_tsquery` usa AND e remove stopwords. Os termos podem estar em campos e trechos distintos. Índice GIN, relevância primeiro, recência e ID como desempate; 20 lotes por página. Não são exibidos snippets, ocorrências ou páginas. Se a diversidade de termos exceder o limite interno de 1 MB do `tsvector` do PostgreSQL, o lote termina como `partial`, com aviso e índice lexical de nome/metadados; texto e embeddings continuam preservados. Esse limite é do índice, não um novo limite de upload.

Se o **total lexical** for positivo, não há chamada semântica, mesmo numa página de resultados vazia. Somente com zero matches é gerado embedding da consulta no Ollama. A consulta pgvector exata usa distância cosseno e o melhor chunk de cada lote, sem duplicações. Só lotes `ready`/`partial` participam. Uma consulta só de stopwords solicita mais detalhes. Indisponibilidade semântica é informada explicitamente.

Padrão: `bge-m3`, vetor de **1024 dimensões**, validado na resposta. `EMBEDDING_DIMENSIONS` deve corresponder ao schema. Trocar dimensão exige migration; trocar modelo exige reindexar todos os embeddings e manter web/worker com a mesma configuração. Suspenda a busca semântica durante uma troca de modelo para não comparar espaços incompatíveis.

`SEMANTIC_MIN_SIMILARITY=0.60` é apenas ponto inicial. Separe consultas reais com documentos esperados e consultas sem correspondência. Compare resultados: aumente o limiar (por exemplo 0.70) para reduzir falsos positivos ou diminua (por exemplo 0.50) para recuperar mais resultados. Avalie precisão e cobertura; não escolha o valor pela quantidade de resultados.

```sh
# Reprocessa lotes pesquisáveis; eles ficam ocultos durante o job.
docker compose run --rm web bin/rails lots:reindex
# Recuperar um lote específico após corrigir uma dependência:
docker compose run --rm -e ID=123 web bin/rails lots:reindex
```

## Segurança e operação

Todas as rotas de domínio exigem sessão, incluindo download/preview. Rotas públicas do Active Storage estão desativadas e nenhum controller redireciona para URLs do storage. Tipos inline restritos a PDF/PNG/JPEG/WebP já processados; HTML/SVG são apenas downloads como octet-stream. Cookies HttpOnly/SameSite, CSRF, limitação de tentativas de login e HTTPS obrigatório em produção. A confirmação de exclusão é feita com Turbo.

O repositório é global: usuários autenticados consultam lotes de qualquer autor. Apenas o autor/admin exclui. O banco impede dois administradores; os fluxos normais não excluem/rebaixam o admin. Tokens de convite são aleatórios, armazenados como SHA-256, expiram e são de uso único. Sessões expiram em 14 dias.

Logs de aplicação usam nível warn; parâmetros sensíveis/consultas são filtrados, logs SQL e corpos de e-mail são desativados, argumentos de jobs não são registrados. Se houver proxy HTTP, configure-o para não registrar query strings nem caminhos de convite. E-mails de desenvolvimento contêm tokens: proteja o volume e faça sua limpeza periodicamente.

```sh
docker compose logs --tail=100 web worker
docker compose exec worker cat log/jobs.log
docker compose run --rm web bin/rails athenas:doctor
# Console de manutenção (não contém interface administrativa pública):
docker compose run --rm web bin/rails console
```

Jobs de entrega de e-mail e purge têm até três tentativas com espera crescente. O purge mantém o registro do blob até a exclusão no storage ter sucesso, permitindo retentar a limpeza. Consulte `SolidQueue::FailedExecution` no console para falhas e reexecuções. A fila não tem dashboard público. Para verificar pendências: `SolidQueue::Job.where(finished_at: nil).count`. A limpeza futura de `lot_accesses` pode remover eventos com mais de 30 dias; o índice por tempo suporta essa manutenção.

### Produção

Use um manifesto próprio, credenciais novas de PostgreSQL, `RAILS_ENV=production`, `SECRET_KEY_BASE` aleatório fora do Git, `APP_BASE_URL=https://...`, SMTP autenticado e storage persistente. `RAILS_MASTER_KEY` só é necessário se você adicionar credenciais Rails criptografadas; o projeto usa variáveis de ambiente. Configure HTTPS no proxy, restrição de hosts e rede privada para banco/Ollama. O SMTP recebe somente notificações e convites. O seed inicial exige credenciais e não as usa novamente após criar o admin. O `compose.yaml` standalone é para desenvolvimento; a implantação de produção é gerenciada pelo overlay do Olympus.

A portabilidade do storage está centralizada em `config/storage.yml`. Para migrar a S3/MinIO, configure um serviço Active Storage e migre blobs; controllers e domínio usam `open`, `download` e `purge`, sem depender de caminhos Disk.

### Backup e restauração

Faça backup coordenado do PostgreSQL e do volume de arquivos; um sem o outro é insuficiente. Guarde cópias criptografadas fora do host e teste restauração. Não envie backups ao Git. Durante a cópia, pare web/worker para impedir uploads/exclusões:

```sh
mkdir -p backups
docker compose stop web worker
docker compose exec -T db pg_dump -U athenas -Fc athenas_development > backups/database.dump
docker compose run --rm --no-deps -v "$PWD/backups:/backup" web tar -czf /backup/uploads.tar.gz -C storage .
docker compose start web worker
```

Restaure numa instalação vazia, com os mesmos arquivos de configuração e os serviços web/worker parados:

```sh
docker compose up -d db
docker compose exec -T db pg_restore -U athenas -d athenas_development --clean --if-exists < backups/database.dump
docker compose run --rm --no-deps -v "$PWD/backups:/backup:ro" web tar -xzf /backup/uploads.tar.gz -C storage
docker compose run --rm web bin/rails db:migrate
docker compose up -d web worker
```

A pasta `backups/` precisa ser gravável pelo UID 1000 da imagem para o comando de tar. Restaure em um volume vazio para não manter arquivos antigos. O cache/modelo Ollama pode ser baixado novamente; não substitui o backup dos documentos. Auditoria permanece no banco, mesmo após excluir um lote, sem conteúdo extraído.

### Diagnóstico

- `pending` sem progresso: confirme `worker`, banco e migrations; veja jobs com falha.
- `failed` ao validar PDF/Office/imagem: execute `athenas:doctor`; confira isolamento, ferramentas, integridade e limites do documento.
- `partial` com embeddings incompletos: confirme `ollama list`, baixe `bge-m3`, verifique memória e reindexe o lote.
- Sem matches e aviso de indisponibilidade: a lexical rodou; restaure o Ollama para habilitar fallback, sem serviços externos.
- E-mail não aparece: verifique worker e `tmp/mail`; em produção, confira SMTP sem imprimir credenciais.
- Erro de dump/schema: `psql`/`pg_dump` precisam ser compatíveis com PostgreSQL 17; a imagem já os inclui.
- Porta ocupada: ajuste mapeamentos e URLs locais ou pare o contêiner isolado usado nos testes.

Referências de implementação: [Active Storage e controllers autenticados](https://guides.rubyonrails.org/active_storage_overview.html#authenticated-controllers), [Solid Queue](https://github.com/rails/solid_queue), [pgvector](https://github.com/pgvector/pgvector), [API local de embeddings do Ollama](https://docs.ollama.com/api/embed).
