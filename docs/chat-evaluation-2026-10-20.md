# Avaliação do chat — 20/10/2026

## Estado da avaliação

Implementação e testes locais concluídos. **A comparação das respostas geradas pelo Qwen ainda não foi executada.** A revisão automática de permissões bloqueou a autenticação no servidor institucional `150.164.110.3:8080`, exigindo autorização explícita para enviar a chave já cadastrada e os textos do acervo. Nenhum resultado de qualidade de geração é presumido a partir dos mocks.

## Constatações no acervo local

- 20 documentos disponíveis: 19 relatórios e um livro.
- Livro de Bitcoin: 138.175 caracteres extraídos, 68 trechos, somente 3 com embeddings. A recuperação anterior entregou 3.750 caracteres para a consulta `Bitcoin`.
- Dez relatórios da Scheilla: 164.728 caracteres extraídos no total, com todos os seus trechos vetorizados. A consulta pelo nome encontra esses dez relatórios e mais dois documentos que a mencionam.
- Os nomes das comissões e os registros de coordenação **estão no texto extraído**. Exemplos: Laboratório de Bromatologia; Comissão de Biossegurança; Comissão Examinadora do Edital nº 2305/2025. As linhas incluem funções e períodos.
- Há divergências nos próprios relatórios: datas de admissão de 2010 e 2013 e diferentes datas de início para registros de coordenação. A resposta deve apontar a divergência, sem unificar períodos arbitrariamente.

## Comparação local da recuperação

Consultas fixas: `Bitcoin`, `Scheilla Vitorino comissões` e `Scheilla Vitorino laboratórios coordenação`. A recuperação anterior foi executada a partir de uma cópia do código original. A busca híbrida combina resultados lexicais e semânticos e inclui trechos vizinhos. As consultas dos trechos pesquisam o acervo inteiro; os números abaixo contam todos os documentos retornados, sem pressupor relevância perfeita.

| Pergunta | Recuperação anterior: documentos / caracteres enviados | Recuperação híbrida: documentos / caracteres enviados | Texto completo das fontes de referência |
|---|---:|---:|---:|
| Bitcoin | 1 / 3.750 | 1 / 54.218 | 138.175 caracteres |
| Comissões | 2 / 2.500 | 7 / 48.223 | 164.728 caracteres em 10 relatórios |
| Laboratórios | 9 / 12.500 | 9 / 47.566 | 164.728 caracteres em 10 relatórios |

Os caracteres dos trechos incluem sobreposição; não equivalem a uma porcentagem de cobertura exclusiva do documento. Essas medições verificam disponibilidade de contexto, não a correção de uma resposta gerada.

## Hipóteses e implementação

1. **Trechos atuais:** cobertura muito pequena no livro e na pergunta sobre comissões; medição local concluída.
2. **Trechos híbridos e vizinhos:** aumentam o material disponível, mas não garantem todos os relatórios ou seções; medição local concluída.
3. **Busca seguida de texto completo em uma única chamada:** roteiro preparado; falta medir qualidade, latência e compatibilidade com a janela real do servidor. Não foi presumido que 138 mil ou 165 mil caracteres caibam nessa janela.
4. **Texto completo analisado em partes:** implementado com síntese por fonte. Os testes verificam que todas as partes são percorridas e que limites de trabalho geram cobertura parcial explícita. Falta avaliar o conteúdo das sínteses no Qwen real.
5. **Pesquisa guiada pela LLM:** implementada com planejamento JSON, consultas curtas validadas e pesquisa adicional quando faltam resultados ou evidências. A aplicação executa as consultas. Testes com respostas simuladas verificam o controle do fluxo; falta a comparação do planejamento real.

A configuração adotada no código combina 4 e 5, com a busca tradicional de documentos como primeira forma de descoberta. A recuperação híbrida serve como fallback de descoberta. Essa escolha resolve os defeitos observados no fluxo e na cobertura; a preferência final de qualidade entre estratégias depende da execução autenticada que está pendente.

## Verificação

- Suíte completa final: **86 testes, 463 asserções, nenhuma falha, nenhum erro, nenhum teste pulado**, incluindo PDF, OCR e Office reais e condensação de evidências dentro do orçamento de contexto.
- Brakeman: nenhum aviso de segurança.
- Zeitwerk: carregamento válido.
- Testes cobrem leitura sem embeddings, fim de documento, todos os relatórios encontrados, múltiplas referências, nova pesquisa após evidência insuficiente, XML inválido, consulta híbrida, continuação de tabelas, marcadores de página, texto indisponível, limite de partes e saída cortada por tokens.
- Foi definido remetente fictício somente no ambiente de testes, necessário para a suíte de entrega local; a configuração de envio pelo Hermes não foi alterada.

Os testes reais de extração verificam as ferramentas e o isolamento. Não substituem uma inspeção visual de todas as tabelas do acervo.

## Reprodução da comparação de geração

```sh
bin/rails runner script/evaluate_chat.rb all all
```

O roteiro mantém o Qwen configurado e grava respostas, tempo, número de chamadas, tamanho de contexto e uso de tokens em `tmp/chat-evaluation/`, fora do Git. Usa seleção fixa de fontes nas variantes de texto completo; `guided_search` avalia também a descoberta pelo modelo. O prompt final é compartilhado para isolar o efeito da recuperação. A variante adicional `legacy_prompt_excerpts` usa o prompt antigo com os mesmos trechos de `legacy_excerpts`, permitindo medir o efeito do prompt separadamente. Não foi atribuída ao prompt uma melhora ainda não medida.

Revisão manual das respostas: conferir nomes e períodos contra as fontes; verificar omissões, divergências e inferências temporais; no resumo, verificar a cobertura dos assuntos; em composição temática, exigir estimativa identificada, critério e soma de 100% por documento. Não basta comparar o tamanho das respostas. Uma execução por caso não constitui avaliação estatística.

## Limites

- Os limites de leitura são 24 documentos, 500 mil caracteres e 40 partes por análise. A síntese usa notas quando o texto não cabe diretamente no contexto.
- A janela é aproximada por caracteres; precisa ser calibrada para o servidor real. Documentos longos podem exigir várias chamadas e levar minutos. A resposta continua síncrona.
- A síntese pode perder detalhes; avisos e cobertura acompanham as evidências. Ausência no texto disponível não prova ausência no original.
- Novas extrações preservam alinhamento e marcadores de página. Arquivos já indexados mantêm o texto antigo até reprocessamento; não foram reindexados nem modificados nesta avaliação.
- A falha dos embeddings do livro não foi reparada por uma reindexação. O novo fluxo analisa seu texto disponível sem depender desses embeddings.
- Não houve publicação em produção.
