import 'package:flutter/material.dart';
import 'package:grradio/main.dart';

class MiniPlayer extends StatelessWidget {
  final String title;
  final Stream<Duration> positionStream;
  final Stream<Duration?> durationStream;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onClose;
  final bool isPlaying;

  const MiniPlayer({
    Key? key,
    required this.title,
    required this.positionStream,
    required this.durationStream,
    required this.onPause,
    required this.onPlay,
    required this.onClose,
    required this.isPlaying,
  }) : super(key: key);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: onClose,
              ),
            ],
          ),
          StreamBuilder<Duration?>(
            stream: durationStream,
            builder: (context, snapshotDuration) {
              final duration = snapshotDuration.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: positionStream,
                builder: (context, snapshotPosition) {
                  final position = snapshotPosition.data ?? Duration.zero;
                  final progress = duration.inMilliseconds == 0
                      ? 0.0
                      : position.inMilliseconds / duration.inMilliseconds;

                  return Column(
                    children: [
                      Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: (value) {
                          final seekPos = Duration(
                            milliseconds: (duration.inMilliseconds * value)
                                .toInt(),
                          );
                          globalMp3QueueService.seek(seekPos);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: isPlaying ? onPause : onPlay,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
