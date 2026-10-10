/// Adapted for Saber from Flutter's [InteractiveViewer] class
/// https://github.com/flutter/flutter/blob/stable/packages/flutter/lib/src/widgets/interactive_viewer.dart
/// Using this commit (Flutter 3.44.0):
/// https://github.com/flutter/flutter/blob/86b97230b17c2fd37cf9e615f1f32650e1541d75/packages/flutter/lib/src/widgets/interactive_viewer.dart
library;

// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in Flutter's LICENSE file.

// ignore_for_file: omit_obvious_property_types

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Quad, Vector3;

typedef InteractiveCanvasViewerWidgetBuilder = Widget Function(
  BuildContext context,
  Quad viewport,
);

@immutable
class InteractiveCanvasViewer extends StatefulWidget {
  /// Create an InteractiveCanvasViewer.
  new({
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.panAxis = PanAxis.free,
    this.boundaryMargin = .zero,
    this.constrained = true,
    // These default scale values were eyeballed as reasonable limits for common
    // use cases.
    this.maxScale = 2.5,
    this.minScale = 0.8,
    this.isDrawGesture,
    this.interactionEndFrictionCoefficient = kDrag,
    this.onInteractionEnd,
    this.onDrawEnd,
    this.onDrawStart,
    this.onDrawUpdate,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.scaleFactor = kDefaultMouseScrollToScaleFactor,
    this.transformationController,
    this.alignment,
    this.trackpadScrollCausesScale = false,
    this.pageWidth,
    required Widget this.child,
  }) : assert(minScale > 0),
       assert(interactionEndFrictionCoefficient > 0),
       assert(minScale.isFinite),
       assert(maxScale > 0),
       assert(!maxScale.isNaN),
       assert(maxScale >= minScale),
       // boundaryMargin must be either fully infinite or fully finite, but not
       // a mix of both.
       assert(
         (boundaryMargin.horizontal.isInfinite &&
                 boundaryMargin.vertical.isInfinite) ||
             (boundaryMargin.top.isFinite &&
                 boundaryMargin.right.isFinite &&
                 boundaryMargin.bottom.isFinite &&
                 boundaryMargin.left.isFinite),
       ),
       builder = null;

  /// Creates an InteractiveCanvasViewer for a child that is created on demand.
  ///
  /// Can be used to render a child that changes in response to the current
  /// transformation.
  ///
  /// See the [builder] attribute docs for an example of using it to optimize a
  /// large child.
  new builder({
    super.key,
    this.clipBehavior = Clip.hardEdge,
    this.panAxis = PanAxis.free,
    this.boundaryMargin = .zero,
    // These default scale values were eyeballed as reasonable limits for common
    // use cases.
    this.maxScale = 2.5,
    this.minScale = 0.8,
    this.isDrawGesture,
    this.interactionEndFrictionCoefficient = kDrag,
    this.onInteractionEnd,
    this.onDrawEnd,
    this.onDrawStart,
    this.onDrawUpdate,
    this.panEnabled = true,
    this.scaleEnabled = true,
    this.scaleFactor = 200.0,
    this.transformationController,
    this.alignment,
    this.trackpadScrollCausesScale = false,
    this.pageWidth,
    required InteractiveCanvasViewerWidgetBuilder this.builder,
  }) : assert(minScale > 0),
       assert(interactionEndFrictionCoefficient > 0),
       assert(minScale.isFinite),
       assert(maxScale > 0),
       assert(!maxScale.isNaN),
       assert(maxScale >= minScale),
       // boundaryMargin must be either fully infinite or fully finite, but not
       // a mix of both.
       assert(
         (boundaryMargin.horizontal.isInfinite &&
                 boundaryMargin.vertical.isInfinite) ||
             (boundaryMargin.top.isFinite &&
                 boundaryMargin.right.isFinite &&
                 boundaryMargin.bottom.isFinite &&
                 boundaryMargin.left.isFinite),
       ),
       constrained = false,
       child = null;

  /// Physical unscaled width of the page / document.
  final double? pageWidth;

  /// The alignment of the child's origin, relative to the size of the box.
  final Alignment? alignment;

  /// If set to [Clip.none], the child may extend beyond the size of the InteractiveCanvasViewer,
  /// but it will not receive gestures in these areas.
  /// Be sure that the InteractiveCanvasViewer is the desired size when using [Clip.none].
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// When set to [PanAxis.aligned], panning is only allowed in the horizontal
  /// axis or the vertical axis, diagonal panning is not allowed.
  ///
  /// When set to [PanAxis.vertical] or [PanAxis.horizontal] panning is only
  /// allowed in the specified axis. For example, if set to [PanAxis.vertical],
  /// panning will only be allowed in the vertical axis. And if set to [PanAxis.horizontal],
  /// panning will only be allowed in the horizontal axis.
  ///
  /// When set to [PanAxis.free] panning is allowed in all directions.
  ///
  /// Defaults to [PanAxis.free].
  final PanAxis panAxis;

