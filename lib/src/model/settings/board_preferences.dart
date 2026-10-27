import 'package:chessground/chessground.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:lichess_mobile/l10n/l10n.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/color_palette.dart';
import 'package:material_ui/material_ui.dart';

part 'board_preferences.freezed.dart';
part 'board_preferences.g.dart';

const kBoardDefaultBrightnessFilter = 1.0;
const kBoardDefaultHueFilter = 0.0;

final boardPreferencesProvider = NotifierProvider<BoardPreferences, BoardPrefs>(
  BoardPreferences.new,
  name: 'BoardPreferencesProvider',
);

class BoardPreferences() extends Notifier<BoardPrefs> with PreferencesStorage<BoardPrefs> {
  @override
  @protected
  PrefCategory get prefCategory => PrefCategory.board;

  @override
  @protected
  BoardPrefs get defaults => BoardPrefs.defaults;

  @override
  BoardPrefs fromJson(Map<String, dynamic> json) => BoardPrefs.fromJson(json);

  @override
  BoardPrefs build() {
    return fetch();
  }

  Future<void> setPieceSet(PieceSet pieceSet) {
    return save(state.copyWith(pieceSet: pieceSet));
  }

  Future<void> setBoardTheme(BoardTheme boardTheme) async {
    await save(state.copyWith(boardTheme: boardTheme));
  }

  Future<void> togglePremoves() async {
    await save(state.copyWith(premoves: !state.premoves));
  }

  Future<void> toggleConfirmResignAndDraw() async {
    await save(state.copyWith(confirmResignAndDraw: !state.confirmResignAndDraw));
  }

  Future<void> setPieceShiftMethod(PieceShiftMethod pieceShiftMethod) async {
    await save(state.copyWith(pieceShiftMethod: pieceShiftMethod));
  }

  Future<void> toggleMoveOnRelease() async {
    await save(state.copyWith(moveOnRelease: !state.moveOnRelease));
  }

  Future<void> setCastlingMethod(CastlingMethod castlingMethod) {
    return save(state.copyWith(castlingMethod: castlingMethod));
  }

  Future<void> toggleHapticFeedback() {
    return save(state.copyWith(hapticFeedback: !state.hapticFeedback));
  }

  Future<void> toggleImmersiveModeWhilePlaying() {
    return save(
      state.copyWith(immersiveModeWhilePlaying: !(state.immersiveModeWhilePlaying ?? false)),
    );
  }

  Future<void> toggleShowLegalMoves() {
    return save(state.copyWith(showLegalMoves: !state.showLegalMoves));
  }

  Future<void> toggleBoardHighlights() {
    return save(state.copyWith(boardHighlights: !state.boardHighlights));
  }

  Future<void> toggleCoordinates() {
    return save(state.copyWith(coordinates: !state.coordinates));
  }

  Future<void> toggleBorder() {
    return save(state.copyWith(showBorder: !state.showBorder));
  }

  Future<void> togglePieceAnimation() {
    return save(state.copyWith(pieceAnimation: !state.pieceAnimation));
  }

  Future<void> toggleMagnifyDraggedPiece() {
    return save(state.copyWith(magnifyDraggedPiece: !state.magnifyDraggedPiece));
  }

  Future<void> setDragTargetKind(DragTargetKind dragTargetKind) {
    return save(state.copyWith(dragTargetKind: dragTargetKind));
  }

  Future<void> setMaterialDifferenceFormat(MaterialDifferenceFormat materialDifferenceFormat) {
    return save(state.copyWith(materialDifferenceFormat: materialDifferenceFormat));
  }

  Future<void> setClockPosition(ClockPosition clockPosition) {
    return save(state.copyWith(clockPosition: clockPosition));
  }

  Future<void> setLandscapeBoardPosition(LandscapeBoardPosition landscapeBoardPosition) {
    return save(state.copyWith(landscapeBoardPosition: landscapeBoardPosition));
  }

  Future<void> toggleMoveListDisplay() {
    return save(state.copyWith(moveListDisplay: !state.moveListDisplay));
  }

  Future<void> toggleEnableShapeDrawings() {
    return save(state.copyWith(enableShapeDrawings: !state.enableShapeDrawings));
  }

  Future<void> setShapeColor(ShapeColor shapeColor) {
    return save(state.copyWith(shapeColor: shapeColor));
  }

  Future<void> adjustColors({double? brightness, double? hue}) {
    return save(state.copyWith(brightness: brightness ?? state.brightness, hue: hue ?? state.hue));
  }
}

