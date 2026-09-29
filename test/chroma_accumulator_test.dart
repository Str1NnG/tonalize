import 'package:flutter_test/flutter_test.dart';
import 'package:keyfinder/core/chroma_accumulator.dart';

void main() {
  group('ChromaAccumulator', () {
    test('8. Frame com 10s de idade tem peso 0.5 em relação a um frame novo', () {
      final acc = ChromaAccumulator(windowSeconds: 20, halfLifeSeconds: 10);
      final frame = List<double>.filled(12, 1.0);

      // Adiciona em t = 0s
      acc.add(frame, Duration.zero);

      // Avalia em t = 10s (idade = 10s -> peso = 0.5^(10/10) = 0.5)
      final prof10 = acc.profile(const Duration(seconds: 10))!;
      expect(prof10[0], closeTo(0.5, 1e-4));

      // Compara com frame novo adicionado em t = 10s
      acc.clear();
      acc.add(frame, const Duration(seconds: 10));
      final prof0 = acc.profile(const Duration(seconds: 10))!;
      expect(prof0[0], closeTo(1.0, 1e-4));
    });

    test('9. Frames mais velhos que 20s saem da janela', () {
      final acc = ChromaAccumulator(windowSeconds: 20, halfLifeSeconds: 10);
      final frame = List<double>.filled(12, 1.0);

      acc.add(frame, Duration.zero);

      // Em t = 19.9s ainda existe
      expect(acc.profile(const Duration(milliseconds: 19900)), isNotNull);

      // Em t = 20.1s deve expirar e retornar null
      expect(acc.profile(const Duration(milliseconds: 20100)), isNull);
    });

    test('10. Intervalo de 4.5s entre frames aciona reinício automático', () {
      final acc = ChromaAccumulator(
        windowSeconds: 20,
        halfLifeSeconds: 10,
        silenceResetSeconds: 4,
      );
      final frameA = List<double>.filled(12, 2.0);
      final frameB = List<double>.filled(12, 5.0);

      final r1 = acc.add(frameA, Duration.zero);
      expect(r1, isFalse);

      // Gap de 4.5s (> 4s de silêncio)
      final r2 = acc.add(frameB, const Duration(milliseconds: 4500));
      expect(r2, isTrue);

      // Janela recomeçou só com frameB
      final prof = acc.profile(const Duration(milliseconds: 4500))!;
      expect(prof[0], closeTo(5.0, 1e-4));
      expect(acc.secondsInWindow, 0.0);
    });

    test('10. seedFrom copia registros e mantém perfil e secondsInWindow idênticos', () {
      final a = ChromaAccumulator(windowSeconds: 20);
      final b = ChromaAccumulator(windowSeconds: 240);

      a.add(List<double>.filled(12, 1.0), const Duration(seconds: 1));
      a.add(List<double>.filled(12, 2.0), const Duration(seconds: 5));

      b.seedFrom(a);

      const now = Duration(seconds: 5);
      expect(b.secondsInWindow, equals(a.secondsInWindow));
      final profA = a.profile(now)!;
      final profB = b.profile(now)!;
      for (var i = 0; i < 12; i++) {
        expect(profB[i], closeTo(profA[i], 1e-6));
      }
    });

    test('11. binSeconds agrupa frames dentro do mesmo intervalo em um só registro', () {
      final acc = ChromaAccumulator(windowSeconds: 20, binSeconds: 1.0);
      final frame = List<double>.filled(12, 0.1);

      // 10 frames dentro de 1 segundo (a cada 90ms)
      for (var i = 0; i < 10; i++) {
        acc.add(frame, Duration(milliseconds: i * 90));
      }

      // Deve ter apenas 1 registro somado
      final prof = acc.profile(Duration.zero)!;
      expect(prof[0], closeTo(1.0, 1e-4));
    });

    test('12. Silêncio de 6s não reinicia aos 5s e reinicia aos 6.5s', () {
      final acc = ChromaAccumulator(silenceResetSeconds: 6);
      final frame = List<double>.filled(12, 1.0);

      acc.add(frame, Duration.zero);

      // Gap de 5s: não deve reiniciar
      final r1 = acc.add(frame, const Duration(seconds: 5));
      expect(r1, isFalse);

      // Gap de 6.5s: deve reiniciar
      final r2 = acc.add(frame, const Duration(milliseconds: 11500));
      expect(r2, isTrue);
    });
  });
}
