import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:photobooth_app/providers/photo_provider.dart';

class ImageFilterUtil {
  static Future<Uint8List> applyFilter(
    Uint8List imageData,
    PhotoFilter filter,
  ) async {
    // 1. Decode dengan mempertahankan resolusi asli
    var image = img.decodeImage(imageData);
    if (image == null) return imageData;

    // 1.2 Limit resolusi agar tidak terlalu berat (DSLR 24MP → 3000px ~9MP)
    // 3000px sudah sangat tajam untuk cetak 4R profesional
    if (image.width > 3000 || image.height > 3000) {
      if (image.width > image.height) {
        image = img.copyResize(image, width: 3000);
      } else {
        image = img.copyResize(image, height: 3000);
      }
    }

    // 1.5 Auto-mirror (horizontal flip) agar hasilnya seperti selfie
    final selfieImage = img.flipHorizontal(image);

    img.Image filteredImage;

    switch (filter) {
      case PhotoFilter.vintage:
        filteredImage = _applyVintageFilter(selfieImage);
        break;
      case PhotoFilter.grayscale:
        filteredImage = img.grayscale(selfieImage);
        break;
      case PhotoFilter.smooth:
        // PERBAIKAN: Gunakan sharpen tipis setelah blur agar tidak terlihat pecah/buram
        filteredImage = img.gaussianBlur(selfieImage, radius: 1); 
        break;
      case PhotoFilter.brightness:
        filteredImage = img.adjustColor(selfieImage, brightness: 1.15);
        break;
      case PhotoFilter.none:
      default:
        filteredImage = selfieImage;
    }

    // JPEG quality 98 adalah sweet spot (hampir lossless tapi jauh lebih ringan dari PNG)
    return Uint8List.fromList(img.encodeJpg(filteredImage, quality: 98));
  }

  static img.Image _applyVintageFilter(img.Image image) {
    // Vintage effect: sepia tone + sedikit kontras
    var result = img.sepia(image);
    result = img.adjustColor(result, contrast: 1.1, saturation: 0.9);
    return result;
  }
}