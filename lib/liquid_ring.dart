import 'package:aero_drop/app_colors.dart';
import 'package:flutter/material.dart';

class LiquidRing extends StatefulWidget {
  final double size;
  final int durationSeconds;
  final bool reverse;

  const LiquidRing({
    super.key,
    required this.size,
    required this.durationSeconds,
    required this.reverse,
  });

  @override
  State<LiquidRing> createState() => _LiquidRingState();
}

class _LiquidRingState extends State<LiquidRing>
    with SingleTickerProviderStateMixin {
  late AnimationController animationController;

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.durationSeconds),
    )..repeat();
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animationController,
      builder: (context, child) {
        var rotation = animationController.value * 2 * 3.14159;
        if (widget.reverse) rotation = -rotation;
        return Transform.rotate(
          angle: rotation,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(60),
                bottomLeft: Radius.circular(70),
                bottomRight: Radius.circular(30),
              ),
            ),
          ),
        );
      },
    );
  }
}
