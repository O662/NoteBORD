import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Where a picture comes from: the tablet's photos and files, or the camera.
enum PhotoOrigin { tablet, camera }

/// Gets a picture's file for the page. Tests supply their own.
abstract class PhotoPicker {
  /// Whether this device can take a photo for us.
  bool get hasCamera;

  /// The chosen picture's bytes, or null if nothing was chosen.
  Future<Uint8List?> pick(PhotoOrigin origin);
}

class DevicePhotoPicker implements PhotoPicker {
  final _picker = ImagePicker();

  @override
  bool get hasCamera => _picker.supportsImageSource(ImageSource.camera);

  @override
  Future<Uint8List?> pick(PhotoOrigin origin) async {
    // Large photos are scaled down to 2400 px: plenty for a page, and it
    // keeps the notebook small.
    final file = await _picker.pickImage(
      source: origin == PhotoOrigin.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 90,
    );
    return file?.readAsBytes();
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => DevicePhotoPicker());