  /// A margin for the visible boundaries of the child.
  ///
  /// Any transformation that results in the viewport being able to view outside
  /// of the boundaries will be stopped at the boundary. The boundaries do not
  /// rotate with the rest of the scene, so they are always aligned with the
  /// viewport.
  ///
  /// To produce no boundaries at all, pass infinite [EdgeInsets], such as
  /// `EdgeInsets.all(double.infinity)`.
  ///
  /// No edge can be NaN.
  ///
  /// Defaults to [EdgeInsets.zero], which results in boundaries that are the
  /// exact same size and position as the [child].
  final EdgeInsets boundaryMargin;

  /// Builds the child of this widget.
  ///
  /// Passed with the [InteractiveCanvasViewer.builder] constructor. Otherwise, the
  /// [child] parameter must be passed directly, and this is null.
  ///
  /// {@tool dartpad}
  /// This example shows how to use builder to create a [Table] whose cell
  /// contents are only built when they are visible. Built and remove cells are
  /// logged in the console for illustration.
  ///
  /// ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.builder.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///   * [ListView.builder], which follows a similar pattern.
  final InteractiveCanvasViewerWidgetBuilder? builder;

  /// The child [Widget] that is transformed by InteractiveCanvasViewer.
  ///
  /// If the [InteractiveCanvasViewer.builder] constructor is used, then this will be
  /// null, otherwise it is required.
  final Widget? child;

  /// Whether the normal size constraints at this point in the widget tree are
  /// applied to the child.
  ///
  /// If set to false, then the child will be given infinite constraints. This
  /// is often useful when a child should be bigger than the InteractiveCanvasViewer.
  ///
  /// For example, for a child which is bigger than the viewport but can be
  /// panned to reveal parts that were initially offscreen, [constrained] must
  /// be set to false to allow it to size itself properly. If [constrained] is
  /// true and the child can only size itself to the viewport, then areas
  /// initially outside of the viewport will not be able to receive user
  /// interaction events. If experiencing regions of the child that are not
  /// receptive to user gestures, make sure [constrained] is false and the child
  /// is sized properly.
  ///
  /// Defaults to true.
  ///
  /// {@tool dartpad}
  /// This example shows how to create a pannable table. Because the table is
  /// larger than the entire screen, setting [constrained] to false is necessary
  /// to allow it to be drawn to its full size. The parts of the table that
  /// exceed the screen size can then be panned into view.
  ///
  /// ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.constrained.0.dart **
  /// {@end-tool}
  final bool constrained;

  /// If false, the user will be prevented from panning.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///   * [scaleEnabled], which is similar but for scale.
  final bool panEnabled;

  /// If false, the user will be prevented from scaling.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///   * [panEnabled], which is similar but for panning.
  final bool scaleEnabled;

  /// {@macro flutter.gestures.scale.trackpadScrollCausesScale}
  final bool trackpadScrollCausesScale;

  /// Determines the amount of scale to be performed per pointer scroll.
  ///
  /// Defaults to [kDefaultMouseScrollToScaleFactor].
  ///
  /// Increasing this value above the default causes scaling to feel slower,
  /// while decreasing it causes scaling to feel faster.
  ///
  /// The amount of scale is calculated as the exponential function of the
  /// [PointerScrollEvent.scrollDelta] to [scaleFactor] ratio. In the Flutter
  /// engine, the mousewheel [PointerScrollEvent.scrollDelta] is hardcoded to 20
  /// per scroll, while a trackpad scroll can be any amount.
  ///
  /// Affects only pointer device scrolling, not pinch to zoom.
  final double scaleFactor;

  /// The maximum allowed scale.
  ///
  /// The scale will be clamped between this and [minScale] inclusively.
  ///
  /// Defaults to 2.5.
  ///
  /// Must be greater than zero and greater than [minScale].
  final double maxScale;

  /// The minimum allowed scale.
  ///
  /// The scale will be clamped between this and [maxScale] inclusively.
  ///
  /// Scale is also affected by [boundaryMargin]. If the scale would result in
  /// viewing beyond the boundary, then it will not be allowed. By default,
  /// boundaryMargin is .zero, so scaling below 1.0 will not be
  /// allowed in most cases without first increasing the boundaryMargin.
  ///
  /// Defaults to 0.8.
  ///
  /// Must be a finite number greater than zero and less than [maxScale].
  final double minScale;

  /// Changes the deceleration behavior after a gesture.
  ///
  /// Defaults to 0.0000135.
  ///
  /// Must be a finite number greater than zero.
  final double interactionEndFrictionCoefficient;

  /// Called when the user ends a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction,
  /// though a pan may cause an inertia animation after this is called as well.
  ///
  /// {@template flutter.widgets.InteractiveCanvasViewer.onInteractionEnd}
  /// Will be called even if the interaction is disabled with [panEnabled] or
  /// [scaleEnabled] for both touch gestures and mouse interactions.
  ///
  /// A [GestureDetector] wrapping the InteractiveCanvasViewer will not respond to
  /// [GestureDetector.onScaleStart], [GestureDetector.onScaleUpdate], and
  /// [GestureDetector.onScaleEnd]. Use [onDrawStart],
  /// [onDrawUpdate], and [onDrawEnd] to respond to those
  /// gestures.
  /// {@endtemplate}
  ///
  /// See also:
  ///
  ///  * [onDrawStart], which handles the start of the same interaction.
  ///  * [onDrawUpdate], which handles an update to the same interaction.
  final GestureScaleEndCallback? onDrawEnd;

