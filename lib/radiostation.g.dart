// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'radiostation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RadioStationAdapter extends TypeAdapter<RadioStation> {
  @override
  final int typeId = 0;

  @override
  RadioStation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RadioStation(
      id: fields[0] as String,
      name: fields[1] as String,
      streamUrl: fields[3] as String?,
      logoUrl: fields[2] as String?,
      language: fields[4] as String?,
      genre: fields[5] as String?,
      state: fields[6] as String?,
      page: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, RadioStation obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.logoUrl)
      ..writeByte(3)
      ..write(obj.streamUrl)
      ..writeByte(4)
      ..write(obj.language)
      ..writeByte(5)
      ..write(obj.genre)
      ..writeByte(6)
      ..write(obj.state)
      ..writeByte(7)
      ..write(obj.page);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadioStationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
