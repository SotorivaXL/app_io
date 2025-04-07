import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Calender extends StatefulWidget {
  const Calender({Key? key}) : super(key: key);

  @override
  State<Calender> createState() => _CalenderState();
}

class _CalenderState extends State<Calender> {
  // Data que define o mês exibido atualmente.
  DateTime _displayedMonth =
  DateTime(DateTime.now().year, DateTime.now().month);

  double _scrollOffset = 0.0;

  // Lista de feriados (fixos: dia e mês). Ajuste conforme necessário, incluindo feriados municipais.
  final List<Map<String, int>> _holidays = [
    {'day': 1, 'month': 1},   // Ano Novo
    {'day': 21, 'month': 4},  // Tiradentes
    {'day': 1, 'month': 5},   // Dia do Trabalhador
    {'day': 19, 'month': 7},   // Corpus Christi
    {'day': 7, 'month': 9},   // Independência
    {'day': 1, 'month': 10}, // Dia do Municipio
    {'day': 12, 'month': 10}, // Nossa Senhora Aparecida
    {'day': 2, 'month': 11},  // Finados
    {'day': 15, 'month': 11}, // Proclamação da República
    {'day': 20, 'month': 11}, // Consciência Negra
    {'day': 28, 'month': 11}, // Aniversário de Ampére
    {'day': 25, 'month': 12}, // Natal
    // Adicione ou remova feriados municipais aqui.
  ];

  /// Verifica se a data é um feriado.
  bool _isHoliday(DateTime date) {
    return _holidays.any((holiday) =>
    holiday['day'] == date.day && holiday['month'] == date.month);
  }

