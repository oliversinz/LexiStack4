/// Deterministic, platform-stable random numbers.
///
/// Implements Mulberry32 (Tommy Ettinger's 32-bit generator) and FNV-1a
/// string hashing using only integer arithmetic that stays below 2^53. All
/// intermediate values are therefore exact both on the Dart VM (64-bit ints)
/// and on the web (JavaScript doubles), so identical seeds produce identical
/// sequences everywhere. `dart:math` `Random(seed)` is deliberately avoided
/// because its sequence is not specified to match across platforms.
library;

const int _two32 = 4294967296;

/// Exact (a * b) mod 2^32 for a, b in [0, 2^32).
int mul32(int a, int b) {
  final aLo = a % 65536;
  final aHi = a ~/ 65536;
  final bLo = b % 65536;
  final bHi = b ~/ 65536;
  final cross = (aHi * bLo + aLo * bHi) % 65536;
  return (aLo * bLo + cross * 65536) % _two32;
}

/// 32-bit FNV-1a hash of the UTF-16 code units of [s].
int fnv1a32(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h = (h ^ c) % _two32;
    h = mul32(h, 0x01000193);
  }
  return h;
}

class Prng {
  Prng(int seed) : state = ((seed % _two32) + _two32) % _two32;

  /// Current 32-bit state; persisting it lets a saved game continue the
  /// exact same sequence after reload.
  int state;

  int nextUint32() {
    state = (state + 0x6D2B79F5) % _two32;
    var t = state;
    t = mul32((t ^ (t ~/ 32768)) % _two32, t | 1);
    t =
        (t ^ ((t + mul32((t ^ (t ~/ 128)) % _two32, t | 61)) % _two32)) %
        _two32;
    return (t ^ (t ~/ 16384)) % _two32;
  }

  /// Uniform-ish integer in [0, max). Modulo bias is negligible for the tiny
  /// ranges used here (at most 16).
  int nextInt(int max) => nextUint32() % max;

  /// In-place Fisher–Yates shuffle.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}
