# Athenas — Especificação do MVP

> **Documento de implementação para Codex**
> Idioma da aplicação e das mensagens: português brasileiro (`pt-BR`).
> Stack principal: Ruby on Rails, PostgreSQL, pgvector e embeddings locais.
> **Objetivo:** construir um aplicativo funcional, testado e executável — não apenas um protótipo visual.

## 1. Instruções ao agente implementador (Codex)

Implemente o **Athenas**, um buscador de informações provenientes de diferentes fontes. No MVP, **a única fonte real é upload de arquivos**. A arquitetura deve permitir a futura inclusão de arquivos do Google Drive e de documentos/processos do SEI, mas **não implemente essas integrações agora**.

Regras de execução:

1. Crie uma aplicação Rails convencional, simples, legível e com responsabilidades separadas. Prefira recursos nativos do Rails quando forem suficientes.
2. Entregue código executável, migrations, seeds, testes automatizados, configuração de desenvolvimento, configuração de worker, `README.md` e `.env.example` sem segredos.
3. Tome decisões técnicas menores não especificadas aqui, documentando-as no README. **Não altere as regras de produto deste documento.**
4. Implemente o fluxo completo (login → upload → job → indexação → e-mail → pesquisa → detalhes → exclusão).
5. Não exponha dados de arquivos por rotas públicas, links do Active Storage ou logs.
6. Execute migrations e testes, corrija os erros e entregue instruções exatas para iniciar a aplicação e suas dependências.
7. Se uma dependência local (OCR, modelo de embeddings, SMTP) estiver indisponível, reporte a condição com clareza e mantenha os comportamentos seguros previstos abaixo; nunca substitua o modelo local por um serviço externo.
8. Use esta especificação como fonte de verdade. As decisões mais recentes aqui descritas prevalecem sobre ideias anteriores.

## 2. Visão do produto

O Athenas é um **Ctrl+F sobre vários lotes ao mesmo tempo**, mas **retorna lotes**, não páginas nem ocorrências individuais. O usuário pesquisa palavras ou uma frase e recebe os lotes que correspondem à consulta.

A home deve ser **minimalista**, com um input de pesquisa centralizado, ação discreta para upload e uma lista dos lotes mais acessados nos últimos 30 dias abaixo da busca.

### 2.1. Conceito central: lote

Um **lote** é uma unidade de informação indexável e apresentável como um resultado único de busca:

- No MVP: **cada arquivo enviado é um lote independente**.
- No futuro: poderá ser um arquivo do Google Drive ou um documento, processo ou objeto JSON de serviço integrado (como o SEI).
- Um lote contém origem, identificador, título/nome, metadados, conteúdo textual extraído quando possível, estado da indexação e, no caso de upload, arquivo original.
- Se uma expressão aparecer 50 vezes no mesmo arquivo, a busca exibirá **um único resultado para aquele lote**.
- Chunks usados internamente na indexação **não são lotes** e não aparecem individualmente nos resultados.

### 2.2. Escopo obrigatório

- Login por e-mail/senha e sessão autenticada.
- Conta administrativa única provisionada na instalação.
- Admin cadastra usuários; usuários não podem se cadastrar sozinhos.
- Todos os usuários autenticados pesquisam e fazem upload em um **repositório global**.
- Upload de um ou mais arquivos, tratados individualmente, respeitando os limites por arquivo.
- Processamento assíncrono para validação de páginas, extração, OCR, indexação lexical e embeddings locais.
- E-mail informando o resultado do processamento ao autor do upload.
- Pesquisa lexical prioritária, com busca semântica **somente quando a lexical retornar zero lotes**.
- Resultados paginados, um por lote, ordenados por relevância e recência como desempate.
- Página de detalhes do lote, pré-visualização segura quando possível e download autenticado.
- Listagem de uploads do próprio usuário e exclusão autorizada; admin pode excluir qualquer lote.
- Registro de auditoria de exclusão.
- Home com lotes mais acessados nos últimos 30 dias.
- Tratamento explícito de indexação parcial.

### 2.3. Fora do escopo do MVP

- Integrações reais com Google Drive ou SEI.
- Chat com documentos, perguntas respondidas por LLM, RAG ou geração de resumos.
- Indexação híbrida simultânea: **não** execute lexical e semântica juntas.
- Busca com resultados por ocorrência, trecho ou número de página na interface.
- Permissões por lote, grupos, compartilhamento privado e cadastro público.
- Versionamento ou substituição de arquivos existentes.
- Bloqueio/deduplicação de arquivos de mesmo conteúdo.
- Painel de administração complexo, notificações em tempo real, indicadores sofisticados e API pública.

