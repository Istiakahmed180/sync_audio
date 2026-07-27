import 'package:flutter/material.dart';

/// Keeps content readable on wide windows while remaining full-width on
/// narrow screens. Decisions use the available app-window width.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    required this.child,
    this.maxWidth = 1180,
    this.mobilePadding = 16,
    this.widePadding = 24,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final double mobilePadding;
  final double widePadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth >= 700
          ? widePadding
          : mobilePadding;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: child,
          ),
        ),
      );
    },
  );
}
