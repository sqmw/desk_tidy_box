import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img; // Re-enabled
import 'package:win32/win32.dart';

const int _shilJumbo = 0x4; // 256x256
const int _ildTransparent = 0x00000001;
const int _ildImage = 0x00000020;
const int _diNormal = 0x0003;
const String _iidIImageList = '{46EB5926-582E-4017-9FDF-E8998DAA0950}';

final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

// Cache
final LinkedHashMap<String, Uint8List?> _iconCache =
    LinkedHashMap<String, Uint8List?>();
const int _iconCacheCapacity = 100;
// Use version in cache keys to invalidate old entries if logic changes
const int _iconCacheVersion = 3;

class _IconTask {
  final String path;
  final int size;
  final Completer<Uint8List?> completer;
  _IconTask(this.path, this.size, this.completer);
}

class _IconLocation {
  final String path;
  final int index;
  const _IconLocation(this.path, this.index);
}

final Queue<_IconTask> _iconTaskQueue = Queue<_IconTask>();
int _activeIconIsolates = 0;
const int _maxIconIsolates = 3;

typedef _SHGetImageListNative =
    Int32 Function(Int32 iImageList, Pointer<GUID> riid, Pointer<Pointer> ppv);
typedef _SHGetImageListDart =
    int Function(int iImageList, Pointer<GUID> riid, Pointer<Pointer> ppv);

final _SHGetImageListDart _shGetImageList = _shell32
    .lookupFunction<_SHGetImageListNative, _SHGetImageListDart>('#727');

typedef _DrawIconExNative =
    Int32 Function(
      IntPtr hdc,
      Int32 xLeft,
      Int32 yTop,
      IntPtr hIcon,
      Int32 cxWidth,
      Int32 cyWidth,
      Uint32 istepIfAniCur,
      IntPtr hbrFlickerFreeDraw,
      Uint32 diFlags,
    );
typedef _DrawIconExDart =
    int Function(
      int hdc,
      int xLeft,
      int yTop,
      int hIcon,
      int cxWidth,
      int cyWidth,
      int istepIfAniCur,
      int hbrFlickerFreeDraw,
      int diFlags,
    );

final _DrawIconExDart _drawIconEx = _user32
    .lookupFunction<_DrawIconExNative, _DrawIconExDart>('DrawIconEx');

class IImageList extends IUnknown {
  IImageList(super.ptr);

  int getIcon(int i, int flags, Pointer<IntPtr> icon) => (ptr.ref.vtable + 10)
      .cast<
        Pointer<
          NativeFunction<Int32 Function(Pointer, Int32, Int32, Pointer<IntPtr>)>
        >
      >()
      .value
      .asFunction<
        int Function(Pointer, int, int, Pointer<IntPtr>)
      >()(ptr.ref.lpVtbl, i, flags, icon);
}

// SHCreateItemFromParsingName for Thumbnails
typedef _SHCreateItemFromParsingNameNative =
    Int32 Function(
      Pointer<Utf16> pszPath,
      Pointer pbc,
      Pointer<GUID> riid,
      Pointer<Pointer> ppv,
    );
typedef _SHCreateItemFromParsingNameDart =
    int Function(
      Pointer<Utf16> pszPath,
      Pointer pbc,
      Pointer<GUID> riid,
      Pointer<Pointer> ppv,
    );
final _SHCreateItemFromParsingName = _shell32
    .lookupFunction<
      _SHCreateItemFromParsingNameNative,
      _SHCreateItemFromParsingNameDart
    >('SHCreateItemFromParsingName');

/// Extracts an icon for the given [filePath].
///
/// [size] is the desired width/height.
/// Uses a combination of PrivateExtractIcons, SHGetImageList (Jumbo), and SHGetFileInfo.
Future<Uint8List?> extractIconAsync(String filePath, {int size = 96}) async {
  if (!Platform.isWindows) return null;

  final key = 'v$_iconCacheVersion|$filePath|$size';
  if (_iconCache.containsKey(key)) return _iconCache[key];

  final completer = Completer<Uint8List?>();
  _iconTaskQueue.add(_IconTask(filePath, size, completer));
  _drainIconTasks();

  return completer.future.then((value) {
    if (value != null) {
      _iconCache[key] = value;
      if (_iconCache.length > _iconCacheCapacity) {
        _iconCache.remove(_iconCache.keys.first);
      }
    }
    return value;
  });
}