  /// Called when the user begins a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will not have
  /// changed due to this interaction.
  ///
  /// {@macro flutter.widgets.InteractiveCanvasViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveCanvasViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onDrawUpdate], which handles an update to the same interaction.
  ///  * [onDrawEnd], which handles the end of the same interaction.
  final GestureScaleStartCallback? onDrawStart;

  /// Called when the user updates a pan or scale gesture on the widget.
  ///
  /// At the time this is called, the [TransformationController] will have
  /// already been updated to reflect the change caused by the interaction, if
  /// the interaction caused the matrix to change.
  ///
  /// {@macro flutter.widgets.InteractiveCanvasViewer.onInteractionEnd}
  ///
  /// The coordinates provided in the details' `focalPoint` and
  /// `localFocalPoint` are normal Flutter event coordinates, not
  /// InteractiveCanvasViewer scene coordinates. See
  /// [TransformationController.toScene] for how to convert these coordinates to
  /// scene coordinates relative to the child.
  ///
  /// See also:
  ///
  ///  * [onDrawStart], which handles the start of the same interaction.
  ///  * [onDrawEnd], which handles the end of the same interaction.
  final GestureScaleUpdateCallback? onDrawUpdate;

  /// A function to distinguish a draw gesture and a pan/zoom gesture.
  final bool Function(ScaleStartDetails scaleDetails)? isDrawGesture;

  /// Called when any gesture ends.
  final GestureScaleEndCallback? onInteractionEnd;

  /// A [TransformationController] for the transformation performed on the
  /// child.
  ///
  /// Whenever the child is transformed, the [Matrix4] value is updated and all
  /// listeners are notified. If the value is set, InteractiveCanvasViewer will update
  /// to respect the new value.
  ///
  /// {@tool dartpad}
  /// This example shows how transformationController can be used to animate the
  /// transformation back to its starting position.
  ///
  /// ** See code in examples/api/lib/widgets/interactive_viewer/interactive_viewer.transformation_controller.0.dart **
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * [ValueNotifier], the parent class of TransformationController.
  ///  * [TextEditingController] for an example of another similar pattern.
  final TransformationController? transformationController;

  // Used as the coefficient of friction in the inertial translation animation.
  // This value was eyeballed to give a feel similar to Google Photos.
  static const double kDrag = 0.0000135;

  /// Returns the closest point to the given point on the given line segment.
  @visibleForTesting
  static Vector3 getNearestPointOnLine(Vector3 point, Vector3 l1, Vector3 l2) {
    final double lengthSquared =
        math.pow(l2.x - l1.x, 2.0).toDouble() +
        math.pow(l2.y - l1.y, 2.0).toDouble();

    // In this case, l1 == l2.
    if (lengthSquared == 0) {
      return l1;
    }

    // Calculate how far down the line segment the closest point is and return
    // the point.
    final Vector3 l1P = point - l1;
    final Vector3 l1L2 = l2 - l1;
    final double fraction = clampDouble(l1P.dot(l1L2) / lengthSquared, 0, 1);
    return l1 + l1L2 * fraction;
  }

  /// Given a quad, return its axis aligned bounding box.
  @visibleForTesting
  static Quad getAxisAlignedBoundingBox(Quad quad) {
    final double minX = math.min(
      quad.point0.x,
      math.min(quad.point1.x, math.min(quad.point2.x, quad.point3.x)),
    );
    final double minY = math.min(
      quad.point0.y,
      math.min(quad.point1.y, math.min(quad.point2.y, quad.point3.y)),
    );
    final double maxX = math.max(
      quad.point0.x,
      math.max(quad.point1.x, math.max(quad.point2.x, quad.point3.x)),
    );
    final double maxY = math.max(
      quad.point0.y,
      math.max(quad.point1.y, math.max(quad.point2.y, quad.point3.y)),
    );
    return Quad.points(
      Vector3(minX, minY, 0),
      Vector3(maxX, minY, 0),
      Vector3(maxX, maxY, 0),
      Vector3(minX, maxY, 0),
    );
  }

  /// Returns true iff the point is inside the rectangle given by the Quad,
  /// inclusively.
  /// Algorithm from https://math.stackexchange.com/a/190373.
  @visibleForTesting
  static bool pointIsInside(Vector3 point, Quad quad) {
    final Vector3 aM = point - quad.point0;
    final Vector3 aB = quad.point1 - quad.point0;
    final Vector3 aD = quad.point3 - quad.point0;

    final double aMAB = aM.dot(aB);
    final double aBAB = aB.dot(aB);
    final double aMAD = aM.dot(aD);
    final double aDAD = aD.dot(aD);

    return 0 <= aMAB && aMAB <= aBAB && 0 <= aMAD && aMAD <= aDAD;
  }

