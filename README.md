# Tonalize

> Identificação de tonalidade musical ao vivo com processamento 100% no celular (on-device), sem envio de áudio e sem conexão à internet.

Desenvolvido como projeto de pesquisa científica para validação em campo de algoritmos de extração tonal a partir de sinal acústico contínuo.

---

## Arquitetura do Sistema

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
[ ChromaMapper (Kotlin) ] ──► Perfil de 12 notas (energia normalizada)
      │
      ▼ (EventChannel: ~10,7 payloads/s)
[ TonalEngine (Dart puro) ]
      ├── Janela deslizante de 10 segundos
      ├── Correlação de Pearson × 24 perfis Krumhansl-Kessler (12 maiores / 12 menores)
      ├── Cálculo de confiança: (best.r - second.r) / 0.25 (clamp 0..1)
      └── Regra de estabilidade: debounce de 3 leituras consecutivas
      │
      ▼
[ Interface Flutter (UI @ 2 Hz) ]
      ├── Tonalidade mais provável (ex.: "C Maior")
      ├── Segunda opção mais provável (ex.: "A Menor")
      ├── Barra de confiança (%)
      ├── 12 barras cromáticas com destaque nas notas da escala
      └── Teste de campo com registro manual (Acertou / Errou) + Exportação CSV
```

### 1. Camada Nativa (Kotlin & TarsosDSP)
- **Captura:** `AudioDispatcherFactory.fromDefaultMicrophone(44100, 8192, 4096)`.
- **Filtro de Silêncio:** `SilenceDetector` configurável (Baixa: -60 dB, Média: -70 dB, Alta: -80 dB SPL). Blocos em silêncio interrompem a cadeia antes da FFT para poupar CPU e bateria.
- **Mapeamento Cromático:** `ChromaMapper` converte frequências entre 130 Hz (Dó 3) e 2.000 Hz para classes de altura (pitch class 0 a 11 via MIDI pitch rounding). A energia é somada e normalizada para peso uniforme de cada bloco.
- **Comunicação Reativa:** Transmissão via `EventChannel` (`tonalize/chroma` e `tonalize/pitch`), desacoplando a thread de áudio da UI thread.

### 2. Núcleo Algorítmico (Dart Puro)
- **Janela Deslizante:** Vetores dos últimos 10 segundos são preservados em memória volátil com carimbo de tempo (`Duration`).
- **Templates Krumhansl-Kessler:** 24 perfis (12 maiores e 12 menores) rotacionados circularmente.
- **Correlação de Pearson:** Compara o cromagrama acumulado com todos os 24 perfis tonais.
- **Filtro de Estabilidade:** Uma nova tonalidade requer 3 avaliações sucessivas a 2 Hz (1,5 s de confirmação) para substituir a exibição na tela.

---

## Requisitos e Conformidade Ética / Pesquisa

- **RNF01 (Sem Internet):** Nenhuma permissão de rede (`INTERNET`) solicitada no `AndroidManifest.xml`.
- **RNF02 (Privacidade):** Nenhum áudio é gravado em disco ou transmitido; o áudio existe apenas temporariamente em buffers de memória volátil.
- **RNF03 (Compatibilidade):** Compatível com Android 8.0+ (`minSdk = 21`).
- **RF06 (Teste de Campo):** Modo de campo ativável nas Configurações para registro de acertos/erros no banco local SQLite (`field_log`) e exportação direta em CSV para a área de transferência.

---

## Como Executar

### Pré-requisitos
- Flutter SDK 3.3.0+
- Android SDK (API 34) e JDK 17

### Comandos

```bash
# Instalar dependências
flutter pub get

# Executar no dispositivo ou emulador conectado
flutter run
```

---

## Testes Automatizados

```bash
# 1. Testes unitários do motor tonal (24 tonalidades, estabilidade, Pearson, janela):
flutter test

# 2. Testes unitários do ChromaMapper nativo na JVM (sem emulador):
cd android && ./gradlew :app:testDebugUnitTest
```
