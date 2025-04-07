import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RequestMetting extends StatefulWidget {
  const RequestMetting({super.key});

  @override
  State<RequestMetting> createState() => _RequestMettingState();
}

class _RequestMettingState extends State<RequestMetting> {
  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();

  final FocusNode _motivoFocus = FocusNode();
  final FocusNode _assuntoFocus = FocusNode();

  final TextEditingController _motivoController = TextEditingController();
  final TextEditingController _assuntoController = TextEditingController();

  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    // Desabilita o pedido de foco inicialmente
    _motivoFocus.canRequestFocus = false;
    _assuntoFocus.canRequestFocus = false;
  }

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

  // Método para selecionar data e horário (sem permitir digitação)
  Future<void> _selectDateTime(BuildContext context) async {
    final DateTime today = DateTime.now();
    DateTime initialDate = today;
    DateTime firstDate = today;
    DateTime lastDate = DateTime(today.year + 1);

    // Diálogo customizado apenas com o calendário (sem TextField)
    final DateTime? pickedDate = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 400,
            height: 350,
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: isDarkMode
                    ? ColorScheme.dark(
                  primary: Theme.of(context).colorScheme.primary,
                  onPrimary: Theme.of(context).colorScheme.outline,
                  surface: Colors.grey[800]!,
                  onSurface: Theme.of(context).colorScheme.onSecondary,
                )
                    : ColorScheme.light(
                  primary: Theme.of(context).colorScheme.primary,
                  onPrimary: Theme.of(context).colorScheme.outline,
                  surface: Colors.grey[200]!,
                  onSurface: Theme.of(context).colorScheme.onSecondary,
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              child: CalendarDatePicker(
                initialDate: initialDate,
                firstDate: firstDate,
                lastDate: lastDate,
                selectableDayPredicate: (DateTime date) {
                  // Permite apenas dias úteis (segunda a sexta) e desabilita feriados
                  if (date.weekday < DateTime.monday ||
                      date.weekday > DateTime.friday) {
                    return false;
                  }
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

    if (pickedDate != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (BuildContext context, Widget? child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: Theme.of(context).colorScheme.primary,
                onPrimary: Theme.of(context).colorScheme.outline,
              ),
            ),
            child: child!,
          );
        },
      );

      if (time != null) {
        setState(() {
          _selectedDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            time.hour,
            time.minute,
          );
        });
      }
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
    if (_formKey.currentState!.validate() && _selectedDate != null) {
      if (_isLoading) return;
      setState(() {
        _isLoading = true;
      });
      // Converte _selectedDate para Timestamp para garantir consistência na comparação
      final Timestamp selectedTimestamp = Timestamp.fromDate(_selectedDate!);

      // Atualização: Verifica conflitos com reuniões levando em conta a carência de 1 hora após o horário agendado
      QuerySnapshot meetingConflict = await FirebaseFirestore.instance
          .collection('requests')
          .where('tipoSolicitacao', isEqualTo: 'Reunião')
          .where('dataReuniao', isGreaterThan: Timestamp.fromDate(_selectedDate!.subtract(Duration(hours: 1))))
          .where('dataReuniao', isLessThanOrEqualTo: selectedTimestamp)
          .get();

      // Conflito para gravações (permanece inalterado)
      QuerySnapshot recordingConflict = await FirebaseFirestore.instance
          .collection('requests')
          .where('tipoSolicitacao', isEqualTo: 'Gravação')
          .where('dataGravacaoInicio', isLessThanOrEqualTo: selectedTimestamp)
          .where('dataGravacaoFim', isGreaterThanOrEqualTo: selectedTimestamp)
          .get();

      if (meetingConflict.docs.isNotEmpty || recordingConflict.docs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Já existe uma solicitação agendada para esse horário.',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      String? nomeEmpresa = await _getCompanyName();
      if (nomeEmpresa == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Empresa não encontrada.')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Obter o UID do usuário atual
      final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // 1) Dados para o Firestore (contém Timestamp e FieldValue)
      final meetingDataFirestore = {
        'motivo': _motivoController.text,
        'assunto': _assuntoController.text,
        'dataReuniao': Timestamp.fromDate(_selectedDate!), // Para Firestore
        'nomeEmpresa': nomeEmpresa,
        'tipoSolicitacao': 'Reunião',
        'createdAt': FieldValue.serverTimestamp(),
        'userId': currentUserId,
      };

      // 2) Dados para a Cloud Function (SQS) - convertendo para string
      final meetingDataSQS = {
        'motivo': _motivoController.text,
        'assunto': _assuntoController.text,
        // Converte para ISO8601. Ex: 2025-05-01T14:30:00.000
        'dataReuniao': _selectedDate!.toIso8601String(),
        'nomeEmpresa': nomeEmpresa,
        'tipoSolicitacao': 'Reunião',
        // Para o createdAt, basta usar o DateTime.now(), caso queira
        'createdAt': DateTime.now().toIso8601String(),
        'userId': currentUserId,
      };

      // Verifica se a empresa já tem solicitação de Reunião para o mesmo mês da data selecionada
      final selectedYear = _selectedDate!.year;
      final selectedMonth = _selectedDate!.month;
      final startOfSelectedMonth = DateTime(selectedYear, selectedMonth, 1);
      final endOfSelectedMonth = DateTime(selectedYear, selectedMonth + 1, 0, 23, 59, 59);

      final sameMonthMeetings = await FirebaseFirestore.instance
          .collection('requests')
          .where('tipoSolicitacao', isEqualTo: 'Reunião')
          .where('nomeEmpresa', isEqualTo: nomeEmpresa)
          .where('dataReuniao', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfSelectedMonth))
          .where('dataReuniao', isLessThanOrEqualTo: Timestamp.fromDate(endOfSelectedMonth))
          .get();

      if (sameMonthMeetings.docs.isNotEmpty) {
        // Se já houver uma reunião para a mesma empresa e mês, envia para a Cloud Function e não salva
        await sendMeetingRequestToSQS(meetingDataSQS);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Já existe uma reunião para este mês. Sua solicitação irá para aprovação da empresa.',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Limpa os campos e retorna
        _formKey.currentState!.reset();
        setState(() {
          _selectedDate = null;
        });
        Navigator.pop(context);
        return;
      }


      // Verifica se o horário selecionado está fora dos intervalos permitidos
      // Intervalos permitidos: 08:30-12:00 e 14:00-18:00
      final DateTime meetingTime = _selectedDate!;
      bool isWithinMorningInterval = (meetingTime.hour > 8 || (meetingTime.hour == 8 && meetingTime.minute >= 30)) && meetingTime.hour < 12;
      bool isWithinAfternoonInterval = meetingTime.hour >= 14 && meetingTime.hour < 18;
      bool isTimeOutsideAllowed = !(isWithinMorningInterval || isWithinAfternoonInterval);

      // Verifica se o usuário já adicionou uma solicitação no mês passado
      final DateTime now = DateTime.now();
      int previousMonth = now.month - 1;
      int previousMonthYear = now.year;
      if (previousMonth < 1) {
        previousMonth = 12;
        previousMonthYear--;
      }
      final DateTime startOfPreviousMonth = DateTime(previousMonthYear, previousMonth, 1);
      final DateTime endOfPreviousMonth = DateTime(previousMonthYear, previousMonth + 1, 0);

      QuerySnapshot lastMonthRequestQuery = await FirebaseFirestore.instance.collection('requests')
          .where('userId', isEqualTo: currentUserId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfPreviousMonth))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfPreviousMonth))
          .get();
      bool hasRequestLastMonth = lastMonthRequestQuery.docs.isNotEmpty;

      // Se o horário estiver fora do intervalo permitido OU se o usuário já adicionou uma solicitação no mês passado, aciona a Cloud Function
      if (isTimeOutsideAllowed || hasRequestLastMonth) {
        await sendMeetingRequestToSQS(meetingDataSQS);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sua solicitação irá para aprovação da empresa.',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Salva a solicitação no Firestore (caso as condições não sejam atendidas)
        await FirebaseFirestore.instance.collection('requests').add(meetingDataFirestore);
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
      }

      // Limpa os campos
      _formKey.currentState!.reset();
      setState(() {
        _selectedDate = null;
      });

      // Volta para a tela anterior
      setState(() {
        _isLoading = false;
      });
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

  Future<void> sendMeetingRequestToSQS(Map<String, dynamic> meetingData) async {
    // Substitua pela URL da sua Cloud Function
    final String cloudFunctionUrl = 'https://sendmeetingrequesttosqs-5a3yl3wsma-uc.a.run.app';
    try {
      final response = await http.post(
        Uri.parse(cloudFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(meetingData),
      );
      if (response.statusCode == 200) {
        print('Dados enviados com sucesso para o SQS: ${response.body}');
      } else {
        print('Falha ao enviar dados para o SQS: ${response.body}');
      }
    } catch (e) {
      print('Erro ao enviar dados para o SQS: $e');
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
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _motivoFocus.dispose();
    _assuntoFocus.dispose();
    _scrollController.dispose();
    _motivoController.dispose();
    _assuntoController.dispose();
    super.dispose();
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
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
          ),
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                spacing: 10,
                children: [
                  // Campo do motivo da reunião
                  // Para o campo de motivo da reunião:
                  TextFormField(
                    controller: _motivoController,
                    focusNode: _motivoFocus,
                    autofocus: false,
                    maxLength: 40,
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
                          ? const EdgeInsets.symmetric(vertical: 25)
                          : const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onTap: () {
                      // Permite o foco somente se o usuário tocar diretamente
                      _motivoFocus.canRequestFocus = true;
                      _motivoFocus.requestFocus();
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira o motivo da reunião';
                      }
                      return null;
                    },
                  ),

                  // Para o campo de assunto da reunião:
                  TextFormField(
                    controller: _assuntoController,
                    focusNode: _assuntoFocus,
                    autofocus: false,
                    maxLength: 100,
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
                          ? const EdgeInsets.symmetric(vertical: 25)
                          : const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onTap: () {
                      _assuntoFocus.canRequestFocus = true;
                      _assuntoFocus.requestFocus();
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira o assunto da reunião';
                      }
                      return null;
                    },
                  ),
                  // Campo de seleção de data e horário
                  InkWell(
                    onTap: () => _selectDateTime(context),
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
                            ? const EdgeInsets.symmetric(vertical: 25)
                            : const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDate == null
                                ? 'Selecione data e horário'
                                : DateFormat('dd/MM/yyyy HH:mm')
                                .format(_selectedDate!),
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
                  const SizedBox(height: 24),
                  // Botão para salvar a solicitação
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _submitForm,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.add_task,
                            color: Theme.of(context).colorScheme.outline,
                            size: 25,
                          ),
                    label: Text(
                      _isLoading ? 'Processando...' : 'Solicitar reunião',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding:
                          const EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
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
      ),
    );
  }
}