  // Função para buscar eventos do mês (já existente).
  Future<Map<DateTime, String>> _getEventsForMonth(DateTime month) async {
    DateTime startMonth = DateTime(month.year, month.month, 1);
    DateTime endMonth = DateTime(month.year, month.month + 1, 1);

    QuerySnapshot meetingSnapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('dataReuniao', isGreaterThanOrEqualTo: startMonth)
        .where('dataReuniao', isLessThan: endMonth)
        .get();

    QuerySnapshot recordingSnapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('dataGravacaoInicio', isLessThanOrEqualTo: endMonth)
        .where('dataGravacaoFim', isGreaterThanOrEqualTo: startMonth)
        .get();

    Map<DateTime, String> dayEventType = {};

    for (var doc in meetingSnapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      DateTime dt = (data['dataReuniao'] as Timestamp).toDate();
      DateTime key = DateTime(dt.year, dt.month, dt.day);
      dayEventType[key] = "Reunião";
    }

    for (var doc in recordingSnapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      DateTime recStart = (data['dataGravacaoInicio'] as Timestamp).toDate();
      DateTime recEnd = (data['dataGravacaoFim'] as Timestamp).toDate();
      if (recEnd.isBefore(startMonth) || recStart.isAfter(endMonth)) continue;
      DateTime effectiveStart = recStart.isBefore(startMonth) ? startMonth : recStart;
      DateTime effectiveEnd = recEnd.isAfter(endMonth)
          ? endMonth.subtract(const Duration(days: 1))
          : recEnd;
      for (DateTime d = DateTime(effectiveStart.year, effectiveStart.month, effectiveStart.day);
      !d.isAfter(DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day));
      d = d.add(const Duration(days: 1))) {
        if (!dayEventType.containsKey(d)) {
          dayEventType[d] = "Gravação";
        }
      }
    }
    return dayEventType;
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: appBarHeight,
        automaticallyImplyLeading: false,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            color: Theme.of(context).colorScheme.onBackground,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Voltar',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Calendário',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.secondary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () {
                      setState(() {
                        _displayedMonth = DateTime(
                          _displayedMonth.year,
                          _displayedMonth.month - 1,
                        );
                      });
                    },
                  ),
                  Text(
                    "${_getMonthName(_displayedMonth.month)} ${_displayedMonth.year}",
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios),
                    onPressed: () {
                      setState(() {
                        _displayedMonth = DateTime(
                          _displayedMonth.year,
                          _displayedMonth.month + 1,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
                    .map((day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ))
                    .toList(),
              ),
            ),
            Expanded(
              child: FutureBuilder<Map<DateTime, List<String>>>(
                future: _getEventLabelsForMonth(_displayedMonth),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: Text("Nenhum evento encontrado."));
                  }
                  final dayEvents = snapshot.data!;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _buildCalendarGrid(dayEvents),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Busca e agrupa as etiquetas dos eventos para o mês.
  Future<Map<DateTime, List<String>>> _getEventLabelsForMonth(DateTime month) async {
    DateTime startMonth = DateTime(month.year, month.month, 1);
    DateTime endMonth = DateTime(month.year, month.month + 1, 1);

    List<DateTime> days = _getDaysForCalendar(month);
    Map<DateTime, List<String>> dayLabels = {};
    for (var day in days) {
      DateTime key = DateTime(day.year, day.month, day.day);
      dayLabels[key] = [];
    }

    QuerySnapshot meetingSnapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('dataReuniao', isGreaterThanOrEqualTo: startMonth)
        .where('dataReuniao', isLessThan: endMonth)
        .get();

    for (var doc in meetingSnapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      DateTime dt = (data['dataReuniao'] as Timestamp).toDate();
      DateTime key = DateTime(dt.year, dt.month, dt.day);
      if (dayLabels.containsKey(key)) {
        dayLabels[key]!.add("Reunião");
      }
    }

    QuerySnapshot recordingSnapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('dataGravacaoInicio', isLessThanOrEqualTo: endMonth)
        .where('dataGravacaoFim', isGreaterThanOrEqualTo: startMonth)
        .get();

    for (var doc in recordingSnapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      DateTime recStart = (data['dataGravacaoInicio'] as Timestamp).toDate();
      DateTime recEnd = (data['dataGravacaoFim'] as Timestamp).toDate();
      if (recEnd.isBefore(startMonth) || recStart.isAfter(endMonth)) continue;
      DateTime effectiveStart = recStart.isBefore(startMonth) ? startMonth : recStart;
      DateTime effectiveEnd = recEnd.isAfter(endMonth)
          ? endMonth.subtract(const Duration(days: 1))
          : recEnd;
      for (DateTime d = DateTime(effectiveStart.year, effectiveStart.month, effectiveStart.day);
      !d.isAfter(DateTime(effectiveEnd.year, effectiveEnd.month, effectiveEnd.day));
      d = d.add(const Duration(days: 1))) {
        DateTime key = DateTime(d.year, d.month, d.day);
        if (dayLabels.containsKey(key)) {
          dayLabels[key]!.add("Gravação");
        }
      }
    }
    return dayLabels;
  }

  /// Constrói a grade de dias, exibindo os marcadores dos eventos e dos feriados.
  Widget _buildCalendarGrid(Map<DateTime, List<String>> dayEvents) {
    final days = _getDaysForCalendar(_displayedMonth);
    final rows = (days.length / 7).ceil();

    List<Widget> dayWidgets = days.map((date) {
      bool isCurrentMonth = date.month == _displayedMonth.month;
      bool isToday = date.year == DateTime.now().year &&
          date.month == DateTime.now().month &&
          date.day == DateTime.now().day;
      DateTime key = DateTime(date.year, date.month, date.day);
      // Cria uma cópia da lista para não modificar o mapa original.
      List<String> labels = List.from(dayEvents[key] ?? []);
      // Se for feriado, adiciona o rótulo "Feriado".
      if (_isHoliday(date)) {
        labels.add("Feriado");
      }

      // Função para obter a cor do rótulo.
      Color? getLabelColor(String tipo) {
        if (tipo == "Reunião") return Colors.blue.shade100;
        if (tipo == "Gravação") return Theme.of(context).colorScheme.onInverseSurface;
        if (tipo == "Feriado") return Colors.amber; // Cor dourada para feriados.
        return null;
      }

      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => DayView(date: date)),
          );
        },
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context)
                .colorScheme
                .tertiaryContainer!
                .withOpacity(isCurrentMonth ? 1.0 : 0.5),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Exibe o número do dia com dois dígitos.
                    Text(
                      "${date.day.toString().padLeft(2, '0')}",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isToday
                            ? Theme.of(context).colorScheme.tertiary
                            : (isCurrentMonth
                            ? Theme.of(context).colorScheme.onSecondary
                            : Theme.of(context).colorScheme.onSecondary.withOpacity(0.5)),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: labels.take(5).map((tipo) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: getLabelColor(tipo),
                                borderRadius: BorderRadius.circular(2.5),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        double cellWidth = constraints.maxWidth / 7;
        double cellHeight = constraints.maxHeight / rows;
        double childAspectRatio = cellWidth / cellHeight;
        return GridView.count(
          crossAxisCount: 7,
          childAspectRatio: childAspectRatio,
          physics: const NeverScrollableScrollPhysics(),
          children: dayWidgets,
        );
      },
    );
  }

  /// Gera uma lista com as datas a serem exibidas na grade, incluindo os dias do mês anterior e seguinte.
  List<DateTime> _getDaysForCalendar(DateTime month) {
    List<DateTime> calendarDays = [];
    int year = month.year;
    int mon = month.month;
    DateTime firstDayOfMonth = DateTime(year, mon, 1);
    int offset = firstDayOfMonth.weekday % 7;
    DateTime lastDayPrevMonth = DateTime(year, mon, 0);
    int daysInPrevMonth = lastDayPrevMonth.day;
    for (int i = offset - 1; i >= 0; i--) {
      calendarDays.add(DateTime(
          lastDayPrevMonth.year, lastDayPrevMonth.month, daysInPrevMonth - i));
    }
    int totalDays = DateTime(year, mon + 1, 0).day;
    for (int i = 1; i <= totalDays; i++) {
      calendarDays.add(DateTime(year, mon, i));
    }
    int remainder = calendarDays.length % 7;
    if (remainder != 0) {
      int extra = 7 - remainder;
      for (int i = 1; i <= extra; i++) {
        calendarDays.add(DateTime(year, mon + 1, i));
      }
    }
    return calendarDays;
  }

  /// Retorna o nome do mês em português.
  String _getMonthName(int month) {
    const monthNames = [
      "Janeiro",
      "Fevereiro",
      "Março",
      "Abril",
      "Maio",
      "Junho",
      "Julho",
      "Agosto",
      "Setembro",
      "Outubro",
      "Novembro",
      "Dezembro"
    ];
    return monthNames[month - 1];
  }
}

