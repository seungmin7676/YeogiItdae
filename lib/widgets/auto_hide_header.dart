import 'package:flutter/material.dart';

/// Hides a screen's secondary header while scrolling down and restores it
/// after a short upward scroll.
class AutoHideHeader extends StatefulWidget {
  const AutoHideHeader({
    required this.header,
    required this.body,
    this.alwaysVisible = false,
    super.key,
  });

  final Widget header;
  final Widget body;
  final bool alwaysVisible;

  @override
  State<AutoHideHeader> createState() => _AutoHideHeaderState();
}

class _AutoHideHeaderState extends State<AutoHideHeader> {
  static const _hideAfter = 44.0;
  static const _showAfter = -28.0;

  double _scrollDistance = 0;
  bool _visible = true;

  @override
  void didUpdateWidget(covariant AutoHideHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alwaysVisible && !oldWidget.alwaysVisible) {
      _scrollDistance = 0;
      _visible = true;
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        widget.alwaysVisible) {
      _scrollDistance = 0;
      return false;
    }

    if (notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      _setVisible(true);
      return false;
    }

    if (notification is! ScrollUpdateNotification) return false;
    final delta = notification.scrollDelta;
    if (delta == null || delta == 0) return false;

    if ((_scrollDistance > 0 && delta < 0) ||
        (_scrollDistance < 0 && delta > 0)) {
      _scrollDistance = 0;
    }
    _scrollDistance += delta;

    if (_visible && _scrollDistance >= _hideAfter) {
      _setVisible(false);
    } else if (!_visible && _scrollDistance <= _showAfter) {
      _setVisible(true);
    }
    return false;
  }

  void _setVisible(bool visible) {
    _scrollDistance = 0;
    if (_visible == visible || !mounted) return;
    setState(() => _visible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible || widget.alwaysVisible;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: Column(
        children: [
          ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: visible ? 1 : 0,
                end: visible ? 1 : 0,
              ),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              builder: (context, progress, child) => Align(
                alignment: Alignment.topCenter,
                heightFactor: progress,
                child: Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, -12 * (1 - progress)),
                    child: child,
                  ),
                ),
              ),
              child: IgnorePointer(ignoring: !visible, child: widget.header),
            ),
          ),
          Expanded(child: widget.body),
        ],
      ),
    );
  }
}