  /// Get the point inside (inclusively) the given Quad that is nearest to the
  /// given Vector3.
  @visibleForTesting
  static Vector3 getNearestPointInside(Vector3 point, Quad quad) {
    // If the point is inside the axis aligned bounding box, then it's ok where
    // it is.
    if (pointIsInside(point, quad)) {
      return point;
    }

    // Otherwise, return the nearest point on the quad.
    final List<Vector3> closestPoints = <Vector3>[
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point0,
        quad.point1,
      ),
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point1,
        quad.point2,
      ),
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point2,
        quad.point3,
      ),
      InteractiveCanvasViewer.getNearestPointOnLine(
        point,
        quad.point3,
        quad.point0,
      ),
    ];
    double minDistance = double.infinity;
    late Vector3 closestOverall;
    for (final Vector3 closePoint in closestPoints) {
      final double distance = math.sqrt(
        math.pow(point.x - closePoint.x, 2) +
            math.pow(point.y - closePoint.y, 2),
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestOverall = closePoint;
      }
    }
    return closestOverall;
  }

  @override
  State<InteractiveCanvasViewer> createState() =>
      _InteractiveCanvasViewerState();
}

class _InteractiveCanvasViewerState extends State<InteractiveCanvasViewer>
    with TickerProviderStateMixin {
  late TransformationController _transformer =
      widget.transformationController ?? TransformationController();

  final GlobalKey _childKey = GlobalKey();
  final GlobalKey _parentKey = GlobalKey();
  Animation<Offset>? _animation;
  Animation<double>? _scaleAnimation;
  late Offset _scaleAnimationFocalPoint;
  late AnimationController _controller;
  late AnimationController _scaleController;

  Offset _previousFocalPoint = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  double _previousScale = 1.0;
  Offset _previousTranslation = Offset.zero;
  double? _scaleStart;
  bool _isClearlyVertical = false;

  final Map<int, PointerDeviceKind> _activePointers = <int, PointerDeviceKind>{};

  bool get _isStylusActive => _activePointers.values.any(
        (kind) =>
            kind == PointerDeviceKind.stylus ||
            kind == PointerDeviceKind.invertedStylus,
      );

  bool isCurrentGestureADrawGesture = false;

  // The Rect representing the child's parent.
  Rect get _viewport {
    assert(_parentKey.currentContext != null);
    final RenderBox parentRenderBox =
        _parentKey.currentContext!.findRenderObject()! as RenderBox;
    return Offset.zero & parentRenderBox.size;
  }

  Size get _childSize {
    if (_childKey.currentContext != null) {
      final RenderBox? childRenderBox =
          _childKey.currentContext!.findRenderObject() as RenderBox?;
      return childRenderBox?.size ?? Size.zero;
    }
    return Size.zero;
  }

  double get _effectivePageWidth {
    final Size childSize = _childSize;
    return widget.pageWidth ??
        (childSize.width > 0 ? childSize.width : _viewport.width);
  }

  double get _totalContentHeight {
    final Size childSize = _childSize;
    return childSize.height > 0 ? childSize.height : _viewport.height;
  }

  static Matrix4 _buildMatrix({
    required double scale,
    required double translationX,
    required double translationY,
  }) {
    return Matrix4.identity()
      ..translateByDouble(translationX, translationY, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// Calculates the new [Matrix4] transformation separating strictly the behavior
  /// of the X-axis and Y-axis.
  Matrix4 _computeTransform({
    required double newScale,
    required double focusX,
    required double focusY,
    required double previousScale,
    required Offset previousTranslation,
    required double deltaX,
    required double deltaY,
    bool allowPanX = true,
  }) {
    final double viewportWidth = _viewport.width;
    final double viewportHeight = _viewport.height;
    final double scaledWidth = _effectivePageWidth * newScale;
    final double scaledHeight = _totalContentHeight * newScale;

    // 2. Eje X (Comportamiento horizontal exacto estilo Noteshelf):
    final double targetX;
    if (scaledWidth <= viewportWidth) {
      // a) Si scaledWidth <= viewportWidth (La hoja cabe en la pantalla):
      //    - La posición horizontal DEBE ser una función directa del ancho escalado:
      //      translationX = (viewportWidth - scaledWidth) / 2
      //    - Ignora cualquier delta o desplazamiento horizontal proveniente de los dedos.
      //      Al hacer zoom, la hoja DEBE expandirse de forma 100% simétrica hacia ambos lados manteniéndose centrada.
      targetX = (viewportWidth - scaledWidth) / 2;
    } else {
      // b) Si scaledWidth > viewportWidth (La hoja supera el ancho de la pantalla):
      //    - Permite desplazamiento horizontal siguiendo el gesto de dos dedos (pinch/pan).
      //    - Aplica topes rígidos (clamping) inmediatos para que nunca se vea espacio vacío a los lados:
      //      minX = viewportWidth - scaledWidth
      //      maxX = 0
      //      translationX = clamp(translationX, minX, maxX)
      final double unconstrainedX = allowPanX
          ? focusX -
              (focusX - previousTranslation.dx) * (newScale / previousScale) +
              deltaX
          : previousTranslation.dx;
      final double minX = viewportWidth - scaledWidth;
      const double maxX = 0.0;
      targetX = clampDouble(unconstrainedX, minX, maxX);
    }

    // 3. Eje Y (Comportamiento vertical):
    //    - Al hacer zoom con dos dedos, escala tomando como pivote el punto vertical medio de los dedos (focusY):
    //      translationY = focusY - (focusY - previousTranslationY) * (newScale / previousScale) + deltaY
    //    - Permite el scroll vertical normal a lo largo del documento.
    final double unconstrainedY = focusY -
        (focusY - previousTranslation.dy) * (newScale / previousScale) +
        deltaY;
    final double minY = math.min(0.0, viewportHeight - scaledHeight);
    const double maxY = 0.0;
    final double targetY = clampDouble(unconstrainedY, minY, maxY);

    return _buildMatrix(
      scale: newScale,
      translationX: targetX,
      translationY: targetY,
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_controller.isAnimating) {
      _controller.stop();
      _controller.reset();
      _animation?.removeListener(_handleInertiaAnimation);
      _animation = null;
    }
    if (_scaleController.isAnimating) {
      _scaleController.stop();
      _scaleController.reset();
      _scaleAnimation?.removeListener(_handleScaleAnimation);
      _scaleAnimation = null;
    }

    _scaleStart = _transformer.value.getMaxScaleOnAxis();
    _gestureStartFocalPoint = details.localFocalPoint;
    _previousFocalPoint = details.localFocalPoint;
    _previousScale = _scaleStart!;
    _previousTranslation = _getMatrixTranslation(_transformer.value);
    _isClearlyVertical = false;

    // 4. Detección de stylus y palma (Palm Rejection):
    // Cualquier evento de puntero clasificado como STYLUS debe usarse exclusivamente
    // para dibujar trazos, anulando cualquier cálculo de paneo o zoom del lienzo.
    final bool isStylus = _isStylusActive;
    final bool isDraw =
        isStylus || (widget.isDrawGesture?.call(details) ?? false);

    if (isDraw) {
      isCurrentGestureADrawGesture = true;
      widget.onDrawStart?.call(details);
      return;
    }

    isCurrentGestureADrawGesture = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // 4. Detección de stylus y palma (Palm Rejection):
    // Si hay un stylus activo o es un gesto de dibujo, anula cualquier cálculo de paneo o zoom del lienzo.
    if (isCurrentGestureADrawGesture || _isStylusActive) {
      widget.onDrawUpdate?.call(details);
      return;
    }

    final double currentScale = _transformer.value.getMaxScaleOnAxis();
    final Offset currentTranslation = _getMatrixTranslation(_transformer.value);

    // 4. El desplazamiento del lienzo debe requerir 2 dedos (two-finger drag)
    // o, si es con un solo dedo, solo responder a movimientos claramente verticales.
    if (details.pointerCount == 1) {
      if (!widget.panEnabled) {
        _previousFocalPoint = details.localFocalPoint;
        return;
      }

      final double totalDx =
          (details.localFocalPoint.dx - _gestureStartFocalPoint.dx).abs();
      final double totalDy =
          (details.localFocalPoint.dy - _gestureStartFocalPoint.dy).abs();

      if (!_isClearlyVertical) {
        if (totalDy > totalDx * 1.5 && totalDy > 8.0) {
          _isClearlyVertical = true;
        }
      }

      if (!_isClearlyVertical) {
        _previousFocalPoint = details.localFocalPoint;
        return;
      }

      final double deltaY = details.localFocalPoint.dy - _previousFocalPoint.dy;

      _transformer.value = _computeTransform(
        newScale: currentScale,
        focusX: details.localFocalPoint.dx,
        focusY: details.localFocalPoint.dy,
        previousScale: currentScale,
        previousTranslation: currentTranslation,
        deltaX: 0.0,
        deltaY: deltaY,
        allowPanX: false,
      );

      _previousFocalPoint = details.localFocalPoint;
      _previousScale = currentScale;
      _previousTranslation = _getMatrixTranslation(_transformer.value);
      return;
    }

    // Dos o más dedos (two-finger drag / pinch):
    final double desiredScale = _scaleStart != null
        ? _scaleStart! * details.scale
        : currentScale * details.scale;
    final double newScale = widget.scaleEnabled
        ? clampDouble(desiredScale, widget.minScale, widget.maxScale)
        : currentScale;

    final double focusX = details.localFocalPoint.dx;
    final double focusY = details.localFocalPoint.dy;
    final double deltaX = focusX - _previousFocalPoint.dx;
    final double deltaY = focusY - _previousFocalPoint.dy;

    _transformer.value = _computeTransform(
      newScale: newScale,
      focusX: focusX,
      focusY: focusY,
      previousScale: _previousScale > 0 ? _previousScale : currentScale,
      previousTranslation: _previousTranslation,
      deltaX: deltaX,
      deltaY: deltaY,
      allowPanX: true,
    );

    _previousFocalPoint = details.localFocalPoint;
    _previousScale = newScale;
    _previousTranslation = _getMatrixTranslation(_transformer.value);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    widget.onInteractionEnd?.call(details);

    if (isCurrentGestureADrawGesture) {
      isCurrentGestureADrawGesture = false;
      widget.onDrawEnd?.call(details);
      return;
    }

    _scaleStart = null;
    _animation?.removeListener(_handleInertiaAnimation);
    _scaleAnimation?.removeListener(_handleScaleAnimation);
    _controller.reset();
    _scaleController.reset();

    final double velocityDist = details.velocity.pixelsPerSecond.distance;
    if (velocityDist >= kMinFlingVelocity && widget.panEnabled) {
      final double currentScale = _transformer.value.getMaxScaleOnAxis();
      final Offset translation = _getMatrixTranslation(_transformer.value);

      final double viewportWidth = _viewport.width;
      final double viewportHeight = _viewport.height;
      final double scaledWidth = _effectivePageWidth * currentScale;
      final double scaledHeight = _totalContentHeight * currentScale;

      final bool canPanX = scaledWidth > viewportWidth;
      final double velocityX =
          canPanX ? details.velocity.pixelsPerSecond.dx : 0.0;
      final double velocityY = details.velocity.pixelsPerSecond.dy;

      final FrictionSimulation frictionSimulationX = FrictionSimulation(
        widget.interactionEndFrictionCoefficient,
        translation.dx,
        velocityX,
      );
      final FrictionSimulation frictionSimulationY = FrictionSimulation(
        widget.interactionEndFrictionCoefficient,
        translation.dy,
        velocityY,
      );

      final double effectiveVelocity =
          canPanX ? velocityDist : velocityY.abs();
      final double tFinal = _getFinalTime(
        effectiveVelocity,
        widget.interactionEndFrictionCoefficient,
      );

      final double finalX;
      if (!canPanX) {
        finalX = (viewportWidth - scaledWidth) / 2;
      } else {
        final double minX = viewportWidth - scaledWidth;
        finalX = clampDouble(frictionSimulationX.finalX, minX, 0.0);
      }

      final double minY = math.min(0.0, viewportHeight - scaledHeight);
      final double finalY = clampDouble(frictionSimulationY.finalX, minY, 0.0);

      _animation = Tween<Offset>(
        begin: translation,
        end: Offset(finalX, finalY),
      ).chain(CurveTween(curve: Curves.decelerate)).animate(_controller);
      _controller.duration = Duration(milliseconds: (tFinal * 1000).round());
      _animation!.addListener(_handleInertiaAnimation);
      _controller.forward();
    } else if (details.scaleVelocity.abs() >= 0.1 && widget.scaleEnabled) {
      final double scale = _transformer.value.getMaxScaleOnAxis();
      final FrictionSimulation frictionSimulation = FrictionSimulation(
        widget.interactionEndFrictionCoefficient * widget.scaleFactor,
        scale,
        details.scaleVelocity / 10,
      );
      final double tFinal = _getFinalTime(
        details.scaleVelocity.abs(),
        widget.interactionEndFrictionCoefficient,
        effectivelyMotionless: 0.1,
      );
      _scaleAnimationFocalPoint = _previousFocalPoint;
      _scaleAnimation = Tween<double>(
        begin: scale,
        end: clampDouble(
          frictionSimulation.x(tFinal),
          widget.minScale,
          widget.maxScale,
        ),
      ).chain(CurveTween(curve: Curves.decelerate)).animate(_scaleController);
      _scaleController.duration =
          Duration(milliseconds: (tFinal * 1000).round());
      _scaleAnimation!.addListener(_handleScaleAnimation);
      _scaleController.forward();
    }
  }

  void _receivedPointerSignal(PointerSignalEvent event) {
    final Offset local = event.localPosition;
    final double currentScale = _transformer.value.getMaxScaleOnAxis();
    final Offset currentTranslation = _getMatrixTranslation(_transformer.value);

    if (event is PointerScrollEvent) {
      if (!HardwareKeyboard.instance.isControlPressed &&
          !HardwareKeyboard.instance.isMetaPressed) {
        if (!widget.panEnabled) return;
        _transformer.value = _computeTransform(
          newScale: currentScale,
          focusX: local.dx,
          focusY: local.dy,
          previousScale: currentScale,
          previousTranslation: currentTranslation,
          deltaX: -event.scrollDelta.dx,
          deltaY: -event.scrollDelta.dy,
          allowPanX: true,
        );
        return;
      }
      if (event.scrollDelta.dy == 0.0) return;
      if (!widget.scaleEnabled) return;
      final double scaleChange =
          math.exp(-event.scrollDelta.dy / widget.scaleFactor);
      final double newScale = clampDouble(
        currentScale * scaleChange,
        widget.minScale,
        widget.maxScale,
      );
      _transformer.value = _computeTransform(
        newScale: newScale,
        focusX: local.dx,
        focusY: local.dy,
        previousScale: currentScale,
        previousTranslation: currentTranslation,
        deltaX: 0.0,
        deltaY: 0.0,
        allowPanX: true,
      );
    } else if (event is PointerScaleEvent) {
      if (!widget.scaleEnabled) return;
      final double newScale = clampDouble(
        currentScale * event.scale,
        widget.minScale,
        widget.maxScale,
      );
      _transformer.value = _computeTransform(
        newScale: newScale,
        focusX: local.dx,
        focusY: local.dy,
        previousScale: currentScale,
        previousTranslation: currentTranslation,
        deltaX: 0.0,
        deltaY: 0.0,
        allowPanX: true,
      );
    }
  }

  void _handleInertiaAnimation() {
    if (!_controller.isAnimating) {
      _animation?.removeListener(_handleInertiaAnimation);
      _animation = null;
      _controller.reset();
      return;
    }
    final double currentScale = _transformer.value.getMaxScaleOnAxis();
    _transformer.value = _buildMatrix(
      scale: currentScale,
      translationX: _animation!.value.dx,
      translationY: _animation!.value.dy,
    );
  }

  void _handleScaleAnimation() {
    if (!_scaleController.isAnimating) {
      _scaleAnimation?.removeListener(_handleScaleAnimation);
      _scaleAnimation = null;
      _scaleController.reset();
      return;
    }
    final double desiredScale = _scaleAnimation!.value;
    final double currentScale = _transformer.value.getMaxScaleOnAxis();
    final Offset currentTranslation = _getMatrixTranslation(_transformer.value);
    _transformer.value = _computeTransform(
      newScale: desiredScale,
      focusX: _scaleAnimationFocalPoint.dx,
      focusY: _scaleAnimationFocalPoint.dy,
      previousScale: currentScale,
      previousTranslation: currentTranslation,
      deltaX: 0.0,
      deltaY: 0.0,
      allowPanX: true,
    );
  }

  void _handleTransformation() {
    // A change to the TransformationController's value is a change to the
    // state.
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _scaleController = AnimationController(vsync: this);

    _transformer.addListener(_handleTransformation);
  }

  @override
  void didUpdateWidget(InteractiveCanvasViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final TransformationController? newController =
        widget.transformationController;
    if (newController == oldWidget.transformationController) {
      return;
    }
    _transformer.removeListener(_handleTransformation);
    if (oldWidget.transformationController == null) {
      _transformer.dispose();
    }
    _transformer = newController ?? TransformationController();
    _transformer.addListener(_handleTransformation);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scaleController.dispose();
    _transformer.removeListener(_handleTransformation);
    if (widget.transformationController == null) {
      _transformer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (widget.child != null) {
      child = _InteractiveCanvasViewerBuilt(
        childKey: _childKey,
        clipBehavior: widget.clipBehavior,
        constrained: widget.constrained,
        matrix: _transformer.value,
        alignment: widget.alignment,
        child: widget.child!,
      );
    } else {
      // When using InteractiveCanvasViewer.builder, then constrained is false and the
      // viewport is the size of the constraints.
      assert(widget.builder != null);
      assert(!widget.constrained);
      child = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Matrix4 matrix = _transformer.value;
          return _InteractiveCanvasViewerBuilt(
            childKey: _childKey,
            clipBehavior: widget.clipBehavior,
            constrained: widget.constrained,
            alignment: widget.alignment,
            matrix: matrix,
            child: widget.builder!(
              context,
              _transformViewport(matrix, Offset.zero & constraints.biggest),
            ),
          );
        },
      );
    }

    return Listener(
      key: _parentKey,
      onPointerDown: (PointerDownEvent event) {
        _activePointers[event.pointer] = event.kind;
      },
      onPointerMove: (PointerMoveEvent event) {
        _activePointers[event.pointer] = event.kind;
      },
      onPointerUp: (PointerUpEvent event) {
        _activePointers.remove(event.pointer);
      },
      onPointerCancel: (PointerCancelEvent event) {
        _activePointers.remove(event.pointer);
      },
      onPointerSignal: _receivedPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // Necessary when panning off screen.
        onScaleEnd: _onScaleEnd,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        trackpadScrollCausesScale: widget.trackpadScrollCausesScale,
        trackpadScrollToScaleFactor: Offset(0, -1 / widget.scaleFactor),
        child: child,
      ),
    );
  }
}