/// Tela que exibe a visualização do dia clicado, com as horas do dia.
/// Cada horário é exibido em uma linha (usando ExpansionTile) para mostrar os eventos agendados.
class DayView extends StatefulWidget {
  final DateTime date;

  const DayView({Key? key, required this.date}) : super(key: key);

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  late DateTime _currentDate;
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _currentDate = widget.date;
  }

  // Lista de feriados (fixos: dia e mês) para uso na visualização do dia. Ajuste conforme necessário.
  final List<Map<String, dynamic>> _holidays = [
    {'day': 1, 'month': 1, 'name': 'Ano Novo'},
    {'day': 21, 'month': 4, 'name': 'Tiradentes'},
    {'day': 1, 'month': 5, 'name': 'Dia do Trabalhador'},
    {'day': 19, 'month': 7, 'name': 'Corpus Christi'},
    {'day': 7, 'month': 9, 'name': 'Independência'},
    {'day': 1, 'month': 10, 'name': 'Dia do Municipio'},
    {'day': 12, 'month': 10, 'name': 'Nossa Senhora Aparecida'},
    {'day': 2, 'month': 11, 'name': 'Finados'},
    {'day': 15, 'month': 11, 'name': 'Proclamação da República'},
    {'day': 20, 'month': 11, 'name': 'Consciência Negra'},
    {'day': 28, 'month': 11, 'name': 'Aniversário de Ampére'},
    {'day': 25, 'month': 12, 'name': 'Natal'},
    // Adicione ou remova feriados municipais aqui.
  ];

  bool _isHoliday(DateTime date) {
    return _holidays.any((holiday) => holiday['day'] == date.day && holiday['month'] == date.month);
  }

  String _getHolidayName(DateTime date) {
    final holiday = _holidays.firstWhere(
      (h) => h['day'] == date.day && h['month'] == date.month,
      orElse: () => {},
    );
    if (holiday.isNotEmpty && holiday.containsKey('name')) {
      return holiday['name'];
    }
    return 'Feriado';
  }

  Future<Map<int, List<Map<String, dynamic>>>> _getEventsForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    QuerySnapshot meetingSnapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('dataReuniao', isGreaterThanOrEqualTo: start)
        .where('dataReuniao', isLessThan: end)
        .get();

    QuerySnapshot recordingSnapshot = await FirebaseFirestore.instance
        .collection('requests')
        .where('dataGravacaoInicio', isLessThanOrEqualTo: end)
        .where('dataGravacaoFim', isGreaterThanOrEqualTo: start)
        .get();

    List<Map<String, dynamic>> events = [];

    for (var doc in meetingSnapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      DateTime eventTime = (data['dataReuniao'] as Timestamp).toDate();
      data['hour'] = eventTime.hour;
      data['fullDate'] = eventTime;
      events.add(data);
    }

    for (var doc in recordingSnapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      DateTime recordingStart = (data['dataGravacaoInicio'] as Timestamp).toDate();
      DateTime recordingEnd = (data['dataGravacaoFim'] as Timestamp).toDate();
      DateTime effectiveStart = recordingStart.isBefore(start) ? start : recordingStart;
      DateTime effectiveEnd = recordingEnd.isAfter(end)
          ? end.subtract(const Duration(minutes: 1))
          : recordingEnd;
      for (int hr = effectiveStart.hour; hr <= effectiveEnd.hour; hr++) {
        var eventData = Map<String, dynamic>.from(data);
        eventData['hour'] = hr;
        eventData['fullDate'] = DateTime(day.year, day.month, day.day, hr);
        events.add(eventData);
      }
    }

    Map<int, List<Map<String, dynamic>>> groupedEvents = {};
    for (int h = 0; h < 24; h++) {
      groupedEvents[h] = [];
    }
    for (var event in events) {
      int hr = event['hour'];
      groupedEvents[hr]?.add(event);
    }
    return groupedEvents;
  }

  Future<String?> _getCompanyPhotoUrl(String nomeEmpresa) async {
    final query = await FirebaseFirestore.instance
        .collection('empresas')
        .where('NomeEmpresa', isEqualTo: nomeEmpresa)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final data = query.docs.first.data();
      return data['photoUrl'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: appBarHeight,
        automaticallyImplyLeading: false,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            color: Theme.of(context).colorScheme.onBackground,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Voltar',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Horários',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.secondary,
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () {
                  setState(() {
                    _currentDate =
                        _currentDate.subtract(const Duration(days: 1));
                  });
                },
              ),
              Text(
                "Dia ${_currentDate.day.toString().padLeft(2, '0')}/${_currentDate.month.toString().padLeft(2, '0')}/${_currentDate.year}",
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: () {
                  setState(() {
                    _currentDate =
                        _currentDate.add(const Duration(days: 1));
                  });
                },
              ),
            ],
          ),
          Expanded(
            child: FutureBuilder<Map<int, List<Map<String, dynamic>>>>(
              future: _getEventsForDay(_currentDate),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData) {
                  return const Center(
                      child: Text("Nenhum evento encontrado."));
                }
                final groupedEvents = snapshot.data!;
                return ListView.builder(
                  itemCount: 24,
                  itemBuilder: (context, hour) {
                    final events = groupedEvents[hour] ?? [];
                    return ExpansionTile(
                      title: Row(
                        children: [
                          if (_isHoliday(_currentDate)) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Feriado: ${_getHolidayName(_currentDate)}',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            "${hour.toString().padLeft(2, '0')}:00",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (events.isNotEmpty)
                            Wrap(
                              spacing: 4,
                              children: events.map((event) {
                                String tipo = event['tipoSolicitacao'] ?? "";
                                Color markerColor;
                                if (tipo == "Reunião") {
                                  markerColor = Colors.blue.shade100;
                                } else if (tipo == "Gravação") {
                                  markerColor = Theme.of(context).colorScheme.onInverseSurface;
                                } else {
                                  markerColor = Colors.grey;
                                }
                                return Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: markerColor,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                      children: events.isNotEmpty
                          ? events.map((event) {
                        final tipoSolicitacao =
                            event['tipoSolicitacao'] ?? '';
                        String title = "";
                        String subtitle = "";
                        if (tipoSolicitacao == "Reunião") {
                          title = event['assunto'] ?? "";
                          subtitle = event['motivo'] ?? "";
                        } else if (tipoSolicitacao == "Gravação") {
                          title = event['descricao'] ?? "";
                          subtitle =
                          "Precisa Roteiro: ${(event['precisaRoteiro'] ?? false) ? "Sim" : "Não"}";
                        }
                        return ListTile(
                          leading: FutureBuilder<String?>(
                            future: _getCompanyPhotoUrl(
                                event['nomeEmpresa'] ?? ''),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const CircleAvatar(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                );
                              }
                              if (snapshot.hasData &&
                                  snapshot.data != null &&
                                  snapshot.data!.isNotEmpty) {
                                return CircleAvatar(
                                  backgroundImage:
                                  NetworkImage(snapshot.data!),
                                );
                              }
                              String company = event['nomeEmpresa'] ?? '';
                              return CircleAvatar(
                                  child: Text(company.isNotEmpty
                                      ? company.substring(0, 1)
                                      : ''));
                            },
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((event['tipoSolicitacao'] ?? "")
                                  .isNotEmpty)
                                Chip(
                                  label: Text(
                                    (event['tipoSolicitacao'] ?? "")
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: (event['tipoSolicitacao'] ==
                                          'Reunião')
                                          ? Colors.blue.shade800
                                          : Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                  backgroundColor: (event['tipoSolicitacao'] ==
                                      'Reunião')
                                      ? Colors.blue.shade100
                                      : Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(8),
                                    side: BorderSide(
                                        width: 0,
                                        color: Colors.transparent),
                                  ),
                                ),
                              Text(
                                title,
                                style: const TextStyle(
                                    fontFamily: 'Poppins'),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                      fontFamily: 'Poppins'),
                                ),
                              Text(
                                event['nomeEmpresa'] ?? '',
                                style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }).toList()
                          : [
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            "Nenhum evento agendado",
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.grey),
                          ),
                        )
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}