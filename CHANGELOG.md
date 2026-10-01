# Changelog — Tonalize

## [v3.6-calibrado] — 1.4.0+13 — 2026-09-30

Versão congelada para a Etapa 1 e validação de campo do TCC. Todas as correções e calibrações foram derivadas diretamente dos logs e gravações da bancada de 33 músicas (`tonalize_bench_20260930_163426`).

### Resumo das Mudanças

1. **Correção da Âncora de Tempo Pós-Reinício:**
   - Correção dos contadores `songSeconds` e `passageSeconds` que ficavam negativos após `silenceReset` ou `manualReset`.
   - Contadores agora reiniciam confiavelmente em 0, e o letreiro retorna em $\le \text{min\_s} + \text{show\_after}$.

2. **Evidência de Nota Nova por Nota Deslocada (`key_evidence.dart`):**
   - Substituição da comparação de notas novas contra o piso pela comparação contra a nota que ela desloca (nota elevada compara com meio-tom abaixo; nota diatônica compara com a nota que sai da escala).
   - Eliminação da promoção indevida do relativo menor e de piscadas transitórias.

3. **Continuidade da Evidência Diatônica (`tonal_engine.dart`):**
   - Continuidade do contador de evidência entre desafiantes sucessivos restrita às notas novas estritamente diatônicas.

4. **Fase Jovem Pós-Confirmação (`tonal_engine.dart`):**
   - Após confirmação de tom vizinho ou distante, o tom confirmado é segurado (`_held`) até que o perfil da música concorde com ele por `youngSeconds` (30 s) ou até o teto de 60 s, evitando oscilações instantâneas para o relativo.

5. **Ajuste de Limiar Distante (`song_far_s`):**
   - Limiar de confirmação de tom distante aumentado de 12 s para 20 s padrão, prevenindo falsas modulações em pedais harmônicos dominantes.

6. **Novo Perfil Menor Calibrado (`aar_b7`):**
   - Perfil Aarden-Essen menor calibrado com a 7ª menor reforçada (índice 10: 7,38 $\to$ 15,0).
   - Adequação ao repertório gospel tonal menor onde o acorde do VII grau é dominante.

7. **Configurações e Parâmetros Congelados:**
   - Padrões: `profiles = aar`, `minor_profiles = aar_b7`, `song_far_s = 20`, `strict_notes = off`, `bass_share = 0.0`.
   - String de configuração atualizada para `v3;w20;harm;aar;min-aar_b7;song60;far20;near45;tol0.8;floor0.25;drain0.5;strict0;bass0`.

8. **Bancada e Exportação de Veredito:**
   - `verdict.final_label`, `final_second` e `final_bars_top3` salvam o último instante com letreiro não vazio antes do silêncio final.
   - Suporte a exportação parcial durante captura em andamento (`verdict.result = "em andamento"`).
   - `reference.segments[0]` espelha automaticamente a referência de tom e modo.
   - Campo de entrada pós-captura para preenchimento de segmentos adicionais em medleys.
   - Gravação de `capture.silence_threshold_db` no `session.json`.

9. **Interface de Usuário:**
   - Exibição permanente do tom relativo logo abaixo do letreiro principal, permitindo discernimento auditivo imediato pelo músico.

10. **Ferramenta de Replay e Testes de Aceitação (`tool/replay.dart` e `test/bench_acceptance_test.dart`):**
    - Implementação de `tool/replay.dart` em puro Dart reproduzindo o motor a partir de `frames.csv`.
    - Suíte de aceitação das 33 sessões validando os 4 critérios: invariantes estruturais, músicas robustas ($\ge 99\%$ de igualdade), tolerância de divergência exclusiva por empate numérico ($< 0,01$) e totais esperados da calibração (19 exatos, 4 relativos, 1 outro nas 24 músicas simples; 25 exatos nas 32 pela 1ª música).
