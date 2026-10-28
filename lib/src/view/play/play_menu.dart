import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:lichess_mobile/src/view/over_the_board/over_the_board_screen.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:material_ui/material_ui.dart';

class const PlayMenu() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Section(
          children: [
            ListTile(
              onTap: () {
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).push(OfflineComputerGameScreen.buildRoute());
              },
              leading: const Icon(Icons.memory),
              title: Text(context.l10n.playAgainstComputer),
            ),
            ListTile(
              onTap: () {
                // Pops the play bottom sheet
                Navigator.of(context).popUntil((route) => route is! ModalBottomSheetRoute);
                Navigator.of(context, rootNavigator: true).push(OverTheBoardScreen.buildRoute());
              },
              leading: const Icon(Icons.table_restaurant_outlined),
              title: Text(context.l10n.mobileOverTheBoard),
            ),
          ],
        ),
      ],
    );
  }
}

class const _Section({required final List<Widget> children}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListSection(hasLeading: true, materialFilledCard: true, children: children);
  }
}
