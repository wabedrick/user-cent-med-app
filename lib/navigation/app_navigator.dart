import 'package:flutter/material.dart';

/// Global navigator key to allow services (e.g., messaging) to navigate
/// in response to background notification taps.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
