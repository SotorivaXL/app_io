import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomMapPicker/custom_map_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter_map_location_picker/flutter_map_location_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

class RequestRecording extends StatefulWidget {
  const RequestRecording({super.key});

  @override
  State<RequestRecording> createState() => _RequestRecordingState();
}

class _RequestRecordingState extends State<RequestRecording> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _descricaoFocus = FocusNode();
  double _scrollOffset = 0.0;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descricaoController = TextEditingController();

  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  double? _selectedLatitude;
  double? _selectedLongitude;
  bool? _needsScript;
  bool _isPickingLocation = false;
  bool _isLoading = false;

  Key _mapKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _descricaoFocus.canRequestFocus = false;
    _descricaoFocus.addListener(() {
      if (!_descricaoFocus.hasFocus) {
        _descricaoFocus.canRequestFocus = false;
      }
    });
  }

  final List<DateTime> _holidays = [
    DateTime(2025, 1, 1),
    DateTime(2025, 4, 18),
    DateTime(2025, 4, 21),
    DateTime(2025, 5, 1),
    DateTime(2025, 6, 19),
    DateTime(2025, 9, 7),
    DateTime(2025, 10, 12),
    DateTime(2025, 11, 2),
    DateTime(2025, 11, 15),
    DateTime(2025, 11, 20),
    DateTime(2025, 11, 28),
    DateTime(2025, 12, 25),
  ];

  Future<DateTime?> _pickDateTime(BuildContext context) async {
    final DateTime today = DateTime.now();
    DateTime initialDate = today;
    DateTime firstDate = today;
    DateTime lastDate = DateTime(today.year + 1);

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
                  if (date.weekday < DateTime.monday || date.weekday > DateTime.friday) {
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
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Cancelar", style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(initialDate),
              child: Text("OK", style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
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
        return DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          time.hour,
          time.minute,
        );
      }
    }
    return null;
  }

  Future<void> _selectIntervalDateTime() async {
    final pickedStart = await _pickDateTime(context);
    if (pickedStart != null) {
      final pickedEnd = await _pickDateTime(context);
      if (pickedEnd != null) {
        if (pickedStart.isAfter(pickedEnd)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'A data de início deve ser anterior à data de fim.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
        setState(() {
          _selectedStartDate = pickedStart;
          _selectedEndDate = pickedEnd;
        });
      }
    }
  }

  Future<void> _pickLocation() async {
    FocusScope.of(context).unfocus();
    double initialLat;
    double initialLng;

    if (_selectedLatitude != null && _selectedLongitude != null) {
      initialLat = _selectedLatitude!;
      initialLng = _selectedLongitude!;
    } else {
      initialLat = -23.550520;
      initialLng = -46.633308;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse) {
            final Position currentPosition = await Geolocator.getCurrentPosition(
              timeLimit: const Duration(seconds: 10),
            );
            initialLat = currentPosition.latitude;
            initialLng = currentPosition.longitude;
          }
        }
      } catch (e) {
        debugPrint("Erro ao obter localização: $e");
      }
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomMapPicker(
          initialLatitude: initialLat,
          initialLongitude: initialLng,
          onLocationPicked: (lat, lng) {
            setState(() {
              _selectedLatitude = lat;
              _selectedLongitude = lng;
              _mapKey = UniqueKey();
            });
          },
        ),
      ),
    );
  }

  Future<String?> _getCompanyName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final createdBy = userDoc.get('createdBy');
      final empresaDoc = await FirebaseFirestore.instance.collection('empresas').doc(createdBy).get();
      if (empresaDoc.exists) {
        return empresaDoc.get('NomeEmpresa');
      }
    }

    final empresaDocDirect = await FirebaseFirestore.instance.collection('empresas').doc(uid).get();
    if (empresaDocDirect.exists) {
      return empresaDocDirect.get('NomeEmpresa');
    }
    return null;
  }

  Future<void> _submitForm() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();

    if (_formKey.currentState!.validate() &&
        _selectedStartDate != null &&
        _selectedEndDate != null &&
        _selectedLatitude != null &&
        _selectedLongitude != null &&
        _needsScript != null) {

      if (_selectedStartDate!.isAfter(_selectedEndDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A data de início deve ser anterior à data de fim.',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

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

      // Endpoint da Cloud Function
      final String cloudFunctionUrl = 'https://sendmeetingrequesttosqs-5a3yl3wsma-uc.a.run.app';

      final Map<String, dynamic> payload = {
        'descricao': _descricaoController.text.trim(),
        'lat': _selectedLatitude?.toString(),
        'lng': _selectedLongitude?.toString(),
        'dataGravacaoInicio': _selectedStartDate?.toIso8601String(),
        'dataGravacaoFim': _selectedEndDate?.toIso8601String(),
        'precisaRoteiro': _needsScript, // bool
        'nomeEmpresa': nomeEmpresa,
        'tipoSolicitacao': 'Gravação',
        'createdAt': DateTime.now().toIso8601String(),
      };

      try {
        final response = await http.post(
          Uri.parse(cloudFunctionUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          print('Dados enviados com sucesso para o SQS: ${response.body}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Solicitação de gravação enviada com sucesso!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          print('Falha ao enviar dados para o SQS: ${response.body}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Falha ao enviar a solicitação.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      } catch (e) {
        print('Erro ao enviar dados para o SQS: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar solicitação.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }

      setState(() {
        _isLoading = false;
      });

      _formKey.currentState!.reset();
      setState(() {
        _selectedStartDate = null;
        _selectedEndDate = null;
        _selectedLatitude = null;
        _selectedLongitude = null;
        _needsScript = null;
      });
      _descricaoController.clear();

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

  @override
  void dispose() {
    _scrollController.dispose();
    _descricaoController.dispose();
    _descricaoFocus.dispose();
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
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_back_ios_new,
                                    color: Theme.of(context).colorScheme.onBackground, size: 18),
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
                            'Solicitar Gravação',
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
                children: [
                  // Descricao
                  TextFormField(
                    controller: _descricaoController,
                    focusNode: _descricaoFocus,
                    autofocus: false,
                    onTap: () {
                      _descricaoFocus.canRequestFocus = true;
                      _descricaoFocus.requestFocus();
                    },
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Digite a descrição da gravação',
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
                      contentPadding: isDesktop
                          ? const EdgeInsets.symmetric(vertical: 25, horizontal: 16)
                          : const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, insira a descrição da gravação';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Localização
                  InkWell(
                    onTap: _pickLocation,
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      child: Stack(
                        children: [
                          if (_selectedLatitude != null &&
                              _selectedLongitude != null &&
                              !_isPickingLocation)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: GoogleMap(
                                key: _mapKey,
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(_selectedLatitude!, _selectedLongitude!),
                                  zoom: 15,
                                ),
                                markers: {
                                  Marker(
                                    markerId: const MarkerId('selected-location'),
                                    position: LatLng(_selectedLatitude!, _selectedLongitude!),
                                  ),
                                },
                                zoomControlsEnabled: false,
                                myLocationButtonEnabled: false,
                                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{}.toSet(),
                              ),
                            )
                          else
                            Center(
                              child: Text(
                                "Toque para selecionar a localização",
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ),
                          Positioned.fill(child: Container(color: Colors.transparent)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Roteiro
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Column(
                      children: [
                        Text(
                          'A gravação precisará de roteiro?',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<bool>(
                                title: const Text('Sim', style: TextStyle(fontFamily: 'Poppins')),
                                value: true,
                                groupValue: _needsScript,
                                onChanged: (bool? value) {
                                  setState(() {
                                    _needsScript = value;
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<bool>(
                                title: const Text('Não', style: TextStyle(fontFamily: 'Poppins')),
                                value: false,
                                groupValue: _needsScript,
                                onChanged: (bool? value) {
                                  setState(() {
                                    _needsScript = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Data e hora (início e fim)
                  InkWell(
                    onTap: _selectIntervalDateTime,
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
                            (_selectedStartDate == null || _selectedEndDate == null)
                                ? 'Selecione data e hora (início e fim)'
                                : '${DateFormat('dd/MM/yyyy HH:mm').format(_selectedStartDate!)} - '
                                '${DateFormat('dd/MM/yyyy HH:mm').format(_selectedEndDate!)}',
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
                      _isLoading ? 'Processando...' : 'Solicitar gravação',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
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