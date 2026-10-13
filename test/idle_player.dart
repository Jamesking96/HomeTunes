// A player with nothing playing, for widget tests of screens that show Play buttons (album covers,
// album and playlist pages). Since 0.1.82 those ask the player what's playing, so a test that
// draws them needs one, as the app always has.
import 'package:flutter/foundation.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:provider/provider.dart';

class IdlePlayer extends ChangeNotifier implements PlayerModel {
  @override
  Track? get current => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// For a test's provider list.
ChangeNotifierProvider<PlayerModel> idlePlayerProvider() => ChangeNotifierProvider<PlayerModel>.value(value: IdlePlayer());