@Freezed(fromJson: true, toJson: true)
sealed class const BoardPrefs._() with _$BoardPrefs implements Serializable {
  @Assert('brightness >= 0.2 && brightness <= 1.4, hue >= 0.0 && hue <= 360.0')
  const factory({
    @JsonKey(defaultValue: PieceSet.cburnett, unknownEnumValue: PieceSet.cburnett)
    required PieceSet pieceSet,
    @JsonKey(defaultValue: BoardTheme.green, unknownEnumValue: BoardTheme.green)
    required BoardTheme boardTheme,
    bool? immersiveModeWhilePlaying,
    required bool hapticFeedback,
    required bool showLegalMoves,
    required bool boardHighlights,
    required bool coordinates,
    required bool pieceAnimation,
    @JsonKey(
      defaultValue: MaterialDifferenceFormat.materialDifference,
      unknownEnumValue: MaterialDifferenceFormat.materialDifference,
    )
    required MaterialDifferenceFormat materialDifferenceFormat,
    @JsonKey(defaultValue: ClockPosition.right, unknownEnumValue: ClockPosition.right)
    required ClockPosition clockPosition,
    @JsonKey(
      defaultValue: LandscapeBoardPosition.left,
      unknownEnumValue: LandscapeBoardPosition.left,
    )
    required LandscapeBoardPosition landscapeBoardPosition,
    @JsonKey(defaultValue: PieceShiftMethod.either, unknownEnumValue: PieceShiftMethod.either)
    required PieceShiftMethod pieceShiftMethod,
    @JsonKey(defaultValue: false) required bool moveOnRelease,
    @JsonKey(
      defaultValue: CastlingMethod.kingOverRook,
      unknownEnumValue: CastlingMethod.kingOverRook,
    )
    required CastlingMethod castlingMethod,
    @JsonKey(defaultValue: true) required bool moveListDisplay,
    @JsonKey(defaultValue: true) required bool premoves,
    @JsonKey(defaultValue: true) required bool confirmResignAndDraw,

    /// Whether to enable shape drawings on the board for games and puzzles.
    @JsonKey(defaultValue: true) required bool enableShapeDrawings,
    @JsonKey(defaultValue: true) required bool magnifyDraggedPiece,
    @JsonKey(defaultValue: DragTargetKind.circle, unknownEnumValue: DragTargetKind.circle)
    required DragTargetKind dragTargetKind,
    @JsonKey(defaultValue: ShapeColor.green, unknownEnumValue: ShapeColor.green)
    required ShapeColor shapeColor,
    @JsonKey(defaultValue: false) required bool showBorder,
    @JsonKey(defaultValue: kBoardDefaultBrightnessFilter) required double brightness,
    @JsonKey(defaultValue: kBoardDefaultHueFilter) required double hue,
  }) = _BoardPrefs;

  static const defaults = BoardPrefs(
    pieceSet: PieceSet.cburnett,
    boardTheme: BoardTheme.green,
    immersiveModeWhilePlaying: false,
    hapticFeedback: true,
    showLegalMoves: true,
    boardHighlights: true,
    coordinates: true,
    pieceAnimation: true,
    materialDifferenceFormat: MaterialDifferenceFormat.materialDifference,
    clockPosition: ClockPosition.right,
    landscapeBoardPosition: LandscapeBoardPosition.left,
    moveListDisplay: true,
    premoves: true,
    confirmResignAndDraw: true,
    pieceShiftMethod: PieceShiftMethod.either,
    moveOnRelease: false,
    castlingMethod: CastlingMethod.kingOverRook,
    enableShapeDrawings: true,
    magnifyDraggedPiece: true,
    dragTargetKind: DragTargetKind.circle,
    shapeColor: ShapeColor.green,
    showBorder: false,
    brightness: kBoardDefaultBrightnessFilter,
    hue: kBoardDefaultHueFilter,
  );

  bool get hasColorAdjustments =>
      brightness != kBoardDefaultBrightnessFilter || hue != kBoardDefaultHueFilter;