void _drainIconTasks() {
  while (_activeIconIsolates < _maxIconIsolates && _iconTaskQueue.isNotEmpty) {
    final task = _iconTaskQueue.removeFirst();
    _activeIconIsolates++;

    Isolate.run(() => _extractIconIsolate(task.path, task.size))
        .then((result) {
          task.completer.complete(result);
        })
        .catchError((e) {
          // Fallback to main isolate if strict isolation fails
          try {
            final result = _extractIconIsolate(task.path, task.size);
            task.completer.complete(result);
          } catch (e2) {
            task.completer.complete(null);
          }
        })
        .whenComplete(() {
          _activeIconIsolates--;
          _drainIconTasks();
        });
  }
}

// This function runs in isolate or main thread
Uint8List? _extractIconIsolate(String filePath, int size) {
  final hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  try {
    Uint8List? result;
    // 1. Try Jumbo icon (includes disk check for folders/files)
    result = _extractJumboIconPng(filePath, size);

    // 2. If failure or empty, try basic file info fallback
    if (result == null) {
      final location = _getIconLocation(filePath);
      if (location != null && location.path.isNotEmpty) {
        final hicon = _extractHiconFromLocation(
          location.path,
          location.index,
          size,
        );
        if (hicon != 0) {
          final png = _hiconToPng(hicon, size: size);
          DestroyIcon(hicon);
          if (png != null && png.isNotEmpty) {
            result = png;
          }
        }
      }
    }

    // 3. Final fallback: Standard SHGetFileInfo icon (reliable but smaller)
    if (result == null) {
      result = _extractStandardIcon(filePath, size);
    }

    return result;
  } finally {
    if (hr == S_OK || hr == S_FALSE) CoUninitialize();
  }
}

/// Generates a thumbnail for a file (image, video, etc.)
Future<Uint8List?> getThumbnailAsync(String filePath, {int size = 256}) async {
  if (!Platform.isWindows) return null;
  final key = 'thumb:v$_iconCacheVersion|$filePath|$size';
  if (_iconCache.containsKey(key)) return _iconCache[key];

  final result = await Isolate.run(() => _getThumbnailIsolate(filePath, size));
  if (result != null) {
    _iconCache[key] = result;
  }
  return result;
}

Uint8List? _getThumbnailIsolate(String filePath, int size) {
  final hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  // ... (rest of implementation) ...
  // Wait, I need to include the FULL implementation here or write_to_file will produce truncated file if I ellipsis.
  // I must include FULL TEXT.

  final pathPtr = filePath.toNativeUtf16();
  final riid = calloc<GUID>();
  final ppv = calloc<Pointer>();
  final hbitmapPtr = calloc<IntPtr>();

  try {
    // IID_IShellItem = 43826d1e-e718-42ee-bc55-a1e261c37bfe
    final iidShellItemStr = '{43826d1e-e718-42ee-bc55-a1e261c37bfe}'
        .toNativeUtf16();
    IIDFromString(iidShellItemStr, riid);
    calloc.free(iidShellItemStr);

    final hr = _SHCreateItemFromParsingName(pathPtr, nullptr, riid, ppv);

    if (FAILED(hr)) return null;

    final shellItem = IShellItem(ppv.value.cast());

    // IID_IShellItemImageFactory = bcc18b79-ba16-442f-80c4-8a59c30c463b
    final iidImgFact = calloc<GUID>();
    final iidImgFactStr = '{bcc18b79-ba16-442f-80c4-8a59c30c463b}'
        .toNativeUtf16();
    IIDFromString(iidImgFactStr, iidImgFact);
    calloc.free(iidImgFactStr);

    final ppvImgFact = calloc<Pointer>();
    final hrQI = shellItem.queryInterface(iidImgFact, ppvImgFact);
    calloc.free(iidImgFact);

    if (FAILED(hrQI)) {
      shellItem.release();
      return null;
    }

    final imageFactory = IShellItemImageFactory(ppvImgFact.value.cast());

    // SIIGBF_THUMBNAILONLY = 0x02
    final flags = 0x02;

    final sizeStruct = calloc<SIZE>();
    sizeStruct.ref.cx = size;
    sizeStruct.ref.cy = size;

    final hrGet = imageFactory.getImage(sizeStruct.ref, flags, hbitmapPtr);

    calloc.free(sizeStruct);
    imageFactory.release();
    shellItem.release();

    if (FAILED(hrGet) || hbitmapPtr.value == 0) return null;

    final png = _hbitmapToPng(hbitmapPtr.value);
    DeleteObject(hbitmapPtr.value);
    return png;
  } catch (e) {
    return null;
  } finally {
    calloc.free(pathPtr);
    calloc.free(riid);
    calloc.free(ppv);
    calloc.free(hbitmapPtr);
    if (hrInit == S_OK || hrInit == S_FALSE) CoUninitialize();
  }
}

