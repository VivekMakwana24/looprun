import '../../data/models/models.dart';

/// Plain-language text for a server flag code.
String describeFlag(Flag f) {
  switch (f.code) {
    case 'mock_location':
      return 'Your phone reported a mock (fake) location. Runs with mock locations cannot earn cells.';
    case 'teleport':
      return 'The track jumped too far between two points, which is not possible on foot.';
    case 'vehicle_speed':
      return 'You moved at a speed that looks like a vehicle rather than running.';
    case 'implausible_loop':
      return 'One loop looked unusually large, so it is being checked.';
    case 'too_few_fixes':
      return 'We received very few GPS points, so the run is hard to judge.';
    case 'near_closure_repaired':
      return 'Your loop almost closed, so we joined the ends for you.';
    case 'loop_rejected_small':
      return 'A loop was too small to count.';
    case 'loop_rejected_large':
      return 'A loop was too large to count.';
    default:
      return f.detail.isNotEmpty ? f.detail : f.code;
  }
}
