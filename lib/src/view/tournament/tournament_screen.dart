import 'package:material_ui/material_ui.dart';

class TournamentScreen extends StatelessWidget {
  const TournamentScreen({super.key});

  static const String routeName = '/tournament';

  static Route<void> buildRoute(Object? tournamentId) {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const TournamentScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Offline')),
    );
  }
}
