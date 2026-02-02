import 'package:flutter/material.dart';

/// A utility class that provides a standardized confirmation dialog.
///
/// This class offers a static method to display an alert dialog with
/// customizable title, message, and action buttons for confirming or
/// canceling an action. The implementation follows Material 3 design guidelines.
class ConfirmationDialog {
  /// Shows a confirmation dialog with customizable content and actions.
  ///
  /// Parameters:
  /// - [context]: The build context for showing the dialog
  /// - [title]: The title displayed at the top of the dialog
  /// - [message]: The main content message of the dialog
  /// - [label]: The text for the confirm button
  /// - [onPressed]: Callback function executed when confirm is pressed
  /// - [cancelLabel]: Optional text for the cancel button (defaults to 'Cancel')
  /// - [confirmColor]: Optional color for the confirm button
  ///
  /// Returns a [Future<bool>] that completes with:
  /// - `true` if the user confirms the action
  /// - `false` if the user cancels or dismisses the dialog
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required String label,
    required VoidCallback onPressed,
    String cancelLabel = 'Cancel',
    Color? confirmColor,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        elevation: 6, // Material 3 elevation
        backgroundColor: colorScheme.surfaceContainer, // TODO: consider to use surfaceContainerLowest
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28), // Material 3 shape
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 400.0,
            minWidth: 280.0,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(cancelLabel),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: confirmColor ?? colorScheme.error,
                        foregroundColor: colorScheme.onError,
                      ),
                      child: Text(label),
                      onPressed: () {
                        onPressed();
                        Navigator.of(context).pop(true);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((value) => value ?? false);
  }
}