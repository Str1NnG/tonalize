import 'key_profiles.dart';

class KeyScorer {
  KeyScorer({this.profiles = ProfileSet.krumhansl});

  final ProfileSet profiles;

  List<KeyCandidate> score(List<double> profile) {
    final major = profiles == ProfileSet.krumhansl ? kkMajor : temperleyMajor;
    final minor = profiles == ProfileSet.krumhansl ? kkMinor : temperleyMinor;
    final out = <KeyCandidate>[];
    for (var t = 0; t < 12; t++) {
      out.add(KeyCandidate(t, true, pearson(profile, rotated(major, t))));
      out.add(KeyCandidate(t, false, pearson(profile, rotated(minor, t))));
    }
    out.sort((a, b) => b.r.compareTo(a.r));
    return out;
  }
}