// This widget allows us to easily swap in and out the LayoutBuilder in
// InteractiveCanvasViewer's depending on if it's using a builder or a child.
class _InteractiveCanvasViewerBuilt extends StatelessWidget {
  const new({
    required this.child,
    required this.childKey,
    required this.clipBehavior,
    required this.constrained,
    required this.matrix,
    required this.alignment,
  });

  final Widget child;
  final GlobalKey childKey;
  final Clip clipBehavior;
  final bool constrained;
  final Matrix4 matrix;
  final Alignment? alignment;

  @override
  Widget build(BuildContext context) {
    Widget child = Transform(
      transform: matrix,
      alignment: alignment,
      child: KeyedSubtree(key: childKey, child: this.child),
    );

    if (!constrained) {
      child = OverflowBox(
        alignment: .topLeft,
        minWidth: 0,
        minHeight: 0,
        // maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: child,
      );
    }

    return ClipRect(clipBehavior: clipBehavior, child: child);
  }
}

// A classification of relevant user gestures. Each contiguous user gesture is
// represented by exactly one _GestureType.
enum _GestureType { pan, scale, rotate }

// Given a velocity and drag, calculate the time at which motion will come to
// a stop, within the margin of effectivelyMotionless.
double _getFinalTime(
  double velocity,
  double drag, {
  double effectivelyMotionless = 10,
}) {
  return math.log(effectivelyMotionless / velocity) / math.log(drag / 100);
}

