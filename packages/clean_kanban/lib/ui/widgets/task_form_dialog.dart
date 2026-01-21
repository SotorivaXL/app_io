import 'package:flutter/material.dart';

/// A dialog widget that displays a form for creating or editing tasks.
///
/// This dialog provides fields for entering a task title and subtitle,
/// with validation and error handling built-in. Follows Material 3 design guidelines.
class TaskFormDialog extends StatefulWidget {
  /// Callback function called when the form is saved.
  /// Takes a [title] and [subtitle] as parameters.
  final Function(String title, String subtitle) onSave;

  /// The initial title to populate the title field.
  final String? initialTitle;

  /// The initial subtitle to populate the subtitle field.
  final String? initialSubtitle;

  /// The title text displayed at the top of the dialog.
  final String dialogTitle;

  /// The label text for the submit button.
  final String submitLabel;

  /// Creates a [TaskFormDialog].
  ///
  /// The [onSave] callback is required and is called when the form is submitted
  /// with valid data.
  const TaskFormDialog({
    super.key,
    required this.onSave,
    this.initialTitle,
    this.initialSubtitle,
    this.dialogTitle = 'Add New Task',
    this.submitLabel = 'Add',
  });

  @override
  State<TaskFormDialog> createState() => TaskFormDialogState();
}

/// The state class for [TaskFormDialog] widget.
///
/// This class manages the form state including text controllers for title and subtitle inputs,
/// form validation, submission state, and error handling.
class TaskFormDialogState extends State<TaskFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _subtitleController = TextEditingController(text: widget.initialSubtitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    try {
      if (_formKey.currentState?.validate() ?? false) {
        setState(() {
          _isSubmitting = true;
          _hasError = false;
        });

        // Trim whitespace from inputs
        final title = _titleController.text.trim();
        final subtitle = _subtitleController.text.trim();

        // Additional validation
        if (title.length > 100) {
          _showError('Title must be less than 100 characters');
          return;
        }

        if (subtitle.length > 200) {
          _showError('Description must be less than 200 characters');
          return;
        }

        // Unfocus before submitting to prevent keyboard issues
        FocusManager.instance.primaryFocus?.unfocus();

        try {
          widget.onSave(title, subtitle);
          Navigator.of(context).pop();
        } catch (e) {
          _showError('Failed to save task. Please try again.');
        }
      }
    } catch (e) {
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _hasError = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Theme.of(context).colorScheme.onError,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    
    return PopScope(
      canPop: !_isSubmitting,
      child: Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
        elevation: 6, // Material 3 elevation
        backgroundColor: colorScheme.surfaceContainer, // Set the dialog background color
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28), // Material 3 shape
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 400.0,
            minWidth: 200.0,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.dialogTitle,
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 24.0),
                SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'Title',
                            hintText: 'Enter task title',
                            errorMaxLines: 2,
                            helperText: 'Required, max 100 characters',
                            helperMaxLines: 2,
                            errorStyle: TextStyle(color: colorScheme.error),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            border: const OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                          autofocus: true,
                          enabled: !_isSubmitting,
                          maxLength: 100,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a title';
                            }
                            if (value.length > 100) {
                              return 'Title must be less than 100 characters';
                            }
                            return null;
                          },
                          onChanged: (_) {
                            if (_hasError) {
                              setState(() => _hasError = false);
                            }
                          },
                        ),
                        const SizedBox(height: 24.0),
                        TextFormField(
                          controller: _subtitleController,
                          decoration: InputDecoration(
                            labelText: 'Subtitle',
                            hintText: 'Brief description or link to task',
                            errorMaxLines: 2,
                            helperText: 'Optional, max 200 characters',
                            helperMaxLines: 2,
                            errorStyle: TextStyle(color: colorScheme.error),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.short_text),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _subtitleController.text.isEmpty
                                  ? null
                                  : () => setState(
                                      () => _subtitleController.clear()),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          enabled: !_isSubmitting,
                          maxLength: 200,
                          maxLines: 1,
                          onFieldSubmitted: (_) => _handleSubmit(),
                          onChanged: (value) {
                            if (_hasError) {
                              setState(() => _hasError = false);
                            }
                            // Force a rebuild to update the clear button state
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.of(context).pop();
                            },
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 16.0),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _handleSubmit,
                      child: _isSubmitting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                              ),
                            )
                          : Text(widget.submitLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}