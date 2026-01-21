import 'dart:async';
import 'board_events.dart';

/// A singleton event notifier that manages board-related events.
///
/// Provides functionality to subscribe to and notify board events using
/// a broadcast stream controller. This allows multiple listeners to
/// receive board event notifications.
class EventNotifier {
  /// The singleton instance of [EventNotifier].
  static final EventNotifier _instance = EventNotifier._internal();

  /// Factory constructor that returns the singleton instance.
  factory EventNotifier() => _instance;

  /// Internal constructor for singleton pattern.
  EventNotifier._internal();
  
  /// The broadcast stream controller for board events.
  final _controller = StreamController<BoardEvent>.broadcast();

  /// The stream of board events that subscribers can listen to.
  Stream<BoardEvent> get stream => _controller.stream;
  
  /// Subscribes to board events with the provided callback function.
  ///
  /// Returns a [StreamSubscription] that can be used to cancel the subscription.
  StreamSubscription<BoardEvent> subscribe(void Function(BoardEvent) onEvent) {
    return stream.listen(onEvent);
  }

  /// Notifies all subscribers of a new board event.
  ///
  /// The [event] will be sent to all active subscribers.
  void notify(BoardEvent event) {
    _controller.add(event);
  }
  
  /// Closes the stream controller and cleans up resources.
  ///
  /// Should be called when the event notifier is no longer needed.
  void dispose() {
    _controller.close();
  }
}