## 3. Stack técnica e arquitetura

Escolhas de implementação para viabilizar o MVP:

| Componente | Decisão |
|---|---|
| Backend e UI | Rails 8+, Ruby compatível, ERB/Hotwire e CSS simples; evitar SPA React desnecessária |
| Banco | PostgreSQL (não SQLite), com extensões `vector` e `unaccent` |
| Busca lexical | PostgreSQL Full-Text Search (`tsvector`, `tsquery`, índice GIN) |
| Busca semântica | `pgvector`, com comparação por distância cosseno |
| Embeddings | **Modelo local**, usando Ollama; padrão sugerido `bge-m3` (1024 dimensões, multilíngue) |
| Jobs | Active Job com **Solid Queue**, worker em processo separado |
| Arquivos originais | Active Storage com serviço `Disk` e volume persistente, preparado para migração futura a S3/MinIO |
| E-mails | Action Mailer com SMTP configurado por ambiente |
| PDF e OCR | Poppler (`pdfinfo`, `pdftotext`, ferramentas de renderização) e Tesseract com idioma `por` (e fallback `eng` quando adequado) |
| Office | Extratores seguros por formato e, quando necessário, LibreOffice headless para conversão/contagem de páginas |
| Infra local | Docker Compose ou alternativa reprodutível com web, worker, PostgreSQL/pgvector e Ollama |
| Testes | Testes Rails (Minitest ou RSpec, escolha um só) com fixtures/factories e serviços externos simulados |

**Não é obrigatório usar um índice vetorial aproximado no início.** Prefira consulta exata pgvector no pequeno volume inicial; quando necessário, adicionar índice HNSW com operações de cosseno sem mudar a interface de busca.

**Portabilidade do storage:** centralizar a configuração no Active Storage; não acoplar a lógica de upload, preview, download ou processamento a caminhos locais, para permitir migração posterior para S3/MinIO sem reescrever o domínio.

**Privacidade:** nenhum conteúdo deve ser enviado a APIs externas para embeddings, OCR, extração ou busca. O SMTP recebe apenas notificações operacionais, nunca conteúdo integral de documentos.

## 4. Usuários, autenticação e autorização

### 4.1. Papéis

- `admin`: **uma única conta**, criada por seed/provisionamento. Pode cadastrar contas de usuários, pesquisar, fazer upload, ver lotes e excluir qualquer lote.
- `user`: pode pesquisar, fazer upload, ver qualquer lote global e **excluir somente lotes dos quais é autor**.
- O sistema inteiro requer autenticação, exceto login e fluxos seguros de recuperação de senha, caso implementados.
- Não há formulário/rota pública de cadastro nem opção de promover outro usuário a admin.

### 4.2. Provisionamento seguro do admin

- Seed idempotente: cria o admin **somente se ele ainda não existir**; execuções futuras não apagam nem redefinem suas credenciais.
- Ler `ADMIN_EMAIL` e `ADMIN_PASSWORD` de variáveis de ambiente **no provisionamento inicial**. Nunca colocar senha fixa no repositório ou no seed.
- Em produção, falhar com mensagem clara se as credenciais iniciais não estiverem presentes na primeira instalação.
- Proteger a unicidade do papel admin também no banco (índice único parcial, por exemplo), não apenas no código.
- Não permitir apagar ou rebaixar o único administrador pelo fluxo normal.
- O admin cria usuários informando e-mail e nome. Usar fluxo seguro de definição de senha (token de convite/definição ou senha temporária com troca obrigatória), **sem enviar senhas em texto puro por e-mail**.
- Considerar a autenticação nativa do Rails 8 como base, com controle de autorização explícito.

### 4.3. Regra de visibilidade

Todos os lotes pesquisáveis são visíveis para **todos os usuários autenticados**, independentemente de quem os enviou. A interface de upload deve advertir: "Os arquivos enviados poderão ser consultados por todos os usuários do Athenas".

## 5. Limites e aceitação de uploads

