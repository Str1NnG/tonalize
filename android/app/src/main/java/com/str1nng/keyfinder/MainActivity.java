package com.str1nng.keyfinder; // Ou o seu pacote correto

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import be.tarsos.dsp.AudioDispatcher;
import be.tarsos.dsp.AudioEvent;
import be.tarsos.dsp.AudioProcessor;
import be.tarsos.dsp.io.android.AudioDispatcherFactory;
import be.tarsos.dsp.pitch.PitchDetectionHandler;
import be.tarsos.dsp.pitch.PitchDetectionResult;
import be.tarsos.dsp.pitch.PitchProcessor;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "keyfinder";
    private AudioDispatcher dispatcher;
    private MethodChannel channel;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);

        channel.setMethodCallHandler(
                (call, result) -> {
                    if (call.method.equals("startListening")) {
                        startListening();
                        result.success("OK");
                    } else if (call.method.equals("stopListening")) {
                        stopListening();
                        result.success("OK");
                    } else {
                        result.notImplemented();
                    }
                }
        );
    }

    private void startListening() {
        stopListening();
        dispatcher = AudioDispatcherFactory.fromDefaultMicrophone(44100, 2048, 0);

        PitchDetectionHandler pdh = new PitchDetectionHandler() {
            @Override
            public void handlePitch(PitchDetectionResult res, AudioEvent e) {
                final float pitchInHz = res.getPitch();
                if (pitchInHz != -1 && res.getProbability() > 0.9) {
                    runOnUiThread(
                            () -> channel.invokeMethod("pitchDetected", pitchInHz)
                    );
                }
            }
        };

        AudioProcessor p = new PitchProcessor(PitchProcessor.PitchEstimationAlgorithm.YIN, 44100, 2048, pdh);
        dispatcher.addAudioProcessor(p);

        new Thread(dispatcher, "Audio Dispatcher").start();
    }

    private void stopListening() {
        if (dispatcher != null && !dispatcher.isStopped()) {
            dispatcher.stop();
        }
        dispatcher = null;
    }
}