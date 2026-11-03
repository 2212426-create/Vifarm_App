import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import 'universal_share_bottom_sheet.dart';

/// Component Nút Chia Sẻ chuẩn hóa toàn app ViFarm
/// Đảm bảo diện tích chạm >= 48x48, phản hồi haptic & scale, semantics accessibility
class ShareButton extends StatefulWidget {
  final ShareContentModel? content;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double iconSize;
  final bool isVideoOverlay;

  const ShareButton({
    super.key,
    this.content,
    this.onTap,
    this.iconColor,
    this.iconSize = 24.0,
    this.isVideoOverlay = false,
  });

  @override
  State<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<ShareButton> {
  bool _isPressed = false;

  void _handleTap() {
    HapticFeedback.lightImpact();
    if (widget.content != null) {
      UniversalShareBottomSheet.show(context, widget.content!);
    } else if (widget.onTap != null) {
      widget.onTap!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.isVideoOverlay
        ? Colors.white
        : (widget.iconColor ?? AppColors.primary);

    return Semantics(
      label: 'Chia sẻ',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          _handleTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: widget.isVideoOverlay
                  ? Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(80),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.share_outlined,
                        color: effectiveColor,
                        size: widget.iconSize,
                      ),
                    )
                  : Icon(
                      Icons.share_outlined,
                      color: effectiveColor,
                      size: widget.iconSize,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