- **Máximo de 10 MB por arquivo** (10 × 1024 × 1024 bytes, definido de forma explícita).
- **Máximo de 100 páginas por documento paginado**.
- Para arquivos sem conceito confiável de página (`TXT`, `CSV`, `JSON` etc.), aplicar o limite de 10 MB, sem inventar uma contagem de páginas.
- Para formatos com páginas, inclusive PDF e documentos do Office que precisem ser renderizados, validar o número efetivo de páginas com ferramentas adequadas. Para PPTX, slides podem ser tratados como páginas. Para TIFF multipágina, considerar quadros/páginas.
- A validação de 10 MB deve ocorrer **antes de persistir o upload**, no servidor; validação de página pode ocorrer no job, pois pode exigir conversão.
- Se ultrapassar 100 páginas, mudar status para `rejected`, não indexar, não publicar e avisar o autor por e-mail. A primeira tela de upload informa que a validação de páginas acontecerá em background.
- Não criar limite arbitrário de quantidade de uploads por usuário no MVP.
- Permitir upload de arquivos idênticos: mesmo hash/conteúdo não bloqueia criação de novos lotes.
- Cada atualização de documento é **outro upload e outro lote**; versões antigas ficam disponíveis até exclusão manual.

### 5.1. Cobertura de formatos

Tentar extrair conteúdo de tantos formatos seguros quanto viável, pelo menos:

1. PDFs textuais e PDFs digitalizados (OCR para páginas sem texto extraível).
2. Arquivos de imagem comuns (`PNG`, `JPEG`, `TIFF`, `WebP`, conforme suporte local), via OCR.
3. Texto puro e dados (`TXT`, `MD`, `CSV`, `JSON`, `XML`, com tratamento de encoding).
4. Documentos de escritório (`DOCX`, `ODT`, `PPTX`, `ODP`, `XLSX`, `ODS`) incluindo texto em tabelas, células e slides.

Para **outros formatos**, tentar identificar o MIME real e selecionar um extrator seguro; quando não houver suporte, **não executar o arquivo**. Armazenar o lote com nome e metadados pesquisáveis, sinalizando `partial` e o motivo "conteúdo não extraído". Arquivos corrompidos/perigosos devem ser tratados sem execução e com erro compreensível. Não descompactar arquivos compactados arbitrários (risco de zip bomb).

Nunca executar macros, JavaScript embutido, código ou binários enviados. As conversões devem ter timeout, limite de recursos, arquivos temporários isolados, subprocessos chamados com argumentos seguros (sem interpolação em shell) e limpeza de temporários.

## 6. Fluxo de upload, extração e publicação

### 6.1. Interface após upload

Ao receber o arquivo dentro do limite de tamanho, salvar um registro de lote com status inicial `pending` e enfileirar processamento.

Exibir uma mensagem simples e voltar à navegação normal, **sem spinner/loader persistente**:

> Arquivo recebido. Ele será processado em segundo plano. Você receberá um e-mail quando o processamento terminar.

Se a validação posterior falhar, o e-mail deve informar rejeição ou falha e o motivo.

### 6.2. Máquina de estados

| Estado | Significado | Aparece na pesquisa? |
|---|---|---|
| `pending` | Upload recebido, aguardando job | Não |
| `processing` | Validação/extrator/OCR/embeddings em andamento | Não |
| `ready` | Indexação concluída sem falhas conhecidas | Sim |
| `partial` | Processamento terminou, mas parte do conteúdo/indexação falhou ou não é suportada | **Sim**, com aviso |
| `failed` | Falha que impede qualquer indexação utilizável | Não |
| `rejected` | Violou limite ou restrição de segurança | Não |

**Regra final de consistência:** um lote **nunca** fica pesquisável enquanto está em `pending` ou `processing`. Ao terminar o job, publique atomicamente como `ready` ou `partial`. Essa regra incorpora a decisão posterior de permitir indexação parcial: se, por exemplo, o OCR falhar na página 80, as demais páginas já extraídas poderão ficar pesquisáveis após o encerramento do processamento. Marque a condição incompleta de forma visível, tanto em resultados quanto na página de detalhes.

### 6.3. Pipeline do job

