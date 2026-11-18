import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The three parts of the BOARD lane. The lane bar keeps its three numbered lanes (the sign-in track and
/// every mockup draw three); the social surfaces live inside lane 2.
enum BoardTab { ranking, feed, rivals }

class BoardTabViewModel extends Notifier<BoardTab> {
  @override
  BoardTab build() => BoardTab.ranking;

  void select(BoardTab tab) => state = tab;
}

final boardTabViewModelProvider = NotifierProvider<BoardTabViewModel, BoardTab>(BoardTabViewModel.new);
