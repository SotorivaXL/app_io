import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

class Providers {
  static List<SingleChildWidget> providers = [
    ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
    Provider<FirestoreService>(create: (_) => FirestoreService()),
  ];
}
