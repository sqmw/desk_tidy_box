import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

const int _shilJumbo = 0x4;
const int _ildTransparent = 0x00000001;
const int _ildImage = 0x00000020;
const int _diNormal = 0x0003;
const String _iidIImageList = '{46EB5926-582E-4017-9FDF-E8998DAA0950}';

final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

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

// Cache
final LinkedHashMap<String, Uint8List?> _iconCache =
    LinkedHashMap<String, Uint8List?>();
const int _iconCacheCapacity = 100;

class _IconTask {
  final String path;
  final int size;
  final Completer<Uint8List?> completer;
  _IconTask(this.path, this.size, this.completer);
}

final Queue<_IconTask> _iconTaskQueue = Queue<_IconTask>();
int _activeIconIsolates = 0;
const int _maxIconIsolates = 3;

Future<Uint8List?> extractIconAsync(String filePath, {int size = 96}) async {
  if (!Platform.isWindows) return null;

  final key = '$filePath|$size';
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
          // Fallback to main isolate if strict isolation fails (e.g. COM init)
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
  // Use CoInitialize for shell operations if needed
  final hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  try {
    return _extractJumboIconPng(filePath, size);
  } finally {
    if (hr == S_OK || hr == S_FALSE) CoUninitialize();
  }
}

Uint8List? _extractJumboIconPng(String filePath, int desiredSize) {
  // Determine if we should check disk (for folders)
  bool isFolder = false;
  try {
    isFolder =
        FileSystemEntity.typeSync(filePath) == FileSystemEntityType.directory;
  } catch (_) {}

  // For folders, we want to check disk to get the thumbnail (if available)
  // For files, we typically use attributes for speed, unless it's an exe?
  // GeekDesk suggests: checkDisk = true means NO USEFILEATTRIBUTES.
  // We want checkDisk = true for folders.

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
    // SHIL_JUMBO = 0x4 (256x256), SHIL_EXTRALARGE = 0x2 (48x48)
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

  // If using attributes, we must pass them. If checking disk, pass 0.
  int attrs = 0;
  if (!checkDisk) {
    final type = FileSystemEntity.typeSync(filePath);
    if (type == FileSystemEntityType.directory) {
      attrs = FILE_ATTRIBUTE_DIRECTORY;
    } else {
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

    // Convert to Image for PNG encoding
    final image = img.Image.fromBytes(
      width: size,
      height: size,
      bytes: pixelsView.buffer,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
      rowStride: size * 4,
    );

    // Simple alpha fix (unpremultiply ish if needed, but Windows icons usually valid)
    // We'll trust image lib for now. Windows draws premultiplied usually.
    // If it looks dark/weird we might need the alpha fix from desktop_helper.

    // Resize if needed
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

// SHCreateItemFromParsingName
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

Future<Uint8List?> getThumbnailAsync(String filePath, {int size = 256}) async {
  if (!Platform.isWindows) return null;
  final key = 'thumb:$filePath|$size';
  if (_iconCache.containsKey(key)) return _iconCache[key];

  // Use Isolate
  final result = await Isolate.run(() => _getThumbnailIsolate(filePath, size));
  if (result != null) {
    _iconCache[key] = result;
  }
  return result;
}

Uint8List? _getThumbnailIsolate(String filePath, int size) {
  final hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

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
    final flags = 0x02; // Just the thumbnail, please.

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

    return Uint8List.fromList(img.encodePng(image));
  } finally {
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);
    calloc.free(bitmap);
    calloc.free(bmi);
  }
}