// -----------------------------------------------------------------------------
// Core Implementation Helpers
// -----------------------------------------------------------------------------

Uint8List? _extractJumboIconPng(String filePath, int desiredSize) {
  bool isFolder = false;
  try {
    isFolder =
        FileSystemEntity.typeSync(filePath) == FileSystemEntityType.directory;
  } catch (_) {}

  final iconIndex = _getSystemIconIndex(filePath, checkDisk: isFolder);
  if (iconIndex < 0) return null;

  final iid = calloc<GUID>();
  final iidStr = _iidIImageList.toNativeUtf16();
  final hrIID = IIDFromString(iidStr, iid);
  calloc.free(iidStr);
  if (FAILED(hrIID)) {
    calloc.free(iid);
    return null;
  }
  final imageListPtr = calloc<COMObject>();

  try {
    final hres = _shGetImageList(_shilJumbo, iid, imageListPtr.cast());
    if (FAILED(hres) || imageListPtr.ref.isNull) return null;

    final imageList = IImageList(imageListPtr);
    final hiconPtr = calloc<IntPtr>();
    try {
      final hres2 = imageList.getIcon(
        iconIndex,
        _ildTransparent | _ildImage,
        hiconPtr,
      );
      if (FAILED(hres2) || hiconPtr.value == 0) return null;

      final png = _hiconToPng(hiconPtr.value, size: desiredSize);
      DestroyIcon(hiconPtr.value);
      return png;
    } finally {
      calloc.free(hiconPtr);
      imageList.release();
    }
  } catch (_) {
    return null;
  } finally {
    calloc.free(iid);
    calloc.free(imageListPtr);
  }
}

int _getSystemIconIndex(String filePath, {bool checkDisk = false}) {
  final pathPtr = filePath.toNativeUtf16();
  final shFileInfo = calloc<SHFILEINFO>();

  int flags = SHGFI_SYSICONINDEX;
  if (!checkDisk) {
    flags |= SHGFI_USEFILEATTRIBUTES;
  }

  int attrs = 0;
  if (!checkDisk) {
    try {
      final type = FileSystemEntity.typeSync(filePath);
      if (type == FileSystemEntityType.directory) {
        attrs = FILE_ATTRIBUTE_DIRECTORY;
      } else {
        attrs = FILE_ATTRIBUTE_NORMAL;
      }
    } catch (_) {
      attrs = FILE_ATTRIBUTE_NORMAL;
    }
  }

  try {
    final hr = SHGetFileInfo(
      pathPtr.cast(),
      attrs,
      shFileInfo.cast(),
      sizeOf<SHFILEINFO>(),
      flags,
    );

    if (hr == 0) return -1;
    return shFileInfo.ref.iIcon;
  } finally {
    calloc.free(pathPtr);
    calloc.free(shFileInfo);
  }
}

