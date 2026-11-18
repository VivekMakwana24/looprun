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

// ---- Phase 1a (social + battles). All of them are drawn full screen above the lanes (root navigator).

/// The notifications inbox, opened from the bell on the map.
const String inboxPath = '/home/inbox';

/// Find runners by name (opened from the BOARD lane).
const String searchPath = '/board/search';

/// People the caller traded cells with recently.
const String rivalsListPath = '/board/rivals';

/// A run from the feed with its comments. The card can be passed as `extra` to show it at once.
String boardRunPath(String runId) => '/board/run/$runId';

/// A runner's public profile.
String userProfilePath(String userId) => '/board/user/$userId';

/// The caller's own run history, and the people lists, opened from the YOU lane.
const String historyPath = '/you/history';
const String followersPath = '/you/followers';
const String followingPath = '/you/following';
const String blockedPath = '/you/blocked';
