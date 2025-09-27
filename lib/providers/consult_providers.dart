import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/consult_repository.dart';
import '../models/consult_request_model.dart';

final consultRepositoryProvider = Provider<ConsultRepository>((ref) => ConsultRepository());

final userConsultsProvider = StreamProvider.autoDispose<List<ConsultRequest>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  final repo = ref.watch(consultRepositoryProvider);
  return repo.userConsults(uid);
});

// For engineers - you may later filter based on role
final openConsultsProvider = StreamProvider.autoDispose<List<ConsultRequest>>((ref) {
  final engineerId = FirebaseAuth.instance.currentUser?.uid;
  if (engineerId == null) return const Stream.empty();
  final repo = ref.watch(consultRepositoryProvider);
  return repo.openConsults(engineerId);
});
