import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_io/util/services/firestore_service.dart';

class CreateCampaignPage extends StatefulWidget {
  final String empresaId;

  CreateCampaignPage({required this.empresaId});

  @override
  _CreateCampaignPageState createState() => _CreateCampaignPageState();
}

class _CreateCampaignPageState extends State<CreateCampaignPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  String _nomeCampanha = '';
  String _descricao = '';
  DateTime _dataInicio = DateTime.now();
  DateTime _dataFim = DateTime.now();
  bool _isLoading = false;

  // Dropdown simulation
  String? _selectedEmpresaId;
  List<Map<String, dynamic>> _empresas = [];

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy'); // Date format

  @override
  void initState() {
    super.initState();
    _loadEmpresas();
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _dataInicio : _dataFim,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      locale: Locale('pt', 'BR'),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Theme.of(context).colorScheme.primary,
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              secondary: Theme.of(context).colorScheme.secondary,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.background,
              onSurface: Theme.of(context).colorScheme.onBackground,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.white,
              selectionColor: Colors.grey,
              selectionHandleColor: Colors.white,
            ),
            inputDecorationTheme: InputDecorationTheme(
              labelStyle: TextStyle(color: Colors.white),
              hintStyle: TextStyle(color: Colors.grey),
            ),
            textTheme: TextTheme(
              labelMedium: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _dataInicio = picked;
        } else {
          _dataFim = picked;
        }
      });
    }
  }

  Future<void> _saveCampaign() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      if (_selectedEmpresaId == null) {
        showErrorDialog(context, 'Por favor selecione uma empresa', 'Atenção');
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        print('Dados enviados:');
        print('empresaId: $_selectedEmpresaId');
        print('nome_campanha: $_nomeCampanha');
        print('descricao: $_descricao');
        print('dataInicio: ${_dataInicio.toIso8601String()}');
        print('dataFim: ${_dataFim.toIso8601String()}');

        CollectionReference campanhas = FirebaseFirestore.instance
            .collection('empresas')
            .doc(_selectedEmpresaId)
            .collection('campanhas');

        await campanhas.add({
          'nome_campanha': _nomeCampanha,
          'descricao': _descricao,
          'dataInicio': _dataInicio.toIso8601String(),
          'dataFim': _dataFim.toIso8601String(),
        });

        showErrorDialog(context, 'Campanha criada com sucesso!', 'Sucesso');

        Future.delayed(Duration(seconds: 2), () {
          Navigator.pop(context);
        });
      } catch (e) {
        showErrorDialog(context, 'Erro ao criar campanha', 'Erro');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadEmpresas() async {
    try {
      List<Map<String, dynamic>> empresas = await _firestoreService.getEmpresas();
      setState(() {
        _empresas = empresas;
      });
    } catch (e) {
      showErrorDialog(context, 'Erro ao carregar empresa', 'Erro');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(
          title: Text('Criar Campanha'),
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w900,
            fontSize: 26,
            color: Theme.of(context).colorScheme.outline
          ),
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: Theme.of(context).colorScheme.outline,
              size: 24,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          shadowColor: Theme.of(context).colorScheme.outline,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.outline,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Nome da Campanha',
                                labelStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                                hintText: 'Digite o nome da campanha',
                                hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.tertiary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                prefixIcon: Icon(
                                  Icons.text_fields,
                                  color: Theme.of(context).colorScheme.tertiary,
                                  size: 25,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, insira o nome da campanha';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                _nomeCampanha = value!;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                            child: TextFormField(
                              decoration: InputDecoration(
                                labelText: 'Descrição',
                                labelStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                                hintText: 'Digite a descrição',
                                hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.tertiary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                prefixIcon: Icon(
                                  Icons.text_fields,
                                  color: Theme.of(context).colorScheme.tertiary,
                                  size: 25,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor, insira a descrição';
                                }
                                return null;
                              },
                              onSaved: (value) {
                                _descricao = value!;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                            child: DropdownButtonFormField<String>(
                              value: _selectedEmpresaId,
                              onChanged: (val) {
                                setState(() {
                                  _selectedEmpresaId = val;
                                });
                              },
                              items: _empresas.map((empresa) {
                                return DropdownMenuItem<String>(
                                  value: empresa['id'] as String?,
                                  child: Text(
                                    empresa['NomeEmpresa'] != null
                                        ? empresa['NomeEmpresa'] as String
                                        : 'Nome não disponível',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondary, // Cor do texto do dropdown
                                    ),
                                  ),
                                );
                              }).toList(),
                              decoration: InputDecoration(
                                contentPadding:
                                EdgeInsetsDirectional.fromSTEB(16, 20, 16, 20),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).primaryColor,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.tertiary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.error,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              hint: Text(
                                'Selecione a empresa...',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary, // Cor do hint
                                ),
                              ),
                              dropdownColor: Theme.of(context)
                                  .colorScheme
                                  .background, // Cor de fundo do dropdown
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: TextEditingController(text: _dateFormat.format(_dataInicio)),
                                decoration: InputDecoration(
                                  labelText: 'Data de Início',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Selecione a data de início',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).primaryColor,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.tertiary,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.error,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.error,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.calendar_today,
                                    color: Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                readOnly: true,
                                onTap: () => _selectDate(context, true),
                              ),
                            ),
                            SizedBox(width: 20),
                            Expanded(
                              child: TextFormField(
                                controller: TextEditingController(text: _dateFormat.format(_dataFim)),
                                decoration: InputDecoration(
                                  labelText: 'Data de Fim',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Selecione a data de fim',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).primaryColor,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.tertiary,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.error,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Theme.of(context).colorScheme.error,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.calendar_today,
                                    color: Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                readOnly: true,
                                onTap: () => _selectDate(context, false),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional(0, 0),
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                      child: _isLoading
                          ? CircularProgressIndicator()
                          : ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveCampaign,
                        icon: Icon(
                          Icons.save,
                          color: Theme.of(context).colorScheme.outline,
                          size: 25,
                        ),
                        label: Text(
                          'Salvar Campanha',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
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
                          side: BorderSide(
                            color: Colors.transparent,
                            width: 1,
                          ),
                        ),
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