1. Revalidar existência do lote, arquivo e segurança; evitar processamento concorrente do mesmo lote.
2. Validar MIME real, tamanho e número máximo de páginas (quando aplicável).
3. Extrair nome e metadados úteis: tipo, tamanho, título interno, autor interno, datas, páginas (quando disponíveis), origem, uploader, data do upload.
4. Extrair o conteúdo textual. Para PDF, tentar texto embutido primeiro e aplicar OCR **às páginas que precisarem**, evitando OCR desnecessário. Para imagens, aplicar OCR.
5. Coletar erros por página/etapa sem descartar conteúdo obtido com sucesso; nunca publicar resultados antes da conclusão do job.
6. Normalizar espaços, quebras e encoding preservando o conteúdo necessário para busca; não alterar o arquivo original.
7. Dividir o conteúdo extraído em chunks apropriados (padrão inicial: cerca de 500 tokens com sobreposição de cerca de 80, preferindo limites de parágrafos). Cada chunk pertence a um lote.
8. Gerar embeddings **localmente** dos chunks via Ollama. Não usar embeddings externos. Se houver falha persistente em parte dos embeddings, preservar a busca lexical do que foi extraído e sinalizar `partial`.
9. Construir/atualizar a representação lexical do lote a partir de **conteúdo + nome + metadados**.
10. Publicar status `ready` ou `partial` **somente depois de terminar as etapas e persistir os índices utilizáveis**. Se nada indexável estiver disponível, marcar `failed`.
11. Enviar e-mail final ao autor com nome, status, eventual motivo e link autenticado para os detalhes.

**Confiabilidade:** jobs idempotentes, retries limitados para erros transitórios (ex.: Ollama indisponível), sem duplicar chunks; timeouts e tratamento diferenciado para erros permanentes. Ao reexecutar, substituir de forma consistente índices provisórios do lote. Se o arquivo for excluído durante o processamento, o job deve abortar sem recriar índices nem publicar o lote. Em falhas sem publicação, não expor dados provisórios nas consultas.

**Observação sobre sucesso parcial:** caso um arquivo não tenha texto extraível, mas seja seguro e possua nome/metadados, ele pode ficar `partial` com apenas esses campos pesquisáveis. Não declarar que seu conteúdo foi indexado. Um arquivo ilegível, inválido ou cuja verificação de limites não possa ser concluída com segurança não deve ser liberado para pesquisa.

## 7. Busca

### 7.1. Contrato de pesquisa

A busca retorna **lotes distintos**. A query é aplicada ao conjunto de nome, conteúdo extraído e metadados de **cada lote**.

- A pesquisa lexical usa a lógica **AND entre todos os termos relevantes**: ignorar conectivos/stopwords do português, normalizar flexões quando suportado e manter comportamento coerente com palavras acentuadas.
- Termos podem estar em **campos diferentes do mesmo lote** (ex.: "relatório" no nome, "financeiro" no conteúdo e "2025" nos metadados); isso deve contar como match.
- **Peso maior para correspondências no conteúdo**, seguido por nome e, depois, metadados.
- Ordenar resultados por pontuação de relevância; **recência como desempate** ou fator secundário de baixo impacto para pontuações semelhantes; ordem estável por ID para paginação consistente.
- Exibir uma única linha/card por lote; **não** renderizar trechos, página, posição ou ocorrências individuais no MVP.
- Somente considerar lotes `ready` ou `partial`.
- Paginar (padrão 20 lotes por página) e mostrar quantidade encontrada, quando viável.

### 7.2. Primeiro estágio — lexical

Usar PostgreSQL Full-Text Search com configuração para português e extensão `unaccent`/configuração equivalente, de modo consistente na indexação e na consulta.

Criar uma representação textual de busca por lote (ex.: `lots.search_vector` materializada) com pesos:

- `A`: conteúdo textual extraído;
- `B`: nome/título;
- `C`: texto pesquisável dos metadados.

Criar índice `GIN` e construir a query por `plainto_tsquery` (ou equivalente com AND e normalização). **Não** fazer AND apenas dentro de um chunk: é necessário que os termos possam estar distribuídos por vários campos e por diferentes trechos do mesmo lote.

Se a query não contiver termos pesquisáveis após normalização (ex.: só stopwords), apresentar mensagem solicitando uma consulta mais específica em vez de produzir resultados arbitrários.

### 7.3. Segundo estágio — semântica, somente como fallback

**Regra essencial:**

1. Executar primeiro a busca lexical.
2. **Se ela encontrar pelo menos um lote, retornar apenas os resultados lexicais. Não executar busca semântica.**
3. **Somente se o total lexical for zero**, gerar o embedding da consulta localmente e consultar os embeddings dos chunks no pgvector.
4. Agregar por lote (`DISTINCT` ou `GROUP BY`), escolhendo o melhor score de chunk como relevância do lote; não repetir o mesmo lote.
5. Aplicar limite/limiar de similaridade configurável e documentado, evitando apresentar resultados irrelevantes só para preencher uma página.
6. Ordenar por similaridade e, em caso de pontuações equivalentes, por recência.
7. Indicar discretamente na interface "Resultados por similaridade semântica" quando esse fallback for usado.

