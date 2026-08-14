import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  final AudioPlayer _sfxPlayer = AudioPlayer();
  final AudioPlayer _bgmPlayer = AudioPlayer();
  final AudioPlayer _tapPlayer = AudioPlayer(); // Separate for quick tap sounds

  AudioService._internal() {
    _bgmPlayer.setReleaseMode(ReleaseMode.loop);
  }

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

  Future<void> playTapSound() async {
    try {
      await _tapPlayer.stop();
      await _tapPlayer.play(AssetSource('audio/play.wav'));
    } catch (_) {}
  }

  Future<void> playSplashBgm() async {
    try {
      await _bgmPlayer.play(AssetSource('audio/from_splash_till_start_only.mp3'));
    } catch (_) {}
  }

  Future<void> playEndingBgm() async {
    try {
      await _bgmPlayer.play(AssetSource('audio/ending_sound.mp3'));
    } catch (_) {}
  }

  Future<void> stopBgm() async {
    try {
      await _bgmPlayer.stop();
    } catch (_) {}
  }

  Future<void> _playSound(String path) async {
    try {
      if (_sfxPlayer.state == PlayerState.playing) {
        await _sfxPlayer.stop();
      }
      await _sfxPlayer.play(AssetSource(path));
    } catch (e) {
      // Ignore audio errors gracefully
    }
  }
}