Uint8List? _hiconToPng(int icon, {required int size}) {
  final screenDC = GetDC(NULL);
  if (screenDC == 0) return null;
  final memDC = CreateCompatibleDC(screenDC);
  if (memDC == 0) {
    ReleaseDC(NULL, screenDC);
    return null;
  }

  final bmi = calloc<BITMAPINFO>();
  final ppBits = calloc<Pointer<Void>>();
  var dib = 0;
  var oldBmp = 0;
  try {
    bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi.ref.bmiHeader.biWidth = size;
    bmi.ref.bmiHeader.biHeight = -size; // top-down DIB
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;

    dib = CreateDIBSection(screenDC, bmi, DIB_RGB_COLORS, ppBits, NULL, 0);
    if (dib == 0) return null;

    oldBmp = SelectObject(memDC, dib);

    // Clear
    final pixelCount = size * size * 4;
    final pixelsView = ppBits.value.cast<Uint8>().asTypedList(pixelCount);
    pixelsView.fillRange(0, pixelsView.length, 0);

    _drawIconEx(memDC, 0, 0, icon, size, size, 0, NULL, _diNormal);

    final image = img.Image.fromBytes(
      width: size,
      height: size,
      bytes: pixelsView.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
      rowStride: size * 4,
    );

    // Alpha masking logic for HICON
    final mask = _readMaskBitsFromIcon(icon, size, size);
    final alphaMeaningful = _alphaHasMeaning(image);
    if (mask != null) {
      _applyMaskToAlpha(image, mask, alphaMeaningful: alphaMeaningful);
    } else if (!alphaMeaningful) {
      _forceOpaque(image);
    }
    _unpremultiplyAlphaIfNeeded(image);

    final output = (image.width == size && image.height == size)
        ? image
        : img.copyResize(image, width: size, height: size);

    return Uint8List.fromList(img.encodePng(output));
  } finally {
    if (oldBmp != 0) SelectObject(memDC, oldBmp);
    if (dib != 0) DeleteObject(dib);
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);
    calloc.free(ppBits);
    calloc.free(bmi);
  }
}

Uint8List? _hbitmapToPng(int hbitmap) {
  final screenDC = GetDC(NULL);
  if (screenDC == 0) return null;
  final memDC = CreateCompatibleDC(screenDC);
  if (memDC == 0) {
    ReleaseDC(NULL, screenDC);
    return null;
  }

  final bitmap = calloc<BITMAP>();
  final bmi = calloc<BITMAPINFO>();

  try {
    final res = GetObject(hbitmap, sizeOf<BITMAP>(), bitmap.cast());
    if (res == 0) return null;

    final width = bitmap.ref.bmWidth;
    final height = bitmap.ref.bmHeight.abs();

    bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi.ref.bmiHeader.biWidth = width;
    bmi.ref.bmiHeader.biHeight = -height;
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;

    final stride = width * 4;
    final totalSize = stride * height;
    final buffer = calloc<Uint8>(totalSize);

    final result = GetDIBits(
      screenDC,
      hbitmap,
      0,
      height,
      buffer.cast(),
      bmi,
      DIB_RGB_COLORS,
    );

    if (result == 0) {
      calloc.free(buffer);
      return null;
    }

    final pixels = Uint8List.fromList(buffer.asTypedList(totalSize));
    calloc.free(buffer);

    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
      rowStride: stride,
    );
    // Thumbnails from IShellItemImageFactory are usually decent
    return Uint8List.fromList(img.encodePng(image));
  } finally {
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);
    calloc.free(bitmap);
    calloc.free(bmi);
  }
}

_IconLocation? _getIconLocation(String filePath) {
  final pathPtr = filePath.toNativeUtf16();
  final shFileInfo = calloc<SHFILEINFO>();
  final result = SHGetFileInfo(
    pathPtr.cast(),
    0,
    shFileInfo.cast(),
    sizeOf<SHFILEINFO>(),
    SHGFI_ICONLOCATION,
  );
  calloc.free(pathPtr);
  if (result == 0) {
    calloc.free(shFileInfo);
    return null;
  }

  final iconPath = shFileInfo.ref.szDisplayName;
  final iconIndex = shFileInfo.ref.iIcon;
  calloc.free(shFileInfo);

  if (iconPath.isEmpty) return null;
  return _IconLocation(iconPath, iconIndex);
}

