import 'dart:ffi';
import 'dart:io';

/// Replaces [destination] from the same filesystem, without first deleting the
/// old file. The Windows implementation uses a single MoveFileExW operation.
Future<void> replaceFile(File temporary, String destination) async {
  if (!Platform.isWindows) {
    await temporary.rename(destination);
    return;
  }
  final kernel = DynamicLibrary.open('kernel32.dll');
  final heap =
      kernel.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetProcessHeap')();
  final allocate = kernel.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
      Pointer<Void> Function(Pointer<Void>, int, int)>('HeapAlloc');
  final free = kernel.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
      int Function(Pointer<Void>, int, Pointer<Void>)>('HeapFree');
  final move = kernel.lookupFunction<
      Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
      int Function(Pointer<Uint16>, Pointer<Uint16>, int)>('MoveFileExW');
  final lastError =
      kernel.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  Pointer<Uint16> makeWide(String path) {
    var full = File(path).absolute.path;
    if (!full.startsWith(r'\\?\')) {
      full = full.startsWith(r'\\')
          ? r'\\?\UNC\' + full.substring(2)
          : r'\\?\' + full;
    }
    final units = full.codeUnits;
    final memory =
        allocate(heap, 0, (units.length + 1) * sizeOf<Uint16>()).cast<Uint16>();
    if (memory == nullptr) {
      throw const FileSystemException('Unable to allocate path buffer');
    }
    final buffer = memory.asTypedList(units.length + 1);
    buffer.setRange(0, units.length, units);
    buffer[units.length] = 0;
    return memory;
  }

  Pointer<Uint16>? source;
  Pointer<Uint16>? target;
  try {
    source = makeWide(temporary.path);
    target = makeWide(destination);
    // MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
    if (move(source, target, 0x1 | 0x8) == 0) {
      final code = lastError();
      throw FileSystemException('Atomic output replacement failed', destination,
          OSError('MoveFileExW', code));
    }
  } finally {
    if (source != null) free(heap, 0, source.cast<Void>());
    if (target != null) free(heap, 0, target.cast<Void>());
  }
}
