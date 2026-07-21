import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_event.dart';
import '../../widgets/animated_background.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game/game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _savedGameJson;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSavedGame();
  }

  Future<void> _checkSavedGame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('saved_game');
      setState(() {
        _savedGameJson = saved;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: Center(
          child: _isLoading 
            ? const CircularProgressIndicator(color: AppColors.goldAccent)
            : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppStrings.appTitle,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: AppColors.goldAccent,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 4),
                  ]
                ),
              ),
              const SizedBox(height: 60),
              
              if (_savedGameJson != null) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    context.read<GameBloc>().add(LoadGame(jsonState: _savedGameJson!));
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const GameScreen())
                    );
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Resume Game"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    // Start fresh game, overriding old save
                    context.read<GameBloc>().add(const StartGame(playerNames: ['Player 1', 'Player 2']));
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const GameScreen())
                    );
                  },
                  child: const Text("Start New Game", style: TextStyle(color: Colors.white70)),
                ),
              ] else ...[
                ElevatedButton(
                  onPressed: () {
                    context.read<GameBloc>().add(const StartGame(playerNames: ['Player 1', 'Player 2']));
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const GameScreen())
                    );
                  },
                  child: const Text(AppStrings.newGame),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
