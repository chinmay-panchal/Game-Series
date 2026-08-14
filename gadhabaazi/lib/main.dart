import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'blocs/game/game_bloc.dart';
import 'blocs/online/online_bloc.dart';
import 'engine/game_engine.dart';
import 'services/room_repository.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const GadhabaaziApp());
}

class GadhabaaziApp extends StatelessWidget {
  const GadhabaaziApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => GameBloc(engine: GameEngine())),
        BlocProvider(create: (_) => OnlineBloc(repository: RoomRepository())),
      ],
      child: MaterialApp(
        title: 'Gadhabaazi',
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      ),
    );
  }
}
