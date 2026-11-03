/// Counts UTF-8 output bytes without allocating an encoded copy.
bool exceedsUtf8Limit(String text, int limit) {
  if (text.length > limit) return true;
  var bytes = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c < 0x80) {
      bytes++;
    } else if (c < 0x800) {
      bytes += 2;
    } else if (c >= 0xd800 &&
        c <= 0xdbff &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) >= 0xdc00 &&
        text.codeUnitAt(i + 1) <= 0xdfff) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
    if (bytes > limit) return true;
  }
  return false;
}

/// Bounds JSON container nesting before invoking Dart's recursive decoder.
void checkJsonDepth(String text, {int maxDepth = 64}) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == 0x5c) {
        escaped = true;
      } else if (c == 0x22) {
        inString = false;
      }
    } else if (c == 0x22) {
      inString = true;
    } else if (c == 0x7b || c == 0x5b) {
      if (++depth > maxDepth) {
        throw FormatException('JSON nesting exceeds $maxDepth');
      }
    } else if (c == 0x7d || c == 0x5d) {
      depth--;
    }
  }
}
