import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  final AudioPlayer _player = AudioPlayer();

  AudioService._internal();

  Future<void> playCardSound() async {
    await _playSound('audio/play.wav');
  }

  Future<void> playTurnSwitchSound() async {
    await _playSound('audio/turn.wav');
  }

  Future<void> playPunishSound() async {
    await _playSound('audio/punish.wav');
  }

  Future<void> playErrorSound() async {
    await _playSound('audio/error.wav');
  }

  Future<void> _playSound(String path) async {
    try {
      if (_player.state == PlayerState.playing) {
        await _player.stop();
      }
      await _player.play(AssetSource(path));
    } catch (e) {
      // Ignore audio errors gracefully
    }
  }
}
