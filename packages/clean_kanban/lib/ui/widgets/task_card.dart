import 'package:flutter/material.dart';
import 'task_drag_data.dart';
import 'dart:convert';

class TaskMetaStore {
  static final Map<String, Map<String, dynamic>> _byId = {};

  static void setMeta(
      String id, {
        required String photoUrl,
        DateTime? arrivedAt,
        required String lastMsg,
        List<Map<String, dynamic>>? tags,
      }) {
    _byId[id] = {
      'photo': photoUrl,
      'arrivedAt': arrivedAt?.toIso8601String(),
      'lastMsg': lastMsg,
      'tags': tags ?? const <Map<String, dynamic>>[],
    };
  }

  static Map<String, dynamic> getMeta(String id) => _byId[id] ?? {};
}

/// Constants for TaskCard layout measurements
class TaskCardLayout {
  static const double cardBorderRadius = 14.0;

  // em vez de "Card elevation", vamos usar BoxShadow (mais bonito e consistente)
  static const double cardElevation = 0.0;
  static const double cardDraggingElevation = 10.0;

  static const double dragScale = 1.03;
  static const Duration dragDelay = Duration(milliseconds: 120);

  // padding interno
  static const EdgeInsets contentPadding =
  EdgeInsets.fromLTRB(12, 10, 12, 10);

  // barra lateral
  static const double accentBarWidth = 4.0;

  // constraints
  static const double minCardWidth = 280.0;
  static const double maxCardWidth = 600.0;

  // tipografia
  static const double titleFontSize = 14.0;
  static const double subtitleFontSize = 12.5;
  static const double subtitleLineHeight = 1.25;
  static const double titleLetterSpacing = 0.1;
}

/// Theme configuration for a task card.
///
/// Defines the visual appearance of a task card including colors for
/// background, borders, text, and interactive elements.
class TaskCardTheme {
  /// Background color of the card.
  final Color cardBackgroundColor;

  /// Color of the card's border.
  final Color cardBorderColor;

  /// Width of the card's border.
  final double cardBorderWidth;

  /// Text color for the task title.
  final Color cardTitleColor;

  /// Text color for the task subtitle.
  final Color cardSubtitleColor;

  /// Color for enabled move/drag icons.
  final Color cardMoveIconEnabledColor;

  /// Color for disabled move/drag icons.
  final Color cardMoveIconDisabledColor;

  /// Color of the card's divider.
  final Color cardDividerColor;

  /// Creates a [TaskCardTheme] with customizable colors.
  ///
  /// All parameters have default values that create a standard light theme.
  const TaskCardTheme({
    this.cardBackgroundColor = Colors.white,
    this.cardBorderColor = const Color(0xFFE0E0E0),
    this.cardBorderWidth = 0.0,
    this.cardTitleColor = const Color.fromRGBO(0, 0, 0, 0.867),
    this.cardSubtitleColor = const Color.fromRGBO(0, 0, 0, 0.541),
    this.cardMoveIconEnabledColor = const Color.fromRGBO(25, 118, 210, 1),
    this.cardMoveIconDisabledColor = const Color.fromRGBO(224, 224, 224, 1),
    this.cardDividerColor = const Color(0xFFE0E0E0),
  });

  /// Creates a copy of this [TaskCardTheme] with modified values.
  ///
  /// Any parameter that is null will keep its original value.
  TaskCardTheme copyWith({
    Color? cardBackgroundColor,
    Color? cardBorderColor,
    double? cardBorderWidth,
    Color? cardTitleColor,
    Color? cardSubtitleColor,
    Color? cardMoveIconEnabledColor,
    Color? cardMoveIconDisabledColor,
    Color? cardDividerColor,
  }) {
    return TaskCardTheme(
      cardBackgroundColor: cardBackgroundColor ?? this.cardBackgroundColor,
      cardBorderColor: cardBorderColor ?? this.cardBorderColor,
      cardBorderWidth: cardBorderWidth ?? this.cardBorderWidth,
      cardTitleColor: cardTitleColor ?? this.cardTitleColor,
      cardSubtitleColor: cardSubtitleColor ?? this.cardSubtitleColor,
      cardMoveIconEnabledColor: cardMoveIconEnabledColor ??
          this.cardMoveIconEnabledColor,
      cardMoveIconDisabledColor: cardMoveIconDisabledColor ??
          this.cardMoveIconDisabledColor,
      cardDividerColor: cardDividerColor ?? this.cardDividerColor,
    );
  }
}

