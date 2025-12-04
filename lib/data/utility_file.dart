class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class PositionState {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionState({
    required this.position,
    required this.bufferedPosition,
    required this.duration,
  });
}