Se o serviço local de embeddings estiver indisponível e não houver resultados lexicais, exibir aviso honesto de que a busca semântica está temporariamente indisponível. **Não** utilizar um serviço externo como fallback.

Modelo de partida sugerido: `bge-m3` do Ollama, dimensão **1024**. Manter modelo e dimensão configurados/documentados, validar a dimensão retornada e deixar explícito que trocar de modelo/dimensão exige **reindexação dos embeddings**.

### 7.4. Exemplos esperados

- Consulta `afastamento para capacitação`: pode encontrar lote que contenha "afastamento" e "capacitação" em qualquer ordem, ignorando "para" conforme a configuração de português.
- Consulta `relatório financeiro 2025`: retorna lote com palavras distribuídas entre nome, conteúdo e metadados.
- Consulta que obtém um único match lexical: **não** invoca Ollama para pesquisa semântica.
- Consulta sem resultados lexicais: executa busca vetorial e exibe cada lote correspondente **uma única vez**.

## 8. Páginas e experiência de uso

### 8.1. `/` — home autenticada

- Cabeçalho discreto com marca **Athenas**, usuário autenticado, ação **Enviar arquivos**, **Meus uploads** e sair; link de administração só para admin.
- Campo de texto de busca **centralizado** e ação de pesquisar; envio também por Enter.
- Abaixo, título "Mais acessados nos últimos 30 dias" e lista simples de lotes com link para detalhes.
- Se ainda não houver registros de acesso, exibir estado vazio amigável.
- Visual limpo, responsivo, acessível (labels, foco, contraste), sem dashboard complexo.

### 8.2. `/search?q=...` — resultados

- Busca preservada no campo do topo.
- Lista paginada: nome do lote, tipo, origem, data de inclusão, metadados básicos e aviso `Indexação incompleta` quando aplicável.
- Link do lote para detalhes.
- Sinalização discreta de resultados lexicais vs. semânticos.
- Estado vazio útil; erros de infraestrutura não devem ser confundidos com "nenhum resultado".

### 8.3. Upload

- Pode ser botão/modal/página dedicada, com formulário acessível de seleção de arquivo(s).
- Mostrar limites **10 MB e 100 páginas** e aviso de repositório global.
- Confirmar recebimento e informar notificação por e-mail; **sem loading de extração/indexação em tela**.
- Rejeitar imediatamente arquivo acima de 10 MB; comunicar rejeição posterior quando o arquivo ultrapassar 100 páginas ou não puder ser validado com segurança.
- Cada arquivo enviado cria um lote separado, inclusive quando idêntico a outro.

### 8.4. `/lots/:id` — detalhes

- Nome, MIME/formato, tamanho, origem, data do upload, autor, metadados extraídos, número de páginas quando conhecido e estado da indexação.
- Ação de **pré-visualizar** quando seguro e suportado, e **download** autenticado do arquivo original.
- Para PDF e imagem, preferir pré-visualização simples no navegador; para formatos não suportados, oferecer download sem prometer visualização.
- Alertas claros quando o conteúdo estiver parcialmente indexado.
- Registrar acesso para o ranking de popularidade quando um usuário autenticado **abre a página de detalhes**.
- Mostrar botão de exclusão apenas ao autor do upload ou ao admin, com confirmação explícita.

### 8.5. `/my/uploads` e admin

- O usuário vê seus uploads, inclusive `pending`, `processing`, `ready`, `partial`, `failed` e `rejected`, com estados em texto (sem tela de carregamento).
- O admin pode listar lotes de todos os usuários e cadastrar usuários comuns.
- Criar apenas as telas administrativas estritamente necessárias, sem painel genérico.

## 9. Popularidade na home

- Criar evento de acesso ao lote **quando um usuário autenticado abrir sua página de detalhes**; não contar mera aparição nas buscas.
- Ranking: número de acessos nos **últimos 30 dias corridos**, em ordem decrescente. Desempatar pela data do acesso mais recente e pelo ID.
- Não contar uploads, indexações automáticas, jobs, pesquisas ou visualizações administrativas técnicas como acessos se não houver abertura real da página de detalhes.
- O modelo de eventos deve permitir consulta eficiente e limpeza futura de dados antigos, sem exigir estatísticas agregadas elaboradas no MVP.

## 10. Modelo de dados sugerido

