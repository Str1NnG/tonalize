# Tonalize

Identificação de tonalidade musical ao vivo, processada inteiramente no dispositivo (on-device), sem envio de áudio e sem conexão à internet.

## Arquitetura

- **Captura e DSP Nativo (Kotlin / TarsosDSP):** Captura de microfone (44.100 Hz mono), detecção de silêncio adaptativa, janelamento Hann e cálculo de espectro FFT (8.192 amostras com 50% de sobreposição) mapeado para perfis cromáticos de 12 notas.
- **Transmissão Reativa:** Comunicação eficiente e desacoplada via `EventChannel` (streaming assíncrono para Dart).
- **Núcleo de Decisão (Dart puro):** Janela deslizante de 10 segundos, correlação de Pearson com os 24 perfis tonais de Krumhansl-Kessler, filtro de estabilidade e cálculo de confiança.

## Como Executar

```bash
flutter pub get
flutter run
```

## Como Testar

```bash
# Testes do núcleo Dart (perfis, Pearson, motor tonal):
flutter test

# Testes unitários do mapper de áudio na JVM Android:
cd android && ./gradlew :app:testDebugUnitTest
```
