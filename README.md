# Tonalize

> Identificação de tonalidade musical ao vivo com processamento 100% no celular (on-device), sem envio de áudio e sem conexão à internet.

Desenvolvido como projeto de pesquisa científica para validação em campo de algoritmos de extração tonal a partir de sinal acústico contínuo.

---

## Arquitetura do Sistema (Versão 2 — Estabilidade Aprimorada)

O fluxo de processamento é dividido em duas camadas estritamente isoladas e modulares:

```
[ Microfone ] (44.100 Hz, mono)
      │
      ▼
[ SilenceDetector (TarsosDSP) ] ── (se silêncio) ──► descarta o bloco
      │
      ▼ (se áudio válido: 8.192 amostras, 50% overlap / salto 4.096)
[ Janela Hann + FFT ] ──► Magnitude das raias (130 Hz a 2.000 Hz)
      │
      ▼
[ ChromaMapper com HPCP (Kotlin) ]
      ├── Apenas picos espectrais locais (reduz ruído de bateria e ambiente)
      ├── Crédito de subarmônicos: fundamentais f/2, f/3, f/4 com pesos 0,6^h (Gómez, 2006)
      └── Descarte de blocos atípicos/planos (minTonalness >= 1,5)
      │
      ▼ (EventChannel: ~10,7 payloads/s)
[ TonalEngine (Dart puro) ]
      ├── ChromaAccumulator: janela deslizante de 20s com decaimento exponencial (meia-vida 10s)
      │     └── Reinício automático de janela após 4s de silêncio
      ├── KeyScorer: Correlação de Pearson × 24 perfis (Krumhansl-Kessler ou Temperley)
      ├── KeyStabilizer: Histerese adaptativa por margem e sustentação temporal
      │     ├── Tons distantes: margem de 0,05 sustentada por 4 segundos
      │     └── Tons vizinhos (quintas, relativas, paralelas): margem de 0,08 sustentada por 6 segundos
      └── Contador de trocas de letreiro por sessão
      │
      ▼
[ Interface Flutter (UI @ 2 Hz) ]
      ├── Tonalidade estabilizada no letreiro (ex.: "D Maior")
      ├── Linha de tons próximos: "2ª opção: A · também: G, Bm"
      ├── Indicador de confirmação com barra fina durante desafios
      ├── Barra de confiança (%)
      ├── 12 barras cromáticas com destaque nas notas da escala
      ├── Métrica de estabilidade da sessão (trocas: N · mm:ss)
      ├── Teste de campo com registro manual (Acertou / Errou) + Exportação CSV
      └── Painel de experimento (v1 baseline vs v2) nas Configurações
```

### 1. Camada Nativa (Kotlin & TarsosDSP)
- **Captura:** `AudioDispatcherFactory.fromDefaultMicrophone(44100, 8192, 4096)`.
- **Filtro de Silêncio:** `SilenceDetector` configurável (Baixa: -60 dB, Média: -70 dB, Alta: -80 dB SPL). Blocos em silêncio interrompem a cadeia antes da FFT para poupar CPU e bateria.
- **Mapeamento Cromático com HPCP:** `ChromaMapper` identifica picos espectrais e distribui energia harmônica para as fundamentais com pesos decrescentes, além de filtrar blocos com tonalidade difusa.
- **Comunicação Reativa:** Transmissão via `EventChannel` (`tonalize/chroma` e `tonalize/pitch`), desacoplando a thread de áudio da UI thread.

### 2. Núcleo Algorítmico (Dart Puro)
- **Acumulador com Esquecimento (`ChromaAccumulator`):** Ponderação exponencial por idade ($0,5^{\text{idade}/\text{meia-vida}}$) para esquecer acordes antigos sem cortes secos.
- **Modelos de Perfil:** Templates de Krumhansl-Kessler (1990) ou Temperley (1999) selecionáveis.
- **Estabilizador Inteligente (`KeyStabilizer`):** Diferencia tons vizinhos (que compartilham notas) de tons distantes, exigindo maior margem de correlação e tempo de sustentação para autorizar a troca do letreiro.

---

## Requisitos e Conformidade Ética / Pesquisa

- **RNF01 (Sem Internet):** Nenhuma permissão de rede (`INTERNET`) solicitada no `AndroidManifest.xml`.
- **RNF02 (Privacidade):** Nenhum áudio é gravado em disco ou transmitido; o áudio existe apenas temporariamente em buffers de memória volátil.
- **RNF03 (Compatibilidade):** Compatível com Android 8.0+ (`minSdk = 21`).
- **RF06 (Teste de Campo & Registro de Leituras):**
  - Registro de acertos/erros no banco local SQLite (`field_log`).
  - Registro de telemetria a 2 Hz (`readings`) quando ativado nas configurações para cálculo de trocas por minuto e tempo até o primeiro acerto.
  - Exportação direta de CSV para a área de transferência.

---

## Como Executar

### Pré-requisitos
- Flutter SDK 3.3.0+
- Android SDK (API 34) e JDK 17

### Comandos

```bash
# Instalar dependências
flutter pub get

# Executar no dispositivo conectado
flutter run
```

---

## Testes Automatizados

```bash
# 1. Testes unitários do motor tonal (KeyStabilizer, ChromaAccumulator, Pearson, 24 tons):
flutter test

# 2. Testes unitários do ChromaMapper nativo na JVM (sem emulador):
cd android && ./gradlew :app:testDebugUnitTest
```
