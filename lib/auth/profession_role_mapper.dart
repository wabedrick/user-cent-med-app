/// Maps a human-readable profession selection to an internal role.
/// Biomedical Engineer -> engineer
/// Doctor / Nurse / Clinical / Medic -> medic
/// Fallback -> engineer
String mapProfessionToRole(String? profession) {
  if (profession == null) return 'engineer';
  final p = profession.toLowerCase();
  if (p.contains('engineer')) return 'engineer';
  if (p.contains('doctor') || p.contains('nurse') || p.contains('medic') || p.contains('clinical')) return 'medic';
  return 'engineer';
}
