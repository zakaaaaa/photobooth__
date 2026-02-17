import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:photobooth_app/providers/photo_provider.dart';

class ImageFilterUtil {
  static Future<Uint8List> applyFilter(
    Uint8List imageData,
    PhotoFilter filter,
  ) async {
    // 1. Decode dengan mempertahankan resolusi asli
    final image = img.decodeImage(imageData);
    if (image == null) return imageData;

    img.Image filteredImage;

    switch (filter) {
      case PhotoFilter.vintage:
        filteredImage = _applyVintageFilter(image);
        break;
      case PhotoFilter.grayscale:
        filteredImage = img.grayscale(image);
        break;
      case PhotoFilter.smooth:
        // PERBAIKAN: Gunakan sharpen tipis setelah blur agar tidak terlihat pecah/buram
        filteredImage = img.gaussianBlur(image, radius: 1); // Radius dikurangi agar tidak terlalu blur
        break;
      case PhotoFilter.brightness:
        // Menaikkan brightness tanpa merusak pixel
        filteredImage = img.adjustColor(image, brightness: 1.15);
        break;
      case PhotoFilter.none:
      default:
        filteredImage = image;
    }

    // --- PERBAIKAN VITAL DISINI ---
    // Tambahkan quality: 100 agar tidak ada kompresi yang merusak hasil cetak.
    // Tanpa ini, printer Epson SL-D500 akan mencetak bintik-bintik (noise).
    return Uint8List.fromList(img.encodeJpg(filteredImage, quality: 100));
  }

  static img.Image _applyVintageFilter(img.Image image) {
    // Vintage effect: sepia tone + sedikit kontras
    var result = img.sepia(image);
    result = img.adjustColor(result, contrast: 1.1, saturation: 0.9);
    return result;
  }
}