Pode ajustar nomes técnicos sem alterar o comportamento. Usar chaves primárias convencionais do Rails e índices/FKs apropriados.

### `users`

- `id`
- `name`
- `email_address` (único, normalizado)
- `password_digest` (conforme autenticação Rails)
- `role`: `admin` ou `user`; por padrão `user`
- `created_at`, `updated_at`
- Garantia de no máximo um admin no banco; seed cria o primeiro.

### `lots`

- `id`
- `uploader_id` (`users`, obrigatório para upload)
- `source_type` (no MVP apenas `upload`; preparado para outras fontes)
- `source_identifier` (opcional, para futura integração)
- `name` (nome original higienizado para apresentação)
- `content_type` (MIME confiável detectado)
- `byte_size`
- `checksum` (opcional, para auditoria/diagnóstico, **sem unique index**)
- `metadata` (`jsonb`, padrão `{}`)
- `metadata_search_text` (`text`, versão pesquisável dos metadados)
- `extracted_text` (`text`, indexável, podendo ser incompleto)
- `page_count` (inteiro opcional)
- `status` (`pending`, `processing`, `ready`, `partial`, `failed`, `rejected`)
- `processing_warnings` (`jsonb`, padrão `[]`)
- `processing_error` (texto curto, sem rastros sensíveis)
- `search_vector` (`tsvector` com GIN)
- `indexed_at`, `created_at`, `updated_at`
- `has_one_attached :file` (Active Storage; somente para `upload`)

### `lot_chunks`

- `id`, `lot_id` (FK, cascade na exclusão)
- `position` (ordem do chunk no lote)
- `text` (texto do chunk)
- `embedding` (`vector(1024)` se usar `bge-m3`)
- `created_at`, `updated_at`
- Índice em `(lot_id, position)` com unicidade; índice vetorial opcional, adequado à distância cosseno.

### `lot_accesses`

- `id`, `lot_id`, `user_id`, `accessed_at`
- Índices para ranking por lote e janela temporal.

### `audit_events`

- `id`, `actor_id`, `action`, `subject_type`, `subject_id`, `subject_snapshot` (`jsonb`), `created_at`
- Ao excluir um lote, registrar `lot.deleted`, nome, origem, autor original e ator; o evento deve permanecer depois da exclusão física do lote.

### Ativos de autenticação/fila

- Tabelas que o Rails gerar para sessões, Active Storage e Solid Queue.

## 11. Exclusão de lote

- Autor do upload pode excluir **somente seu lote**; admin pode excluir **qualquer lote**.
- Outros usuários não podem excluir, mesmo acessando a rota HTTP diretamente.
- A exclusão deixa o lote imediatamente invisível na busca e remove seus chunks/embeddings, conteúdo extraído, metadados pesquisáveis, eventos de popularidade e arquivo original (purge seguro, síncrono ou job idempotente).
- Registrar auditoria persistente com quem excluiu, quando e qual lote, sem guardar o conteúdo original no evento.
- Proteger contra corrida com job em andamento; lote excluído não pode reaparecer pela finalização atrasada de um job.
- Excluir não deve apagar outros lotes idênticos enviados por usuários diferentes.

## 12. Segurança e privacidade

1. Autenticação obrigatória para **todas** as rotas de lotes, resultados, upload, preview e download; autorizações testadas no servidor.
2. **Desabilitar rotas públicas padrão do Active Storage**, que poderiam expor blobs por URLs assinadas permanentes (`config.active_storage.draw_routes = false`), e servir conteúdo apenas por controllers autenticados. Não redirecionar para URL pública desprotegida.
3. Validar tamanho no backend e não confiar em MIME enviado pelo navegador; higienizar nomes exibidos e escapar HTML.
4. Para previews, restringir tipos seguros, usar `Content-Disposition` apropriado e `X-Content-Type-Options: nosniff`; nunca renderizar HTML/SVG potencialmente malicioso como conteúdo confiável.
5. Proteção CSRF, cookies seguros em produção, limites de tentativas de login e tratamento seguro de sessão.
6. Não executar arquivos carregados; subprocessos de extração isolados, sem acesso desnecessário à rede e com timeouts/limites de recursos.
7. Não registrar conteúdo dos documentos, senhas, tokens ou texto completo de queries em logs. Reduzir retenção de informação sensível.
8. Criptografar o tráfego HTTP em produção por HTTPS; configurar segredo e SMTP via variáveis de ambiente.
9. Como o repositório é global, mostrar aviso sobre compartilhamento antes do upload.
10. Backup do PostgreSQL e do volume Active Storage, com procedimento documentado de restauração. E-mails e logs de auditoria não substituem backups.

