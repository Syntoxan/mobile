import 'package:auto_size_text/auto_size_text.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/message/message_repository.dart';
import 'package:lichess_mobile/src/model/team/team_providers.dart';
import 'package:lichess_mobile/src/model/user/user.dart';
import 'package:lichess_mobile/src/network/connectivity.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/http_network_image.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/lichess_assets.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/account/profile_screen.dart';
import 'package:lichess_mobile/src/view/message/contacts_screen.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/view/team/team_updates_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/syn_mascot_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountMenuScreen extends ConsumerWidget {
  const AccountMenuScreen({super.key});

  static Route<void> buildRoute(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return buildScreenRoute(screen: const AccountMenuScreen());
    }

    return PageRouteBuilder<void>(
      pageBuilder: (_, a, b) => const AccountMenuScreen(),
      transitionsBuilder: (_, animation, b, child) {
        final tween = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(context.l10n.mobileAccount),
        automaticallyImplyLeading: isIOS,
        actions: [
          if (!isIOS)
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        ],
      ),
      body: ListView(
        children: [
          ListSection(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                trailing: isIOS ? const CupertinoListTileChevron() : null,
                title: Text(context.l10n.settingsSettings),
                onTap: () {
                  Navigator.of(context).push(SettingsScreen.buildRoute());
                },
              ),
            ],
          ),
          const SocketPingRatingListTile(),
        ],
      ),
    );
  }
}

class AccountMenuButton extends ConsumerStatefulWidget {
  const AccountMenuButton({super.key});

  @override
  ConsumerState<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState extends ConsumerState<AccountMenuButton> {
  static const _cupertinoButtonSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    void openMenu() {
      Navigator.of(context).push(AccountMenuScreen.buildRoute(context));
    }

    return IconButton(
      padding: isIOS ? EdgeInsets.zero : null,
      constraints: isIOS
          ? const BoxConstraints.tightFor(width: _cupertinoButtonSize, height: _cupertinoButtonSize)
          : null,
      icon: const SynMascotIcon(size: 28),
      tooltip: context.l10n.mobileAccount,
      onPressed: openMenu,
    );
  }
}