// Return the translation from the given Matrix4 as an .
Offset _getMatrixTranslation(Matrix4 matrix) {
  final Vector3 nextTranslation = matrix.getTranslation();
  return Offset(nextTranslation.x, nextTranslation.y);
}

// Transform the four corners of the viewport by the inverse of the given
// matrix. This gives the viewport after the child has been transformed by the
// given matrix. The viewport transforms as the inverse of the child (i.e.
// moving the child left is equivalent to moving the viewport right).
Quad _transformViewport(Matrix4 matrix, Rect viewport) {
  final Matrix4 inverseMatrix = matrix.clone()..invert();
  return Quad.points(
    inverseMatrix.transform3(
      Vector3(viewport.topLeft.dx, viewport.topLeft.dy, 0),
    ),
    inverseMatrix.transform3(
      Vector3(viewport.topRight.dx, viewport.topRight.dy, 0),
    ),
    inverseMatrix.transform3(
      Vector3(viewport.bottomRight.dx, viewport.bottomRight.dy, 0),
    ),
    inverseMatrix.transform3(
      Vector3(viewport.bottomLeft.dx, viewport.bottomLeft.dy, 0),
    ),
  );
}

// Find the axis aligned bounding box for the rect rotated about its center by
// the given amount.
Quad _getAxisAlignedBoundingBoxWithRotation(Rect rect, double rotation) {
  final Matrix4 rotationMatrix = Matrix4.identity()
    ..translateByDouble(rect.size.width / 2, rect.size.height / 2, 0, 1)
    ..rotateZ(rotation)
    ..translateByDouble(-rect.size.width / 2, -rect.size.height / 2, 0, 1);
  final Quad boundariesRotated = Quad.points(
    rotationMatrix.transform3(Vector3(rect.left, rect.top, 0)),
    rotationMatrix.transform3(Vector3(rect.right, rect.top, 0)),
    rotationMatrix.transform3(Vector3(rect.right, rect.bottom, 0)),
    rotationMatrix.transform3(Vector3(rect.left, rect.bottom, 0)),
  );
  return InteractiveCanvasViewer.getAxisAlignedBoundingBox(boundariesRotated);
}