Uint8List? _extractStandardIcon(String filePath, int size) {
  final pathPtr = filePath.toNativeUtf16();
  final shFileInfo = calloc<SHFILEINFO>();

  // SHGFI_ICON | SHGFI_LARGEICON gives 32x32 usually.
  // We can try to use SHGFI_USEFILEATTRIBUTES if we want speed for generic files,
  // but for "real" icons we should probably access the file (no passed attributes).
  try {
    final result = SHGetFileInfo(
      pathPtr.cast(),
      0,
      shFileInfo.cast(),
      sizeOf<SHFILEINFO>(),
      SHGFI_ICON | SHGFI_LARGEICON, // Large is typically 32x32
    );

    if (result == 0 || shFileInfo.ref.hIcon == 0) return null;

    final hicon = shFileInfo.ref.hIcon;
    final png = _hiconToPng(hicon, size: size); // Attempt to scale if needed
    DestroyIcon(hicon);
    return png;
  } finally {
    calloc.free(pathPtr);
    calloc.free(shFileInfo);
  }
}

// Helpers
int _extractHiconFromLocation(String iconPath, int iconIndex, int size) {
  final iconPathPtr = iconPath.toNativeUtf16();
  final hiconPtr = calloc<IntPtr>();
  final iconIdPtr = calloc<Uint32>();

  // PrivateExtractIconsW
  final extracted = PrivateExtractIcons(
    iconPathPtr.cast(),
    iconIndex,
    size,
    size,
    hiconPtr,
    iconIdPtr,
    1,
    0,
    // Note: PrivateExtractIconsW takes 8 args in win32 package 5.0.0
    // If getting error about 9 args, it means flags was optional or I miscounted.
    // Checking definitions... win32 usually follows MSDN.
    // HRESULT PrivateExtractIconsW(LPCWSTR szFileName, int nIconIndex, int cxIcon, int cyIcon, HICON *phicon, UINT *piconid, UINT nIcons, UINT flags);
    // That is 8 arguments.
  );

  calloc.free(iconPathPtr);
  calloc.free(iconIdPtr);

  final hicon = hiconPtr.value;
  calloc.free(hiconPtr);

  if (extracted <= 0 || hicon == 0) return 0;
  return hicon;
}

class _MaskBits {
  final Uint8List bytes;
  final int width;
  final int height;
  final int rowBytes;
  const _MaskBits(this.bytes, this.width, this.height, this.rowBytes);
}

_MaskBits? _readMaskBitsFromIcon(int hicon, int maxWidth, int maxHeight) {
  final iconInfo = calloc<ICONINFO>();
  var hbmMask = 0;
  var hbmColor = 0;
  try {
    final ok = GetIconInfo(hicon, iconInfo);
    if (ok == 0) return null;
    hbmMask = iconInfo.ref.hbmMask;
    hbmColor = iconInfo.ref.hbmColor;
    if (hbmMask == 0) return null;
    return _readMaskBits(hbmMask, maxWidth, maxHeight, hasColor: hbmColor != 0);
  } finally {
    if (hbmMask != 0) DeleteObject(hbmMask);
    if (hbmColor != 0) DeleteObject(hbmColor);
    calloc.free(iconInfo);
  }
}

