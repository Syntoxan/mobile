import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';

/// A provider for [MoveFeedbackService].
final moveFeedbackServiceProvider = Provider<MoveFeedbackService>((Ref ref) {
  final soundService = ref.watch(soundServiceProvider);
  return MoveFeedbackService(soundService, ref);
}, name: 'MoveFeedbackServiceProvider');

class MoveFeedbackService(final SoundService _soundService, final Ref _ref) {
  void moveFeedback({bool check = false}) {
    _soundService.play(Sound.move);

    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      if (check) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  void playedMove(String san, {Variant variant = Variant.standard, bool opponent = false}) {
    final check = san.contains('+') || san.contains('#');
    final capture = san.contains('x');
    if (capture && variant == Variant.atomic) {
      captureFeedback(variant, check: check);
      return;
    }
    if (check) {
      _soundService.play(Sound.check);
    } else if (san.contains('=')) {
      _soundService.play(Sound.promote);
    } else if (san.startsWith('O-O')) {
      _soundService.play(Sound.castle);
    } else if (capture) {
      captureFeedback(variant);
      return;
    } else if (opponent) {
      _soundService.play(Sound.moveOpponent);
    } else {
      _soundService.play(Sound.move);
    }
    _hapticFeedback(check);
  }

  void _hapticFeedback(bool check) {
    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      if (check) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  void captureFeedback(Variant variant, {bool check = false}) {
    _soundService.playCaptureSound(variant);

    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      if (check) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }
}
