/// A clean architecture implementation of a Kanban board system.
///
/// This library provides a complete set of components for building Kanban boards
/// in Flutter applications, following clean architecture principles. It includes:
///
/// * Domain entities for representing board structure
/// * Repository interfaces for data persistence
/// * Use cases for business logic
/// * Event system for state updates
/// * UI widgets for visual representation
/// * Theming system for customization
library clean_kanban;

// Export core components
export 'core/exceptions.dart';
export 'core/result.dart';

// Export domain entities.
export 'domain/entities/board.dart';
export 'domain/entities/column.dart';
export 'domain/entities/task.dart';

// Export repository interfaces.
export 'domain/repositories/board_repository.dart';

// Export use cases.
export 'domain/usecases/board_use_cases.dart';
export 'domain/usecases/task_use_cases.dart';

// Export events and notifier.
export 'domain/events/board_events.dart';
export 'domain/events/event_notifier.dart';
export 'injection_container.dart';

// Export UI widgets.
export 'ui/widgets/board_widget.dart';
export 'ui/widgets/column_widget.dart';
export 'ui/widgets/task_card.dart';
export 'ui/widgets/task_form_dialog.dart';
export 'ui/widgets/confirmation_dialog.dart';
export 'ui/widgets/task_drag_data.dart';

// Export providers
export 'ui/providers/board_provider.dart';

// Export theming system
export 'ui/theme/kanban_theme.dart';
