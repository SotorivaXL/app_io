import 'package:clean_kanban/core/exceptions.dart';

/// Represents a task in a Kanban board.
///
/// Each task has a unique [id], [title], and [subtitle].
/// The title and subtitle are limited to 100 characters each.
class Task {
  /// Unique identifier for the task.
  final String id;

  /// The title of the task.
  /// Must be 100 characters or less.
  final String title;

  /// The subtitle or description of the task.
  /// Must be 100 characters or less.
  final String subtitle;
  
  /// Creates a new task with the given [id], [title], and [subtitle].
  ///
  /// Throws [TaskOperationException] if:
  /// * [title] is longer than 100 characters
  /// * [subtitle] is longer than 100 characters
  Task({required this.id, required this.title, required this.subtitle}) {
    if (title.length > 100) {
      throw TaskOperationException('Title must be at most 100 characters long.');
    }
    if (subtitle.length > 100) {
      throw TaskOperationException('Subtitle must be at most 100 characters long.');
    }
  }
  
  /// Converts the task to a JSON-compatible map for persistence.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
    };
  }

  /// Creates a copy of this task with optionally updated fields.
  ///
  /// The [id] is preserved while [title] and [subtitle] can be updated.
  Task copyWith({ String? title, String? subtitle}) {
    return Task(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    
    return other is Task &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle;
  }

  @override
  int get hashCode => Object.hash(id, title, subtitle);
}