_MaskBits? _readMaskBits(
  int hbmMask,
  int maxWidth,
  int maxHeight, {
  required bool hasColor,
}) {
  final bitmap = calloc<BITMAP>();
  try {
    final res = GetObject(hbmMask, sizeOf<BITMAP>(), bitmap.cast());
    if (res == 0) return null;
    final maskWidth = bitmap.ref.bmWidth;
    var maskHeight = bitmap.ref.bmHeight.abs();
    if (!hasColor && maskHeight >= maxHeight * 2) {
      maskHeight = maskHeight ~/ 2;
    }

    final targetWidth = math.min(maxWidth, maskWidth);
    final targetHeight = math.min(maxHeight, maskHeight);
    if (targetWidth <= 0 || targetHeight <= 0) return null;

    final rowBytes = ((maskWidth + 31) ~/ 32) * 4;
    final totalBytes = rowBytes * maskHeight;
    final buffer = calloc<Uint8>(totalBytes);
    final bmi = calloc<BITMAPINFO>();
    final dc = GetDC(NULL);
    try {
      if (dc == 0) return null;
      bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = maskWidth;
      bmi.ref.bmiHeader.biHeight = -maskHeight;
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 1;
      bmi.ref.bmiHeader.biCompression = BI_RGB;
      final lines = GetDIBits(
        dc,
        hbmMask,
        0,
        maskHeight,
        buffer.cast(),
        bmi,
        DIB_RGB_COLORS,
      );
      if (lines == 0) return null;

      final bytes = Uint8List.fromList(buffer.asTypedList(totalBytes));
      return _MaskBits(bytes, targetWidth, targetHeight, rowBytes);
    } finally {
      if (dc != 0) ReleaseDC(NULL, dc);
      calloc.free(bmi);
      calloc.free(buffer);
    }
  } finally {
    calloc.free(bitmap);
  }
}

bool _alphaHasMeaning(img.Image image) {
  if (!image.hasAlpha) return false;
  var hasTransparent = false;
  var hasOpaque = false;
  for (final p in image) {
    final a = p.a.toInt();
    if (a == 0) {
      hasTransparent = true;
    } else if (a == 255) {
      hasOpaque = true;
    } else {
      return true;
    }
  }
  return hasTransparent && hasOpaque;
}

void _applyMaskToAlpha(
  img.Image image,
  _MaskBits mask, {
  required bool alphaMeaningful,
}) {
  if (!image.hasAlpha) return;
  final width = math.min(image.width, mask.width);
  final height = math.min(image.height, mask.height);
  final bytes = mask.bytes;
  for (var y = 0; y < height; y++) {
    final rowOffset = y * mask.rowBytes;
    for (var x = 0; x < width; x++) {
      final byteIndex = rowOffset + (x >> 3);
      final bitMask = 0x80 >> (x & 7);
      final transparent = (bytes[byteIndex] & bitMask) != 0;
      final p = image.getPixel(x, y);
      if (transparent) {
        p
          ..r = 0
          ..g = 0
          ..b = 0
          ..a = 0;
      } else if (!alphaMeaningful) {
        p.a = 255;
      }
    }
  }
}

void _forceOpaque(img.Image image) {
  if (!image.hasAlpha) return;
  for (final p in image) {
    p.a = 255;
  }
}

void _unpremultiplyAlphaIfNeeded(img.Image image) {
  if (!image.hasAlpha) return;
  if (!_isLikelyPremultiplied(image)) return;
  _unpremultiplyAlpha(image);
}

bool _isLikelyPremultiplied(img.Image image) {
  if (!image.hasAlpha) return false;
  var samples = 0;
  var premultiplied = 0;
  for (final p in image) {
    final a = p.a.toInt();
    if (a == 0 || a == 255) continue;
    samples++;
    if (p.r <= a && p.g <= a && p.b <= a) {
      premultiplied++;
    }
    if (samples >= 2000) break;
  }
  if (samples == 0) return false;
  return premultiplied / samples >= 0.9;
}

void _unpremultiplyAlpha(img.Image image) {
  for (final p in image) {
    final a = p.a.toInt();
    if (a == 0) {
      p
        ..r = 0
        ..g = 0
        ..b = 0;
      continue;
    }
    if (a >= 255) continue;
    final scale = 255.0 / a;
    p
      ..r = (p.r * scale).round().clamp(0, 255)
      ..g = (p.g * scale).round().clamp(0, 255)
      ..b = (p.b * scale).round().clamp(0, 255);
  }
}
