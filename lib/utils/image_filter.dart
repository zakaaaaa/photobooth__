import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:photobooth_app/providers/photo_provider.dart';

class ImageFilterUtil {
  static Future<Uint8List> applyFilter(
    Uint8List imageData,
    PhotoFilter filter,
  ) async {
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
        filteredImage = img.gaussianBlur(image, radius: 2);
        break;
      case PhotoFilter.brightness:
        filteredImage = img.adjustColor(image, brightness: 1.2);
        break;
      case PhotoFilter.none:
      default:
        filteredImage = image;
    }

    return Uint8List.fromList(img.encodeJpg(filteredImage));
  }

  static img.Image _applyVintageFilter(img.Image image) {
    // Vintage effect: sepia tone + vignette
    var result = img.sepia(image);
    result = img.adjustColor(result, contrast: 1.1, saturation: 0.8);
    return result;
  }
}