## 13. Configuração e execução

Criar `.env.example` com nomes, documentação e **valores de exemplo não secretos**:

```dotenv
RAILS_ENV=development
DATABASE_URL=postgresql://athenas:example@localhost:5432/athenas_development
RAILS_MASTER_KEY=
ADMIN_EMAIL=admin@example.local
ADMIN_PASSWORD=
APP_BASE_URL=http://localhost:3000
OLLAMA_BASE_URL=http://localhost:11434
EMBEDDING_MODEL=bge-m3
EMBEDDING_DIMENSIONS=1024
SEMANTIC_MIN_SIMILARITY=0.60
MAX_UPLOAD_BYTES=10485760
MAX_DOCUMENT_PAGES=100
JOB_CONCURRENCY=1
SMTP_ADDRESS=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM=no-reply@example.local
```

`SEMANTIC_MIN_SIMILARITY=0.60` é **valor inicial sujeito a calibração**, não garantia de qualidade. Documentar como ajustá-lo com exemplos reais. Outras variáveis relacionadas a credenciais devem ser configuradas por ambiente sem commit de secrets.

Entregar:

- `Dockerfile` e configuração reproduzível para desenvolvimento (preferencialmente `compose.yaml`) com PostgreSQL + extensão pgvector, app Rails, worker Solid Queue e Ollama local. Não iniciar múltiplos workers pesados de OCR/embeddings por padrão.
- Dependências de extração instaladas ou passos claros para instalá-las no ambiente usado pelos jobs, incluindo idioma português no OCR.
- Volume persistente para arquivos enviados, dados PostgreSQL e cache/modelos Ollama.
- Script/comandos para preparar banco, seed idempotente, baixar modelo Ollama, iniciar web e worker, executar testes e verificar serviços.
- SMTP de desenvolvimento com captura de mensagens ou visualização local; nunca enviar notificações de desenvolvimento para destinatários reais por acidente.
- `README.md` em português com arquitetura, decisões importantes, limitações de extratores, backup/restauração e troubleshooting.

## 14. Organização sugerida de código

Use controllers Rails pequenos, modelos com validações fundamentais e serviços especializados:

```text
app/
  controllers/
    home_controller.rb
    searches_controller.rb
    lots_controller.rb
    uploads_controller.rb
    my/uploads_controller.rb
    admin/users_controller.rb
  models/
    user.rb
    lot.rb
    lot_chunk.rb
    lot_access.rb
    audit_event.rb
  jobs/
    process_lot_job.rb
  mailers/
    lot_processing_mailer.rb
  services/
    lots/upload_service.rb
    lots/extraction_service.rb
    lots/extractors/...
    lots/chunker.rb
    lots/indexing_service.rb
    search/lexical_search.rb
    search/semantic_search.rb
    search/service.rb
    embeddings/ollama_client.rb
```

Isso é uma sugestão de estrutura, não obrigação literal. Separar **origens**, **extração**, **indexação** e **busca**, para permitir fontes futuras sem adicionar dependências de Drive ou SEI agora.

## 15. Critérios de aceite (teste ponta a ponta)

O MVP só está pronto quando todos os cenários essenciais abaixo passarem:

### Autenticação e permissões

- [ ] Instalar e executar seed cria exatamente um admin; executar novamente não cria outro nem altera sua senha.
- [ ] Usuário anônimo não consegue pesquisar, listar, visualizar, pré-visualizar, baixar ou fazer upload.
- [ ] Não existe cadastro público. Apenas admin consegue criar usuário comum.
- [ ] Usuários comuns podem consultar todos os lotes pesquisáveis no repositório global.
- [ ] Usuário comum não consegue excluir lote de terceiro por chamada HTTP direta; autor e admin conseguem.

### Upload e processamento

