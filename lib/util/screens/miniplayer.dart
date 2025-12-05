import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:grradio/util/radio_handler_web.dart';

class MiniPlayer extends StatelessWidget {
  final RadioHandlerImpl handler;

  const MiniPlayer({Key? key, required this.handler}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MediaItem?>(
      valueListenable: handler.mediaItem,
      builder: (context, item, _) {
        if (item == null) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            leading: item.artUri != null
                ? Image.network(
                    item.artUri.toString(),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.radio, size: 40),
                  )
                : const Icon(Icons.radio, size: 40),
            title: Text(item.title),
            subtitle: Text(item.genre ?? ''),
            trailing: ValueListenableBuilder<bool>(
              valueListenable: handler.isPlaying,
              builder: (context, playing, _) {
                return IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (playing) {
                      handler.pause();
                    } else {
                      handler.resume();
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
