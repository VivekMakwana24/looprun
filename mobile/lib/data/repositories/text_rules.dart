/// Client-side copies of the server's text rules (docs/PHASE1_SPEC.md 1 and 4), so a bad input is refused
/// before a request. The server stays the judge; these only save a round trip.

/// Control characters (C0, DEL, C1) and zero-width / invisible formatting characters.
bool hasForbiddenCharacter(String text) {
  for (final r in text.runes) {
    if (r < 0x20 || (r >= 0x7f && r <= 0x9f)) return true;
    if ((r >= 0x200b && r <= 0x200f) || (r >= 0x2028 && r <= 0x202e) || (r >= 0x2060 && r <= 0x2064) || r == 0xfeff) {
      return true;
    }
  }
  return false;
}

/// Trims and collapses inner whitespace, like the server does for display names.
String normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Unicode code points, as the server counts them.
int codePointLength(String text) => text.runes.length;

const int minNameLength = 2;
const int maxNameLength = 30;
const int maxCommentLength = 500;
const int maxReasonLength = 500;