// Return the amount that viewport lies outside of boundary. If the viewport
// is completely contained within the boundary (inclusively), then returns
// .zero.
Offset _exceedsBy(Quad boundary, Quad viewport) {
  final List<Vector3> viewportPoints = <Vector3>[
    viewport.point0,
    viewport.point1,
    viewport.point2,
    viewport.point3,
  ];
  Offset largestExcess = .zero;
  for (final Vector3 point in viewportPoints) {
    final Vector3 pointInside = InteractiveCanvasViewer.getNearestPointInside(
      point,
      boundary,
    );
    final Offset excess = Offset(
      pointInside.x - point.x,
      pointInside.y - point.y,
    );
    if (excess.dx.abs() > largestExcess.dx.abs()) {
      largestExcess = Offset(excess.dx, largestExcess.dy);
    }
    if (excess.dy.abs() > largestExcess.dy.abs()) {
      largestExcess = Offset(largestExcess.dx, excess.dy);
    }
  }

  return _round(largestExcess);
}

// Round the output values. This works around a precision problem where
// values that should have been zero were given as within 10^-10 of zero.
Offset _round(Offset offset) {
  return Offset(
    double.parse(offset.dx.toStringAsFixed(9)),
    double.parse(offset.dy.toStringAsFixed(9)),
  );
}

// Align the given offset to the given axis by allowing movement only in the
// axis direction.
Offset _alignAxis(Offset offset, Axis axis) {
  return switch (axis) {
    Axis.horizontal => Offset(offset.dx, 0),
    Axis.vertical => Offset(0, offset.dy),
  };
}

// Given two points, return the axis where the distance between the points is
// greatest. If they are equal, return null.
Axis? _getPanAxis(Offset point1, Offset point2) {
  if (point1 == point2) {
    return null;
  }
  final double x = point2.dx - point1.dx;
  final double y = point2.dy - point1.dy;
  return x.abs() > y.abs() ? Axis.horizontal : Axis.vertical;
}
