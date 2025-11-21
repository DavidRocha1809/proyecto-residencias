import 'package:flutter/foundation.dart';

class AppNotifier extends ChangeNotifier {
  static final AppNotifier instance = AppNotifier._();
  AppNotifier._();

  void notifyAttendanceChanged() {
    notifyListeners();
  }
}
