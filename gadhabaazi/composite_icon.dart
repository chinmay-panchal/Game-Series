import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('assets/images/starting.png');
  final original = img.decodeImage(file.readAsBytesSync());
  if (original == null) return;

  final width = original.width;
  final height = original.height;

  final bg = img.Image(width: width, height: height, numChannels: 4);
  // #D4AF37 -> R:212, G:175, B:55 (Gold Accent)
  // img.fill(bg, color: img.ColorRgba8(212, 175, 55, 255));

  // // #167B42 -> R:22, G:123, B:66 (Table Light Green)
  img.fill(bg, color: img.ColorRgba8(22, 123, 66, 255));

  img.compositeImage(bg, original);

  File('assets/images/app_icon_solid.png').writeAsBytesSync(img.encodePng(bg));
  print('Done');
}
