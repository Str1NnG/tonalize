# bench_expected_v36

Saída do replay de referência (Python, `replay.py` deste repositório de análise) com a configuração v3.6 calibrada, para cada uma das 33 sessões de `tonalize_bench_20260930_163426`.

- `<sessão>/timeline.csv`: `t_s` (passo 0,5 s), `passage` (tom do trecho), `song` (letreiro), `evidence_s`, `event`. Notas em inglês com `m` para menor (`F#m`, `Bb` grafado `A#`).
- `<sessão>/expected.json`: classe (exato/relativo/…), tempo na referência, letreiro final, segmentos, trocas, eventos, fim da música.
- `referencias_v36.json`: referências e segmentos fechados em 30/09 (plano 4, Adendo 6). `ambigua: true` na 04.
- `summary_v36.json`: configuração usada e o resumo de todas as sessões.

Uso no teste de aceitação (plano 5, fase 7.3): o `tool/replay.dart` roda a mesma sessão com a mesma configuração e compara `song` instante a instante com `timeline.csv`. No primeiro instante em que divergem, a diferença de correlação (memória da música) entre os dois letreiros decide: < 0,01 é empate (admitido); caso contrário é regressão.
