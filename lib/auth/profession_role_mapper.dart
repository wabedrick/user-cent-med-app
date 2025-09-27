/// Maps a human-readable profession selection to an internal role.
/// Biomedical Engineer -> engineer
/// Doctor / Nurse / Clinical / Medic -> medic
/// Fallback -> user
String mapProfessionToRole(String? profession) {
  if (profession == null) return 'user';
  final p = profession.toLowerCase();
  if (p.contains('engineer')) return 'user'; // do not auto-elevate; require admin approval
  if (p.contains('doctor') || p.contains('nurse') || p.contains('medic') || p.contains('clinical')) return 'medic';
  return 'user';
}
