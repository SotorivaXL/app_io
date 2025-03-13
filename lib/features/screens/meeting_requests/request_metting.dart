import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class RequestMetting extends StatefulWidget {
  const RequestMetting({super.key});

  @override
  State<RequestMetting> createState() => _RequestMettingState();
}

class _RequestMettingState extends State<RequestMetting> {
  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  final _formKey = GlobalKey<FormState>();

  final TextEditingController _motivoController = TextEditingController();
  final TextEditingController _assuntoController = TextEditingController();

  String? _urgency;
  DateTime? _selectedDate;

  // Lista de feriados nacionais para 2025 (ajuste conforme necessário)
  final List<DateTime> _holidays = [
    DateTime(2025, 1, 1), // Confraternização Universal
    DateTime(2025, 4, 18), // Sexta-feira Santa
    DateTime(2025, 4, 21), // Tiradentes
    DateTime(2025, 5, 1), // Dia do Trabalho
    DateTime(2025, 6, 19), // Corpus Christi
    DateTime(2025, 9, 7), // Independência do Brasil
    DateTime(2025, 10, 12), // Nossa Senhora Aparecida
    DateTime(2025, 11, 2), // Finados
    DateTime(2025, 11, 15), // Proclamação da República
    DateTime(2025, 11, 20), // Dia Nacional de Zumbi e da Consciência Negra
    DateTime(2025, 11, 28), // Dia do Município
    DateTime(2025, 12, 25), // Natal
  ];

  // Método para selecionar a data (apenas via calendário, sem digitação)
  Future<void> _selectDate(BuildContext context) async {
    final DateTime today = DateTime.now();
    DateTime initialDate = today;
    DateTime firstDate = today;
    DateTime lastDate = DateTime(today.year + 1);

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 400,
            height: 350,
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: isDarkMode
                    ? ColorScheme.dark(
                  primary: Colors.deepPurple,
                  onPrimary: Colors.white,
                  surface: Colors.grey[800]!,
                  onSurface: Colors.white,
                )
                    : ColorScheme.light(
                  primary: Colors.deepPurple,
                  onPrimary: Colors.white,
                  surface: Colors.grey[200]!,
                  onSurface: Colors.black,
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              child: CalendarDatePicker(
                initialDate: initialDate,
                firstDate: firstDate,
                lastDate: lastDate,
                selectableDayPredicate: (DateTime date) {
                  if (date.weekday < DateTime.monday ||
                      date.weekday > DateTime.friday) return false;
                  for (DateTime holiday in _holidays) {
                    if (date.year == holiday.year &&
                        date.month == holiday.month &&
                        date.day == holiday.day) {
                      return false;
                    }
                  }
                  return true;
                },
                onDateChanged: (DateTime date) {
                  initialDate = date;
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                "Cancelar",
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(initialDate);
              },
              child: Text(
                "OK",
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // Busca o nome da empresa a partir do UID do usuário logado
  Future<String?> _getCompanyName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final createdBy = userDoc.get('createdBy');
      final empresaDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(createdBy)
          .get();
      if (empresaDoc.exists) {
        return empresaDoc.get('NomeEmpresa');
      }
    }

    final empresaDocDirect =
    await FirebaseFirestore.instance.collection('empresas').doc(uid).get();
    if (empresaDocDirect.exists) {
      return empresaDocDirect.get('NomeEmpresa');
    }
    return null;
  }

  // Valida e salva a solicitação no Firestore, limpa os campos e volta para a tela anterior
  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate() &&
        _selectedDate != null &&
        _urgency != null) {
      String? nomeEmpresa = await _getCompanyName();
      if (nomeEmpresa == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Empresa não encontrada.')),
        );
        return;
      }

      final meetingData = {
        'motivo': _motivoController.text,
        'assunto': _assuntoController.text,
        'urgencia': _urgency,
        'dataReuniao': _selectedDate,
        'nomeEmpresa': nomeEmpresa,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('meetingRequests')
          .add(meetingData);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Solicitação de reunião enviada com sucesso!',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Limpa os campos
      _formKey.currentState!.reset();
      setState(() {
        _selectedDate = null;
        _urgency = null;
      });

      // Volta para a tela anterior
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Por favor, preencha todos os campos obrigatórios.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _navigateWithBottomToTopTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          final tween =
          Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          final offsetAnimation = animation.drive(tween);
          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 1024;
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    return ConnectivityBanner(
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(appBarHeight),
          child: Opacity(
            opacity: opacity,
            child: AppBar(
              toolbarHeight: appBarHeight,
              automaticallyImplyLeading: false,
              flexibleSpace: SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onBackground,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Voltar',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Solicitar Reunião',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color:
                              Theme.of(context).colorScheme.onSecondary,
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
          ),
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Campo do motivo da reunião
                TextFormField(
                  controller: _motivoController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Digite o motivo da reunião',
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.secondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.meeting_room,
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 20,
                    ),
                    contentPadding: isDesktop
                        ? EdgeInsets.symmetric(vertical: 25)
                        : EdgeInsets.symmetric(vertical: 15),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o motivo da reunião';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                // Campo do assunto da reunião
                TextFormField(
                  controller: _assuntoController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Digite o assunto da reunião',
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.secondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.subject,
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 20,
                    ),
                    contentPadding: isDesktop
                        ? EdgeInsets.symmetric(vertical: 25)
                        : EdgeInsets.symmetric(vertical: 15),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o assunto da reunião';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                // Dropdown de urgência
                DropdownButtonFormField<String>(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Selecione a urgência da reunião',
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.secondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.add_alert,
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 20,
                    ),
                    contentPadding: isDesktop
                        ? EdgeInsets.symmetric(vertical: 25)
                        : EdgeInsets.symmetric(vertical: 15),
                  ),
                  value: _urgency,
                  items: [
                    'Muito Baixa',
                    'Baixa',
                    'Media',
                    'Alta',
                    'Muito Alta',
                    'Urgente'
                  ]
                      .map((urgency) => DropdownMenuItem<String>(
                    value: urgency,
                    child: Text(
                      urgency,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _urgency = value;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, selecione a urgência';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                // Campo de seleção de data com formatação dd/MM/yyyy
                InkWell(
                  onTap: () => _selectDate(context),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.secondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(
                        Icons.date_range,
                        color: Theme.of(context).colorScheme.tertiary,
                        size: 20,
                      ),
                      contentPadding: isDesktop
                          ? EdgeInsets.symmetric(vertical: 25)
                          : EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedDate == null
                              ? 'Selecione uma data'
                              : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 24),
                // Botão para salvar a solicitação
                ElevatedButton.icon(
                  onPressed: _submitForm,
                  icon: Icon(
                    Icons.add_task,
                    color: Theme.of(context).colorScheme.outline,
                    size: 25,
                  ),
                  label: Text(
                    'Solicitar reunião',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}