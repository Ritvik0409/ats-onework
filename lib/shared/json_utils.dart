/// Small helpers for reading loosely-typed JSON.
///
/// The API returns lists of strings in a few places (a user's roles, the
/// capabilities they hold). They may be absent, null, or a list of
/// anything, so they are read defensively rather than cast.
library;

/// Reads a JSON value as a list of strings, ignoring anything else.
List<String> stringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).toList();
}

/// Reads a JSON value as a map, or an empty map for anything else.
Map<String, dynamic> jsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, v) => MapEntry(key.toString(), v));
  return <String, dynamic>{};
}
