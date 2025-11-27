import 'dart:typed_data';
import 'dart:io';
import 'package:image/image.dart' as img;

class ClipImageProcessor {
  // CLIP Standard Constants
  static const List<double> mean = [0.48145466, 0.4578275, 0.40821073];
  static const List<double> std = [0.26862954, 0.26130258, 0.27577711];

  /// Reads file, resizes, crops, normalizes, and returns Float32List [1, 3, 224, 224]
  static Future<Float32List?> preprocess(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) return null;

    // 1. Resize (Shortest side to 224)
    int w = image.width;
    int h = image.height;
    int target = 224;
    
    img.Image resized;
    if (w < h) {
      resized = img.copyResize(image, width: target);
    } else {
      resized = img.copyResize(image, height: target);
    }

    // 2. Center Crop (224x224)
    final cropped = img.copyResizeCropSquare(resized, size: target);

    // 3. Convert to Float32 List (NCHW format: Batch, Channels, Height, Width)
    // Size: 1 * 3 * 224 * 224 = 150,528 float values
    final Float32List inputData = Float32List(1 * 3 * 224 * 224);
    
    int pixelIndex = 0;
    // Iterate pixels and separate channels
    // Planar format (RRRR... GGGG... BBBB...)
    int rOffset = 0;
    int gOffset = 224 * 224;
    int bOffset = 224 * 224 * 2;

    for (var y = 0; y < 224; y++) {
      for (var x = 0; x < 224; x++) {
        final pixel = cropped.getPixel(x, y);
        
        // Normalize: (Value/255 - Mean) / Std
        double r = (pixel.r / 255.0 - mean[0]) / std[0];
        double g = (pixel.g / 255.0 - mean[1]) / std[1];
        double b = (pixel.b / 255.0 - mean[2]) / std[2];

        inputData[rOffset + pixelIndex] = r;
        inputData[gOffset + pixelIndex] = g;
        inputData[bOffset + pixelIndex] = b;
        
        pixelIndex++;
      }
    }

    return inputData;
  }
}
