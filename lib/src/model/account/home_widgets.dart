import 'package:lichess_mobile/l10n/l10n.dart';

/// Enum representing the editable widgets on the home screen.
enum HomeEditableWidget(
  /// True if the widget should always be enabled and cannot be disabled.
  final bool alwaysEnabled,
) {
  /// No longer shown (the greeting is in the app bar): kept so that stored preferences listing it
  /// as disabled can still be read.
  hello(false),
  perfCards(false),
  friends(false),
  ongoingGames(true),
  quickPairing(false);
  String label(AppLocalizations l10n) => switch (this) {
    // not shown in the UI, so no need to localize
    HomeEditableWidget.ongoingGames => 'Ongoing Games',
    HomeEditableWidget.hello => l10n.mobileHello,
    // not shown in the UI, so no need to localize
    HomeEditableWidget.perfCards => 'Performance Cards',
    HomeEditableWidget.friends => l10n.friends,
    HomeEditableWidget.quickPairing => l10n.quickPairing,
    
  };
}
