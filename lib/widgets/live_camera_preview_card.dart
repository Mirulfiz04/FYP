import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Live camera-preview card with face-detection corner brackets, a LIVE badge
/// and a "face not visible" overlay. Falls back to a placeholder when the
/// camera is loading or unavailable.
class LiveCameraPreviewCard extends StatelessWidget {
  final CameraController? controller;
  final bool loading;
  final bool faceVisible;
  final bool paused;

  const LiveCameraPreviewCard({
    super.key,
    required this.controller,
    required this.loading,
    required this.faceVisible,
    this.paused = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ready = c != null && c.value.isInitialized;
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize?.height ?? 480,
                  height: c.value.previewSize?.width ?? 640,
                  child: CameraPreview(c),
                ),
              )
            else
              Container(
                color: _accent.withValues(alpha: 0.08),
                child: Center(
                  child: loading
                      ? const CircularProgressIndicator(color: _accent)
                      : const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_off_outlined,
                                color: MedsColors.muted, size: 36),
                            SizedBox(height: 8),
                            Text('Camera unavailable',
                                style: TextStyle(
                                    color: MedsColors.muted, fontSize: 12.5)),
                          ],
                        ),
                ),
              ),
            if (ready) ..._corners(),
            if (ready && paused)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pause_circle_filled,
                          color: Colors.white, size: 44),
                      SizedBox(height: 6),
                      Text('Paused',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            // LIVE / PAUSED badge
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: paused ? const Color(0xFF5F5E5A) : _accent,
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(paused ? Icons.pause : Icons.circle,
                        color: Colors.white, size: paused ? 11 : 8),
                    const SizedBox(width: 5),
                    Text(paused ? 'PAUSED' : 'LIVE',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            ),
            if (ready && !faceVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: MedsColors.red.withValues(alpha: 0.85),
                  child: const Row(
                    children: [
                      Icon(Icons.face_retouching_off,
                          color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Face not clearly visible',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _corners() {
    const len = 22.0, th = 3.0;
    const white = Colors.white;
    BoxDecoration deco(bool top, bool left) => BoxDecoration(
          border: Border(
            top: top ? const BorderSide(color: white, width: th) : BorderSide.none,
            bottom:
                !top ? const BorderSide(color: white, width: th) : BorderSide.none,
            left:
                left ? const BorderSide(color: white, width: th) : BorderSide.none,
            right: !left
                ? const BorderSide(color: white, width: th)
                : BorderSide.none,
          ),
        );
    return [
      Positioned(top: 90, left: 40, child: Container(width: len, height: len, decoration: deco(true, true))),
      Positioned(top: 90, right: 40, child: Container(width: len, height: len, decoration: deco(true, false))),
      Positioned(bottom: 90, left: 40, child: Container(width: len, height: len, decoration: deco(false, true))),
      Positioned(bottom: 90, right: 40, child: Container(width: len, height: len, decoration: deco(false, false))),
    ];
  }
}
