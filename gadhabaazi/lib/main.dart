import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'blocs/game/game_bloc.dart';
import 'blocs/online/online_bloc.dart';
import 'engine/game_engine.dart';
import 'services/room_repository.dart';
import 'screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const GadhabaaziApp());
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
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
        scrollBehavior: const AppScrollBehavior(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          // If on wide screens (laptop, desktop, tablet), constrain to mobile phone width
          const double maxMobileWidth = 460.0;
          if (mediaQuery.size.width > maxMobileWidth) {
            final effectiveMediaQuery = mediaQuery.copyWith(
              size: Size(maxMobileWidth, mediaQuery.size.height),
            );

            return Scaffold(
              backgroundColor: const Color(0xFF070B12), // Sleek dark velvet backdrop
              body: Center(
                child: Container(
                  width: maxMobileWidth,
                  height: mediaQuery.size.height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1A14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: MediaQuery(
                    data: effectiveMediaQuery,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          }
          return child ?? const SizedBox.shrink();
        },
        home: const SplashScreen(),
      ),
    );
  }
}