// PiliPlus ImageDoubleTapGestureRecognizer; GPL-3.0-or-later.
// Flutter's checkUp hook is private: record the same accepted double-tap
// timestamp through its public callback without replacing SDK recognition.
import 'package:flutter/gestures.dart';

class ImageDoubleTapGestureRecognizer extends DoubleTapGestureRecognizer {
  Duration timeStamp = Duration.zero;
  Duration _lastUp = Duration.zero;
  final _routes = <int, PointerRoute>{};

  @override
  set onDoubleTap(GestureDoubleTapCallback? callback) {
    super.onDoubleTap = callback == null
        ? null
        : () {
            timeStamp = _lastUp;
            callback();
          };
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    void track(PointerEvent update) {
      if (update is PointerUpEvent || update is PointerCancelEvent) {
        if (update is PointerUpEvent) _lastUp = update.timeStamp;
        final route = _routes.remove(update.pointer);
        if (route != null) {
          GestureBinding.instance.pointerRouter.removeRoute(
            update.pointer,
            route,
          );
        }
      }
    }

    _routes[event.pointer] = track;
    GestureBinding.instance.pointerRouter.addRoute(event.pointer, track);
    super.addAllowedPointer(event);
  }

  @override
  void dispose() {
    for (final entry in _routes.entries) {
      GestureBinding.instance.pointerRouter.removeRoute(entry.key, entry.value);
    }
    _routes.clear();
    super.dispose();
  }
}
