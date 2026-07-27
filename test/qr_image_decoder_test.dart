import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:syncmesh_audio/services/qr_image_decoder_service.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  test('decodes a Receiver QR payload from a PNG file', () async {
    const payload = '192.168.1.10:5050:12345678:Receiver:device-1';
    final matrix = Encoder.encode(payload, ErrorCorrectionLevel.h).matrix!;
    const scale = 6;
    const margin = 4;
    final bitmap = image.Image(
      width: (matrix.width + margin * 2) * scale,
      height: (matrix.height + margin * 2) * scale,
      numChannels: 4,
    );
    image.fill(bitmap, color: image.ColorRgba8(255, 255, 255, 255));
    for (var x = 0; x < matrix.width; x++) {
      for (var y = 0; y < matrix.height; y++) {
        if (matrix.get(x, y) == 1) {
          image.fillRect(
            bitmap,
            x1: (x + margin) * scale,
            y1: (y + margin) * scale,
            x2: (x + margin) * scale + scale - 1,
            y2: (y + margin) * scale + scale - 1,
            color: image.ColorRgba8(0, 0, 0, 255),
          );
        }
      }
    }
    final directory = await Directory.systemTemp.createTemp('syncmesh-qr-');
    final file = File('${directory.path}/receiver.png');
    await file.writeAsBytes(image.encodePng(bitmap));

    expect(await QrImageDecoderService().decodeFile(file.path), payload);
    await directory.delete(recursive: true);
  });
}
