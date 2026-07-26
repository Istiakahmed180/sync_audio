import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  final Stream<Uint8List> stream;
  final Color color;
  final int barCount;

  const AudioVisualizer({
    super.key,
    required this.stream,
    this.color = Colors.blue,
    this.barCount = 40,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> {
  late List<double> _amplitudes;
  StreamSubscription<Uint8List>? _subscription;
  double _currentPeak = 0.0;
  Timer? _decayTimer;

  @override
  void initState() {
    super.initState();
    // This buffer is shifted on every decay tick, so it must be growable.
    // List.filled() defaults to a fixed-length list.
    final barCount = widget.barCount < 1 ? 1 : widget.barCount;
    _amplitudes = List<double>.filled(barCount, 0.0, growable: true);
    _subscription = widget.stream.listen(_onData);

    // Smooth decay when no audio is playing
    _decayTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) {
        setState(() {
          _amplitudes.removeAt(0);
          _amplitudes.add(_currentPeak);
          _currentPeak *= 0.8; // Fast decay for the peak
          // Decay existing bars slightly for a smoother look
          for (int i = 0; i < _amplitudes.length; i++) {
            _amplitudes[i] *= 0.95;
          }
        });
      }
    });
  }

  void _onData(Uint8List data) {
    if (!mounted || data.isEmpty) return;

    double max = 0;
    final byteData = ByteData.sublistView(data);
    for (int i = 0; i < data.length; i += 10) {
      // Sample every 5th sample for speed
      if (i + 1 < data.length) {
        final sample = byteData.getInt16(i, Endian.little).abs();
        if (sample > max) max = sample.toDouble();
      }
    }

    final normalized = (max / 32768.0).clamp(0.0, 1.0);
    if (normalized > _currentPeak) {
      _currentPeak = normalized;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _decayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 80),
      painter: _VisualizerPainter(amplitudes: _amplitudes, color: widget.color),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;

  _VisualizerPainter({required this.amplitudes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final spacing = size.width / amplitudes.length;
    final barWidth = spacing * 0.7;

    for (int i = 0; i < amplitudes.length; i++) {
      final amp = amplitudes[i];
      final barHeight = 4.0 + (amp * (size.height - 4.0));
      final x = i * spacing + (spacing - barWidth) / 2;
      final y = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint..color = color.withValues(alpha: 0.3 + (amp * 0.7)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) {
    return true; // We repaint on every timer tick
  }
}