  ChessboardSettings toBoardSettings(Variant variant) {
    return ChessboardSettings(
      pieceAssets: pieceSet.assets,
      colorScheme: boardTheme.colors,
      brightness: brightness,
      hue: hue,
      border: showBorder
          ? BoardBorder(color: darken(boardTheme.colors.darkSquare, 0.2), width: 16.0)
          : null,
      showValidMoves: showLegalMoves,
      showLastMove: boardHighlights,
      enableCoordinates: coordinates,
      animationDuration: pieceAnimationDuration,
      dragFeedbackScale: magnifyDraggedPiece ? 2.0 : 1.0,
      dragFeedbackOffset: Offset(0.0, magnifyDraggedPiece ? -1.0 : 0.0),
      dragTargetKind: dragTargetKind,
      pieceShiftMethod: pieceShiftMethod,
      moveOnRelease: moveOnRelease,
      drawShape: DrawShapeOptions(enable: enableShapeDrawings, newShapeColor: shapeColor.color),
      enableDrops: variant == Variant.crazyhouse,
      canPromoteToKing: variant == Variant.antichess,
    );
  }

  factory fromJson(Map<String, dynamic> json) {
    return _$BoardPrefsFromJson(json);
  }

  Duration get pieceAnimationDuration =>
      pieceAnimation ? const Duration(milliseconds: 150) : Duration.zero;
}

/// Colors taken from lila: https://github.com/lichess-org/chessground/blob/54a7e71bf88701c1109d3b9b8106b464012b94cf/src/state.ts#L178
enum ShapeColor() {
  green,
  red,
  blue,
  yellow;

  Color get color => Color(switch (this) {
    ShapeColor.green => 0x15781B,
    ShapeColor.red => 0x882020,
    ShapeColor.blue => 0x003088,
    ShapeColor.yellow => 0xe68f00,
  }).withAlpha(0xAA);
}

/// The chessboard theme.
enum BoardTheme(final String label, final String gifApiName, final Color light, final Color dark) {
  green('Green', 'green', Color(0xffffffdd), Color(0xff86a666)),
  pink('Pink', 'pink', Color(0xfff4f0f0), Color(0xffec93a6)),
  midnight('Midnight', 'blue', Color(0xff9aa5b8), Color(0xff3e4a63)),
  classic('Classic', 'brown', Color(0xfff0d9b6), Color(0xffb58863)),
  lavender('Lavender', 'purple', Color(0xffffffff), Color(0xff8e7cc3));

  static final _cache = <BoardTheme, ChessboardColorScheme>{};

  ChessboardColorScheme get colors => this == BoardTheme.green
      ? ChessboardColorScheme.green
      : _cache.putIfAbsent(this, () => ChessboardColorScheme.solid(light: light, dark: dark));

  Widget get thumbnail => SizedBox(
    height: 44,
    width: 44 * 6,
    child: Row(
      children: [
        for (final c in const [1, 2, 3, 4, 5, 6])
          Container(width: 44, color: c.isEven ? colors.darkSquare : colors.lightSquare),
      ],
    ),
  );
}

enum MaterialDifferenceFormat() {
  materialDifference,
  capturedPieces,
  hidden;

  bool get visible => this != MaterialDifferenceFormat.hidden;

  String l10n(AppLocalizations l10n) => switch (this) {
    MaterialDifferenceFormat.materialDifference => l10n.preferencesMaterialDifference,
    MaterialDifferenceFormat.capturedPieces => l10n.mobileSettingsMaterialDifferenceCapturedPieces,
    MaterialDifferenceFormat.hidden => l10n.puzzleHidden, // should be good to reuse this
  };
}

enum ClockPosition() {
  left,
  right;

  String label(AppLocalizations l10n) => switch (this) {
    ClockPosition.left => l10n.mobilePositionLeft,
    ClockPosition.right => l10n.mobilePositionRight,
  };
}

enum LandscapeBoardPosition() {
  left,
  right;

  String label(AppLocalizations l10n) => switch (this) {
    LandscapeBoardPosition.left => l10n.mobilePositionLeft,
    LandscapeBoardPosition.right => l10n.mobilePositionRight,
  };
}

enum CastlingMethod() {
  /// Allow castling by moving either the king over the rook or two squares (to match lichess website).
  kingOverRook,

  /// Allow castling only by moving the king two squares.
  kingTwoSquares;

  String l10n(AppLocalizations l10n) => switch (this) {
    CastlingMethod.kingOverRook => l10n.preferencesCastleByMovingOntoTheRook,
    CastlingMethod.kingTwoSquares => l10n.preferencesCastleByMovingTwoSquares,
  };
}

String dragTargetKindLabel(AppLocalizations l10n, DragTargetKind kind) => switch (kind) {
  DragTargetKind.circle => l10n.mobileSettingsDraggedTargetCircle,
  DragTargetKind.square => l10n.mobileSettingsDraggedTargetSquare,
  DragTargetKind.none => l10n.none,
};
