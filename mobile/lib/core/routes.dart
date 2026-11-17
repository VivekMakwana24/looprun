/// Route paths (go_router). Kept apart from router.dart so screens can name a path without importing
/// the router, which imports the screens.
const String splashPath = '/splash';
const String signInPath = '/sign-in';
const String disclosurePath = '/disclosure';

/// Lane 1: the map (home).
const String homePath = '/home';

/// Lane 2: the weekly board.
const String boardPath = '/board';

/// Lane 3: profile.
const String profilePath = '/you';

/// The live run screen. A child of the map route drawn full screen above the lanes, so `go` to it
/// (or from it to a result) keeps the map underneath for the back button.
const String recordPath = '/home/record';

/// Result of one run: `/home/run/<id>` (full screen above the map, like [recordPath]).
String runResultPath(String runId) => '/home/run/$runId';