class TaskCardContent extends StatelessWidget {
  final TaskDragData data;
  final TaskCardTheme theme;

  const TaskCardContent({
    super.key,
    required this.data,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final meta = TaskMetaStore.getMeta(data.task.id);

    final photo = (meta['photo'] ?? '').toString().trim();
    final arrivedAtStr = (meta['arrivedAt'] ?? '').toString().trim();

    DateTime? arrivedAt;
    if (arrivedAtStr.isNotEmpty) {
      arrivedAt = DateTime.tryParse(arrivedAtStr);
    }

    String dateLabel = '';
    if (arrivedAt != null) {
      final d = arrivedAt.toLocal();
      dateLabel =
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    final rawTags = (meta['tags'] as List?) ?? const [];
    final tags = rawTags
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(photoUrl: photo),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      data.task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TaskCardLayout.titleFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: TaskCardLayout.titleLetterSpacing,
                        color: theme.cardTitleColor,
                      ),
                    ),
                  ),
                  if (dateLabel.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: theme.cardSubtitleColor,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _TagsLine(
                tags: tags,
                textColor: theme.cardSubtitleColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String photoUrl;
  const _Avatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 42,
        height: 42,
        color: Colors.black.withOpacity(0.06),
        child: hasPhoto
            ? Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 22),
        )
            : const Icon(Icons.person, size: 22),
      ),
    );
  }
}

class TaskCard extends StatelessWidget {
  final TaskDragData data;
  final TaskCardTheme theme;

  const TaskCard({
    super.key,
    required this.data,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final accent = theme.cardMoveIconEnabledColor;

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: theme.cardBackgroundColor,
        borderRadius: BorderRadius.circular(TaskCardLayout.cardBorderRadius),
        border: theme.cardBorderWidth > 0
            ? Border.all(color: theme.cardBorderColor, width: theme.cardBorderWidth)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: TaskCardLayout.accentBarWidth,
            height: 64,
            color: accent,
          ),
          Expanded(
            child: Padding(
              padding: TaskCardLayout.contentPadding,
              child: TaskCardContent(data: data, theme: theme),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsLine extends StatelessWidget {
  final List<Map<String, dynamic>> tags;
  final Color textColor;

  const _TagsLine({
    required this.tags,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text(
        'Sem etiquetas',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: TaskCardLayout.subtitleFontSize,
          height: TaskCardLayout.subtitleLineHeight,
          color: textColor.withOpacity(0.75),
        ),
      );
    }

    return SizedBox(
      height: 24,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tags.map((t) {
            final name = (t['name'] ?? '').toString().trim();
            if (name.isEmpty) return const SizedBox.shrink();

            // cor vindo do Firestore (int tipo 4284955319)
            final tagColor = _parseAnyColor(t['color']) ?? const Color(0xFF9E9E9E);

            // texto preto ou branco automaticamente
            final onDark =
                ThemeData.estimateBrightnessForColor(tagColor) == Brightness.dark;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: tagColor, // ✅ fundo sólido (cor original)
                  borderRadius: BorderRadius.circular(5), // ✅ igual seu WhatsAppChats
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: onDark ? Colors.white : Colors.black, // ✅ nunca a cor da tag
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

Color? _parseAnyColor(dynamic raw) {
  if (raw == null) return null;

  // ✅ se já veio como int/num (Firestore number)
  if (raw is int) return Color(raw);
  if (raw is num) return Color(raw.toInt());

  final s = raw.toString().trim();
  if (s.isEmpty) return null;

  // ✅ string numérica tipo "4284955319"
  final asInt = int.tryParse(s);
  if (asInt != null) return Color(asInt);

  // ✅ aceita "#RRGGBB" ou "#AARRGGBB"
  if (s.startsWith('#')) {
    final hex = s.substring(1);
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    if (hex.length == 8) return Color(int.parse(hex, radix: 16));
  }

  return null;
}