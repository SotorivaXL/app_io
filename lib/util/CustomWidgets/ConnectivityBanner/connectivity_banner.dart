import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_io/util/services/connectivity_service.dart';
import 'package:lottie/lottie.dart'; // Add this line

class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({required this.child});

  @override
  _ConnectivityBannerState createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  late StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _hasConnection = true;

  // Add a flag to check if the dialog is currently showing
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    _subscription = ConnectivityService().connectivityStream.listen(
          (List<ConnectivityResult> results) {
        bool previousConnection = _hasConnection;
        _hasConnection = results.isNotEmpty &&
            results.any((result) => result != ConnectivityResult.none);

        // If the connection status has changed, update accordingly
        if (previousConnection != _hasConnection) {
          _updateConnectionStatus(_hasConnection);
        }
      },
    );
  }

  Future<void> _checkInitialConnection() async {
    List<ConnectivityResult> results =
    await ConnectivityService().checkConnectivity();
    _hasConnection = results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);

    // Show or hide the dialog based on initial connection status
    _updateConnectionStatus(_hasConnection);
  }

  void _updateConnectionStatus(bool hasConnection) {
    if (!hasConnection && !_isDialogShowing) {
      // Show the dialog
      _showNoInternetDialog();
    } else if (hasConnection && _isDialogShowing) {
      // Dismiss the dialog
      Navigator.of(context, rootNavigator: true).pop();
      _isDialogShowing = false;
    }
  }

  void _showNoInternetDialog() {
    _isDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Disable back button
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Sem conexão com a Internet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Display your animation here
                // For Lottie animation
                Lottie.asset(
                  'assets/animations/no_internet.json', // Update with your animation path
                  width: 150,
                  height: 150,
                  fit: BoxFit.contain,
                ),

                // If you have a GIF instead, you can use Image.asset
                // Image.asset(
                //   'assets/animations/no_internet.gif',
                //   width: 150,
                //   height: 150,
                //   fit: BoxFit.contain,
                // ),

                SizedBox(height: 20),
                Text(
                  'Por favor, verifique sua conexão com a internet e tente novamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    if (_isDialogShowing) {
      Navigator.of(context, rootNavigator: true).pop();
      _isDialogShowing = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No need to wrap with Stack anymore
    return widget.child;
  }
}