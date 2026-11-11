/// The cost limit for one task, and the hard stop that follows it.
///
/// A task is one agent run in a conversation: the limit is read from the live
/// cost the server reports for that conversation (`session.usage.updated`).
/// When the run passes the limit, the phone stops it — the run ends there
/// and nothing further is spent until the person raises the limit or starts a
/// new task.
///
/// The limit is per server profile, in US dollars, and is stored on the
/// device only. Null (or zero) means "no limit".
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TaskCostLimit {
  const TaskCostLimit._();

  static String keyFor(String profileId) => 'oc.taskCostLimit.$profileId';

  /// The limit in US dollars for one task on this profile; null when there
  /// is none.
  static double? read(SharedPreferences preferences, String profileId) {
    if (profileId.isEmpty) return null;
    try {
      final raw = preferences.getString(keyFor(profileId));
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final limit = value['limitUsd'];
      if (limit is num && limit > 0) return limit.toDouble();
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Stores (or clears) the limit. A value of zero or less clears it.
  static Future<void> save(
    SharedPreferences preferences,
    String profileId,
    double? usd,
  ) async {
    if (profileId.isEmpty) return;
    try {
      if (usd == null || usd <= 0) {
        await preferences.remove(keyFor(profileId));
        return;
      }
      await preferences.setString(
        keyFor(profileId),
        jsonEncode({'version': 1, 'limitUsd': usd}),
      );
    } catch (_) {
      // A device that cannot store the limit keeps it in memory only.
    }
  }

  /// Whether a run that has reached [cost] dollars must stop.
  static bool exceeded(double? limitUsd, double? cost) {
    if (limitUsd == null || limitUsd <= 0 || cost == null) return false;
    return cost >= limitUsd;
  }
}
