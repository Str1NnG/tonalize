# Tonalize

Aplicativo Android que identifica a tonalidade de uma música tocada ao vivo,
usando só o microfone e o processador do celular. Não precisa de internet e
não grava áudio.

Trabalho de Conclusão de Curso — Tecnologia em Análise e Desenvolvimento de
Sistemas, IFRN Campus Nova Cruz. Orientador: Prof. Dr. Maurício Rabello Silva.

## Como funciona

O áudio é capturado em blocos de 8.192 amostras (44,1 kHz) por uma thread
nativa em Kotlin, com a TarsosDSP. Cada bloco vira um perfil das doze notas
(HPCP), que atravessa um EventChannel até o Dart. Ali o motor compara o
perfil acumulado com 24 perfis tonais (correlação de Pearson), mantém uma
memória do trecho (20 s) e uma da música (240 s) e só troca o tom exibido
quando as notas da escala nova aparecem de verdade.

## Rodando

    flutter pub get
    flutter run            # Android 8.0 ou superior
    flutter test           # testes do motor, inclusive o de aceitação da calibração

## Estrutura

- `lib/core/` — motor de decisão (Dart puro, testável no computador)
- `lib/ui/` — telas
- `lib/bench/` — registro das sessões de bancada e do teste de campo (sem áudio)
- `android/` — captura, detector de silêncio, FFT, HPCP e YIN (Kotlin + TarsosDSP)
- `calibracao.json` — parâmetros do motor
- `bench_data/` — as 33 sessões da bancada de calibração (CSV/JSON, sem áudio)
- `bench_data/expected_v36/` — linhas do tempo esperadas, usadas pelo teste de aceitação
- `tool/replay.dart` — reproduz o motor sobre um `frames.csv`

## Reproduzindo os números da calibração

    dart run tool/replay.dart bench_data/32_alem_do_rio_azul_20260930-162051/frames.csv

## Licença

GPL-3.0 — a mesma da TarsosDSP.
