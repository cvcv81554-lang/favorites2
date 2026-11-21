import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// فك الصورة بالمقاس الذي يحتاجه مكانها **حسب أبعادها الحقيقية** (تُقرأ من رأس الملف قبل الفك):
/// - cover: أصغر مقاس يغطي المكان كاملًا (صورة عريضة في مكان طولي تُفك بارتفاع المكان، لا بعرضه ⇒ لا تمطيط ولا ضبابية).
/// - contain: أصغر مقاس يظهر كاملًا داخل المكان.
/// لا تكبير أبدًا فوق الدقة الأصلية، وحد أعلى للذاكرة (~12 ميغابكسل).
class FitResize extends ImageProvider<FitKey> {
  const FitResize(this.provider, this.width, this.height, {this.cover = true});
  final ImageProvider<Object> provider; final int width, height; final bool cover;

  @override
  Future<FitKey> obtainKey(ImageConfiguration configuration) {
    Completer<FitKey>? completer; SynchronousFuture<FitKey>? result;
    provider.obtainKey(configuration).then((k) {
      final key = FitKey(k, width, height, cover);
      if (completer == null) { result = SynchronousFuture<FitKey>(key); } else { completer.complete(key); }
    });
    if (result != null) return result!;
    completer = Completer<FitKey>();
    return completer.future;
  }

  /// المقاس المستهدف لصورة أبعادها [iw]×[ih] (منطق نقي قابل للاختبار).
  static ui.TargetImageSize target(int iw, int ih, int w, int h, bool cover) {
    if (iw <= 0 || ih <= 0 || w <= 0 || h <= 0) return const ui.TargetImageSize();
    var s = cover ? max(w / iw, h / ih) : min(w / iw, h / ih);
    final px = iw * s * ih * s;
    if (px > 12e6) s *= sqrt(12e6 / px);
    if (s >= 1) return const ui.TargetImageSize();   // لا تكبير: الأصل كما هو
    return ui.TargetImageSize(width: max(1, (iw * s - 1e-6).ceil()), height: max(1, (ih * s - 1e-6).ceil()));
  }

  @override
  ImageStreamCompleter loadImage(FitKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> d(ui.ImmutableBuffer b, {ui.TargetImageSizeCallback? getTargetSize}) =>
      decode(b, getTargetSize: (iw, ih) => target(iw, ih, width, height, cover));
    return provider.loadImage(key.k, d);
  }
}

@immutable
class FitKey {
  const FitKey(this.k, this.w, this.h, this.cover);
  final Object k; final int w, h; final bool cover;
  @override bool operator ==(Object other) => other is FitKey && other.k == k && other.w == w && other.h == h && other.cover == cover;
  @override int get hashCode => Object.hash(k, w, h, cover);
}
