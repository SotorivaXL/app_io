import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clean_kanban/clean_kanban.dart';

class ColumnSettingsScreen extends StatelessWidget {
  const ColumnSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final boardProvider = Provider.of<BoardProvider>(context);
    
    // Check if board is loaded
    if (boardProvider.board == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final columns = boardProvider.board!.columns;
    final screenWidth = MediaQuery.of(context).size.width;
    // Limit card width to 400px or 90% of screen width, whichever is smaller
    final cardWidth = screenWidth > 450 ? 800.0 : screenWidth * 0.8;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.2),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Information card moved to top
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: cardWidth,
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Column limits (WIP limits) help control workflow and prevent overloading any stage in your process.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Settings section header
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: cardWidth,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                  child: Text(
                    'Column Task Limits',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            // Column settings cards - centered with limited width
            ...columns.map((column) => Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: cardWidth,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ColumnLimitSettingTile(
                      column: column,
                      onLimitChanged: (newLimit) async {
                        await boardProvider.updateColumnLimit(column.id, newLimit);
                      },
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class ColumnLimitSettingTile extends StatefulWidget {
  final KanbanColumn column;
  final Function(int?) onLimitChanged;

  const ColumnLimitSettingTile({
    super.key,
    required this.column,
    required this.onLimitChanged,
  });

  @override
  State<ColumnLimitSettingTile> createState() => _ColumnLimitSettingTileState();
}

class _ColumnLimitSettingTileState extends State<ColumnLimitSettingTile> {
  late bool _isLimited;
  late int _limit;

  @override
  void initState() {
    super.initState();
    _isLimited = widget.column.columnLimit != null;
    // Initialize limit to either the current limit or the max of (current tasks count, 5)
    _limit = widget.column.columnLimit ?? 
      (widget.column.tasks.length > 5 ? widget.column.tasks.length : 5);
  }

  void _showErrorSnackBar(String message) {
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 3),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _updateLimit(int? newLimit) async {
    try {
      await widget.onLimitChanged(newLimit);
    } catch (e) {
      _showErrorSnackBar('Error updating limit: ${e.toString()}');
      // Reset state if there was an error
      setState(() {
        if (widget.column.columnLimit != null) {
          _isLimited = true;
          _limit = widget.column.columnLimit!;
        } else {
          _isLimited = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSlider = _isLimited;
    final bool showNote = _isLimited && widget.column.tasks.isNotEmpty;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Column header with background color
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: widget.column.headerBgColorLight != null
                ? Color(int.parse(widget.column.headerBgColorLight!.substring(1), radix: 16))
                : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            // Use column's custom header color if available
          ),
          child: Text(
            widget.column.header,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Column settings
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Tasks: ${widget.column.tasks.length}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  Text(
                    'Limit:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  if (_isLimited)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_limit.toInt()}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (!_isLimited)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'None',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isLimited,
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (value) {
                      setState(() {
                        _isLimited = value;
                      });
                      if (!_isLimited) {
                        // Set to unlimited
                        _updateLimit(null);
                      } else {
                        // Apply current limit value, ensuring it's not less than task count
                        if (_limit < widget.column.tasks.length) {
                          setState(() {
                            _limit = widget.column.tasks.length;
                          });
                        }
                        _updateLimit(_limit);
                      }
                    },
                  ),
                ],
              ),
              if (hasSlider) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${widget.column.tasks.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Expanded(
                      child: Slider(
                        min: widget.column.tasks.length.toDouble(),
                        max: 20,
                        divisions: 20 - widget.column.tasks.length,
                        value: _limit.toDouble(),
                        activeColor: Theme.of(context).colorScheme.primary,
                        label: '${_limit.toInt()}',
                        onChanged: (value) {
                          setState(() {
                            _limit = value.toInt();
                          });
                        },
                        onChangeEnd: (value) {
                          // Only update when user stops dragging
                          _updateLimit(_limit);
                        },
                      ),
                    ),
                    Text(
                      '20',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (showNote) ...[
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline, 
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Minimum limit equals current tasks',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}