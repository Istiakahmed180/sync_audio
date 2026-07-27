import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:zxing2/qrcode.dart';

class QrImageDecoderService {
  Future<String?> decodeFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = image.decodeImage(bytes);
      if (decoded == null) return null;
      final rgba = decoded
          .convert(numChannels: 4)
          .getBytes(order: image.ChannelOrder.rgba);
      final source = RGBLuminanceSource(
        decoded.width,
        decoded.height,
        Int32List.fromList(rgba.buffer.asInt32List()),
      );
      return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
    } on Exception {
      return null;
    }
  }
}
