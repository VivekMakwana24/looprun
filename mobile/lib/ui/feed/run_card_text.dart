import '../../data/models/social_models.dart';

/// "took 12 from Anna, 3 from Ben and 4 from hidden runners", or null when nothing was taken.
String? takenFromText(RunCard card) {
  final parts = <String>[
    for (final t in card.takenFrom) '${t.cells} from ${t.user.name.isEmpty ? 'a runner' : t.user.name}',
    if (card.takenFromHidden > 0) '${card.takenFromHidden} from hidden runners',
  ];
  if (parts.isEmpty) return null;
  if (parts.length == 1) return 'took ${parts.first}';
  return 'took ${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

/// "12 cells claimed" / "1 cell claimed" / "No cells claimed".
String claimedText(RunCard card) {
  final n = card.cellsClaimed;
  if (n <= 0) return 'No cells claimed';
  return n == 1 ? '1 cell claimed' : '$n cells claimed';
}

/// The status of a run that is not (yet) accepted, in words; null for accepted runs.
String? statusText(RunCard card) {
  switch (card.status) {
    case 'processing':
      return 'Processing';
    case 'pending_review':
      return 'In review';
    case 'rejected':
      return 'Not counted';
    default:
      return null;
  }
}
