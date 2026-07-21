import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'blocs/game/game_bloc.dart';
import 'engine/game_engine.dart';
import 'screens/home/home_screen.dart';

void main() {
  runApp(const GadhabaaziApp());
}

class GadhabaaziApp extends StatelessWidget {
  const GadhabaaziApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GameBloc(engine: GameEngine()),
      child: MaterialApp(
        title: 'Gadhabaazi',
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
