/*
 * This file is part of PiliPlus
 *
 * PiliPlus is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * PiliPlus is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with PiliPlus.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flutter/gestures.dart'
    show LongPressGestureRecognizer, HorizontalDragGestureRecognizer;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:get/get.dart';

import '../../score_image_save_menu.dart';
import '../../../utils/platform_utils.dart';
import '../num_ext.dart';
import 'colored_box_transition.dart';
import 'gesture/image_double_tap_gesture_recognizer.dart';
import 'gesture/image_horizontal_drag_gesture_recognizer.dart';
import 'gesture/image_tap_gesture_recognizer.dart';
import 'image.dart';
import 'loading_indicator.dart';

///
/// created by dom on 2026/02/14
///

class GalleryViewer extends StatefulWidget {
  const GalleryViewer({
    super.key,
    this.minScale = 1.0,
    this.maxScale = 8.0,
    required this.images,
    required this.imageAt,
    required this.title,
    this.whiteBackground = false,
    this.initIndex = 0,
    this.onPageChanged,
  });

  final double minScale;
  final double maxScale;
  final List<ImageProvider> images;
  final Future<Uint8List> Function(int index) imageAt;
  final String title;
  final bool whiteBackground;
  final int initIndex;
  final ValueChanged<int>? onPageChanged;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer>
    with SingleTickerProviderStateMixin {
  late Size _containerSize;
  late final RxInt _currIndex;
  EdgeInsets? _padding;

  RawGestureDetectorState? _pagingDetector;

  late final PageController _pageController;

  late final ImageTapGestureRecognizer _tapGestureRecognizer;
  late final ImageDoubleTapGestureRecognizer _doubleTapGestureRecognizer;
  late final ImageHorizontalDragGestureRecognizer
  _horizontalDragGestureRecognizer;
  ImageHorizontalDragGestureRecognizer horizontalDragGestureRecognizer() {
    return _horizontalDragGestureRecognizer;
  }

  late final LongPressGestureRecognizer _longPressGestureRecognizer;

  late final AnimationController _animateController;
  late final Animation<Color?> _opacityAnimation;
  double dx = 0, dy = 0;

  Offset _offset = Offset.zero;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _currIndex = widget.initIndex.obs;
    _pageController = PageController(initialPage: widget.initIndex);

    final gestureSettings = MediaQuery.maybeGestureSettingsOf(Get.context!);
    _tapGestureRecognizer = ImageTapGestureRecognizer()
      // ..onTap = _onTap
      ..gestureSettings = gestureSettings;
    if (PlatformUtils.isDesktop) {
      _tapGestureRecognizer.onSecondaryTapUp = _showDesktopMenu;
    }
    _doubleTapGestureRecognizer = ImageDoubleTapGestureRecognizer()
      ..onDoubleTap = () {}
      ..gestureSettings = gestureSettings;
    _horizontalDragGestureRecognizer = ImageHorizontalDragGestureRecognizer();
    _longPressGestureRecognizer = LongPressGestureRecognizer()
      ..onLongPress = _onLongPress
      ..gestureSettings = gestureSettings;

    Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _tapGestureRecognizer.onTap = _onTap;
      }
    });

    _animateController = AnimationController(
      duration: const Duration(
        milliseconds: 750,
      ), // reverse only if value <= 0.2
      vsync: this,
    );

    _opacityAnimation = _animateController.drive(
      ColorTween(begin: Colors.black, end: Colors.transparent),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding ??= MediaQuery.viewPaddingOf(context);
  }

  Matrix4 _onTransform(double val) {
    final scale = val.lerp(1.0, 0.25);

    // Matrix4.identity()
    //   ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
    //   ..translateByDouble(size.width * val * dx, size.height * val * dy, 0, 1)
    //   ..scaleByDouble(scale, scale, scale, 1)
    //   ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);

    final tmp = (1.0 - scale) / 2.0;
    return Matrix4.diagonal3Values(scale, scale, scale)..setTranslationRaw(
      _containerSize.width * (val * dx + tmp),
      _containerSize.height * (val * dy + tmp),
      0,
    );
  }

  void _updateMoveAnimation() {
    dy = _offset.dy.sign;
    if (dy == 0) {
      dx = 0;
    } else {
      dx = _offset.dx / _offset.dy.abs();
    }
  }

  void _onDragStart(ScaleStartDetails details) {
    _dragging = true;

    if (_animateController.isAnimating) {
      _animateController.stop();
    } else {
      _offset = Offset.zero;
      _animateController.value = 0.0;
    }
    _updateMoveAnimation();
  }

  void _onDragUpdate(ScaleUpdateDetails details) {
    if (!_dragging || _animateController.isAnimating) {
      return;
    }

    _offset += details.focalPointDelta;
    _updateMoveAnimation();

    if (!_animateController.isAnimating) {
      _animateController.value = _offset.dy.abs() / _containerSize.height;
    }
  }

  void _onDragEnd(ScaleEndDetails details) {
    if (!_dragging || _animateController.isAnimating) {
      return;
    }

    _dragging = false;

    if (!_animateController.isDismissed) {
      if (_animateController.value > 0.2) {
        Get.back();
      } else {
        _animateController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animateController.dispose();
    _tapGestureRecognizer.dispose();
    _doubleTapGestureRecognizer
      ..onDoubleTapDown = null
      ..onDoubleTap = null
      ..dispose();
    _longPressGestureRecognizer.dispose();
    Timer(const Duration(milliseconds: 200), _currIndex.close);
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _tapGestureRecognizer.addPointer(event);
    _doubleTapGestureRecognizer.addPointer(event);
    _longPressGestureRecognizer.addPointer(event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: .opaque,
      onPointerDown: _onPointerDown,
      child: Stack(
        fit: .expand,
        alignment: .center,
        clipBehavior: .none,
        children: [
          ColoredBoxTransition(color: _opacityAnimation),
          LayoutBuilder(
            builder: (context, constraints) {
              _containerSize = constraints.biggest;
              return MatrixTransition(
                alignment: .topLeft,
                animation: _animateController,
                onTransform: _onTransform,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: _GalleryScrollPhysics(),
                  ),
                  itemCount: widget.images.length,
                  itemBuilder: _itemBuilder,
                ),
              );
            },
          ),
          _buildIndicator,
        ],
      ),
    );
  }

  Widget get _buildIndicator => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: Container(
        padding: _padding! + const EdgeInsets.fromLTRB(12, 8, 20, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
          ),
        ),
        alignment: Alignment.center,
        child: Obx(
          () => Text(
            "${_currIndex.value + 1}/${widget.images.length}",
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );

  void _onPageChanged(int index) {
    _currIndex.value = index;
    widget.onPageChanged?.call(index);
  }

  late final ValueChanged<int>? _onChangePage = widget.images.length == 1
      ? null
      : (int offset) {
          final currPage = _pageController.page?.round() ?? 0;
          final nextPage = (currPage + offset).clamp(
            0,
            widget.images.length - 1,
          );
          if (nextPage != currPage) {
            _pageController.animateToPage(
              nextPage,
              duration: const Duration(milliseconds: 200),
              curve: Curves.ease,
            );
          }
        };

  // The reference SDK exposes a recognizer factory on PageView. The stock
  // SDK provides the same Scrollable callbacks through its public gesture
  // factory; connect the copied recognizer during viewport layout only.
  // Paging, dragging and ballistic scrolling remain owned by Flutter.
  void _bindPageGesture(BuildContext context) {
    final detector = context.findAncestorStateOfType<RawGestureDetectorState>();
    if (detector == null || identical(detector, _pagingDetector)) return;
    final factories = Map<Type, GestureRecognizerFactory>.of(
      detector.widget.gestures,
    );
    final factory = factories[HorizontalDragGestureRecognizer];
    if (factory is! GestureRecognizerFactory<HorizontalDragGestureRecognizer>) {
      return;
    }
    detector.replaceGestureRecognizers(
      {...factories}..remove(HorizontalDragGestureRecognizer),
    );
    detector.replaceGestureRecognizers({
      ...factories,
      HorizontalDragGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
            () => _horizontalDragGestureRecognizer,
            factory.initializer,
          ),
    });
    _pagingDetector = detector;
  }

  Widget _itemBuilder(BuildContext context, int index) => LayoutBuilder(
    builder: (context, constraints) {
      _bindPageGesture(context);
      return Image(
        image: widget.images[index],
        minScale: widget.minScale,
        maxScale: widget.maxScale,
        containerSize: _containerSize,
        color: widget.whiteBackground ? Colors.white : null,
        colorBlendMode: widget.whiteBackground ? BlendMode.dstOver : null,
        doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
        horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
        onChangePage: _onChangePage,
        loadingBuilder: loadingBuilder,
        errorBuilder: (context, error, stack) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white),
        ),
        onDragStart: _onDragStart,
        onDragUpdate: _onDragUpdate,
        onDragEnd: _onDragEnd,
      );
    },
  );

  static const Duration _kTapDiff = Duration(milliseconds: 300);

  void _onTap() {
    if (_tapGestureRecognizer.timeStamp -
            _doubleTapGestureRecognizer.timeStamp <
        _kTapDiff) {
      return;
    }
    Get.back();
  }

  void _onLongPress() {
    HapticFeedback.mediumImpact();
    showScoreImageSaveMenu(
      context,
      title: widget.title,
      index: _currIndex.value,
      count: widget.images.length,
      imageAt: widget.imageAt,
    );
  }

  void _showDesktopMenu(TapUpDetails details) => _onLongPress();

  Widget loadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? loadingProgress,
  ) {
    return Stack(
      fit: .expand,
      alignment: .center,
      clipBehavior: .none,
      children: [
        child,
        if (loadingProgress != null &&
            loadingProgress.expectedTotalBytes != null &&
            loadingProgress.cumulativeBytesLoaded !=
                loadingProgress.expectedTotalBytes)
          Center(
            child: LoadingIndicator(
              size: 39.4,
              progress:
                  loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!,
            ),
          ),
      ],
    );
  }
}

// Original tabBarScrollPhysics with its default spring preference.
class _GalleryScrollPhysics extends ClampingScrollPhysics {
  const _GalleryScrollPhysics({super.parent});
  @override
  _GalleryScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _GalleryScrollPhysics(parent: buildParent(ancestor));
  @override
  SpringDescription get spring => const SpringDescription(
    mass: 1.0,
    stiffness: 438.64908449286037,
    damping: 41.88790204786391,
  );
}