- [ ] Upload de arquivo até 10 MB recebe mensagem imediata e job assíncrono, sem loading permanente.
- [ ] Upload maior que 10 MB é rejeitado no servidor.
- [ ] PDF com 101 páginas é rejeitado antes de ser publicado; com 100 páginas é aceito se válido.
- [ ] TXT/JSON sem conceito de página são limitados pelo tamanho, não por contagem inventada.
- [ ] PDF textual e PDF digitalizado (OCR) ficam pesquisáveis pelo conteúdo quando processados.
- [ ] Pelo menos DOCX, XLSX, PPTX e imagens comuns possuem caminhos de extração testados.
- [ ] Falha em parte do OCR resulta em `partial` **após fim do job**, com conteúdo extraído disponível para pesquisa e aviso claro.
- [ ] Lote em `pending` ou `processing` nunca aparece nos resultados.
- [ ] E-mail é disparado na conclusão, conclusão parcial, falha ou rejeição, sem incluir o conteúdo integral.
- [ ] Upload de arquivo idêntico gera **dois lotes** distintos.

### Busca

- [ ] Pesquisa lexical usa AND dos termos relevantes e encontra termos distribuídos entre nome, conteúdo e metadados do mesmo lote.
- [ ] Correspondência no conteúdo recebe peso maior do que no nome/metadados.
- [ ] Se existir qualquer resultado lexical, a busca semântica **não é chamada**.
- [ ] Sem resultado lexical, embeddings são gerados localmente e resultados vetoriais são retornados por lote.
- [ ] Um lote com muitas ocorrências ou vários chunks relevantes aparece **uma única vez** na lista.
- [ ] Resultados são ordenados por relevância, com recência como critério secundário, e paginados.
- [ ] Consulta só de stopwords é tratada sem resultados enganosos.
- [ ] Falha do Ollama não provoca chamada a API externa nem se apresenta falsamente como ausência definitiva de documentos.

### Visualização, popularidade e exclusão

- [ ] Página de detalhes mostra nome, tipo, tamanho, data, origem, autor e metadados; mostra aviso de indexação parcial quando aplicável.
- [ ] Pré-visualização/download somente por endpoint autenticado, sem URL pública do blob.
- [ ] Aberturas de detalhes contam para ranking dos últimos 30 dias; aparecer em busca, sem clique, não conta.
- [ ] Exclusão remove arquivo e dados de busca sem afetar duplicados de outros autores, e preserva evento de auditoria.
- [ ] Um job atrasado não consegue recriar lote excluído.

### Operação

- [ ] Ambiente reproduzível sobe Rails, banco, worker e Ollama sem dependências de SaaS.
- [ ] Migrations e testes completos executam com sucesso; testes de OCR/integrações locais têm fixtures e/ou mocks adequados.
- [ ] README explica iniciar, criar admin, fazer upload, pesquisar, checar e-mails, configurar SMTP, acompanhar jobs e fazer backup.

## 16. Ordem de implementação recomendada

1. **Fundação:** Rails + PostgreSQL/pgvector + autenticação + admin via seed + autorização.
2. **Domínio:** `Lot`, Active Storage local seguro, uploads, validações, listagem e detalhes.
3. **Processamento:** Solid Queue, extração de texto/OCR, limite de páginas, estados, notificação por e-mail.
4. **Busca lexical:** `tsvector` agregado por lote, configuração portuguesa, GIN, AND, relevância e resultados únicos.
5. **Semântica:** chunks, Ollama local, pgvector e fallback exclusivamente com zero resultados lexicais.
6. **Experiência:** home centralizada, resultados, ranking de 30 dias, preview/download e administração mínima.
7. **Qualidade:** exclusão/auditoria, testes ponta a ponta, segurança, backup, Docker e README.

## 17. Definição de pronto

Uma pessoa deve conseguir clonar o repositório, configurar variáveis locais, iniciar dependências, criar o único admin, cadastrar um usuário, enviar um PDF de exemplo, receber notificação, encontrar o lote por palavras do conteúdo, abrir seus detalhes, baixá-lo e excluí-lo quando autorizada. Também deverá ser possível demonstrar **fallback semântico local**, **OCR** e **publicação parcial sinalizada**.

**Não considerar concluído apenas porque as telas existem.** A indexação deve funcionar de verdade, os arquivos não podem ser acessíveis anonimamente e os critérios de aceite devem estar cobertos por testes.

---

### Referências técnicas oficiais (para quem estiver implementando)

- Rails: https://guides.rubyonrails.org/security.html
- Active Job / Solid Queue: https://guides.rubyonrails.org/active_job_basics.html
- Active Storage (proteção de rotas de blob): https://guides.rubyonrails.org/active_storage_overview.html
- pgvector: https://github.com/pgvector/pgvector
- pgvector para Ruby: https://github.com/pgvector/pgvector-ruby
- Ollama BGE-M3: https://ollama.com/library/bge-m3
