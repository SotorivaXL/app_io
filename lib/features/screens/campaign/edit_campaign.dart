import 'dart:async';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart'; // Importa showErrorDialog de utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EditCampaignPage extends StatefulWidget {
  final String empresaId;
  final String campanhaId;

  EditCampaignPage({required this.empresaId, required this.campanhaId});

  @override
  _EditCampaignPageState createState() => _EditCampaignPageState();
}

class _EditCampaignPageState extends State<EditCampaignPage> {
  final _formKey = GlobalKey<FormState>();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  // Controladores de Texto para pré-preencher os campos
  late TextEditingController _nomeCampanhaController;
  late TextEditingController _descricaoController;
  late TextEditingController _mensagemController;
  late TextEditingController _dataInicioController;
  late TextEditingController _dataFimController;

  DateTime _dataInicio = DateTime.now();
  DateTime _dataFim = DateTime.now();
  bool _isLoading = false;
  bool _isFetchingData = true;

  // Definição do ScrollController e _scrollOffset
  ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _nomeCampanhaController = TextEditingController();
    _descricaoController = TextEditingController();
    _mensagemController = TextEditingController();
    _dataInicioController = TextEditingController();
    _dataFimController = TextEditingController();

    _fetchCampaignData();

    // Adicionar listener ao ScrollController
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
  }

  @override
  void dispose() {
    _nomeCampanhaController.dispose();
    _descricaoController.dispose();
    _mensagemController.dispose();
    _dataInicioController.dispose();
    _dataFimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCampaignData() async {
    setState(() {
      _isFetchingData = true;
    });

    try {
      DocumentSnapshot<Map<String, dynamic>> campanhaDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('campanhas')
          .doc(widget.campanhaId)
          .get();

      if (campanhaDoc.exists) {
        Map<String, dynamic>? data = campanhaDoc.data();
        if (data != null) {
          _nomeCampanhaController.text = data['nome_campanha'] ?? '';
          _descricaoController.text = data['descricao'] ?? '';
          _mensagemController.text = data['mensagem_padrao'] ?? '';
          _dataInicio = data['dataInicio'] != null
              ? DateTime.parse(data['dataInicio'])
              : DateTime.now();
          _dataFim = data['dataFim'] != null
              ? DateTime.parse(data['dataFim'])
              : DateTime.now();
          _dataInicioController.text = _dateFormat.format(_dataInicio);
          _dataFimController.text = _dateFormat.format(_dataFim);
        }
      } else {
        showErrorDialog(context, 'Campanha não encontrada.', 'Erro');
        Navigator.pop(context);
      }
    } catch (e) {
      print("Erro ao buscar dados da campanha: $e");
      showErrorDialog(context, 'Erro ao buscar dados da campanha.', 'Erro');
      Navigator.pop(context);
    } finally {
      setState(() {
        _isFetchingData = false;
      });
    }
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
          _dataInicioController.text = _dateFormat.format(_dataInicio);
        } else {
          _dataFim = picked;
          _dataFimController.text = _dateFormat.format(_dataFim);
        }
      });
    }
  }

  Future<void> _updateCampaign() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      setState(() {
        _isLoading = true;
      });

      try {
        CollectionReference campanhas = FirebaseFirestore.instance
            .collection('empresas')
            .doc(widget.empresaId)
            .collection('campanhas');

        await campanhas.doc(widget.campanhaId).update({
          'nome_campanha': _nomeCampanhaController.text,
          'descricao': _descricaoController.text,
          'mensagem_padrao': _mensagemController.text,
          'dataInicio': _dataInicio.toIso8601String(),
          'dataFim': _dataFim.toIso8601String(),
          'timestamp': FieldValue.serverTimestamp(),
        });

        showErrorDialog(context, 'Campanha atualizada com sucesso!', 'Sucesso');

        Future.delayed(Duration(seconds: 2), () {
          Navigator.pop(context, true); // Retorna true para atualizar a lista
        });
      } catch (e) {
        print("Erro ao atualizar campanha: $e");
        showErrorDialog(context, 'Erro ao atualizar campanha.', 'Erro');
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      // Botão de voltar e título
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
                            'Editar Campanha',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                      // Botão de salvar
                      Stack(
                        children: [
                          _isLoading
                              ? CircularProgressIndicator()
                              : IconButton(
                            icon: Icon(
                              Icons.save_as_sharp,
                              color: Theme.of(context).colorScheme.onBackground,
                              size: 30,
                            ),
                            onPressed: _isLoading ? null : _updateCampaign,
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
        body: _isFetchingData
            ? Center(child: CircularProgressIndicator())
            : GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nome da Campanha
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nome da Campanha',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          SizedBox(height: 8),
                          TextFormField(
                            controller: _nomeCampanhaController,
                            decoration: InputDecoration(
                              hintText: 'Digite o nome da campanha',
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.secondary,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: Icon(
                                Icons.text_fields,
                                color: Theme.of(context).colorScheme.tertiary,
                                size: 20,
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Por favor, insira o nome da campanha';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    // Descrição
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Descrição',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          SizedBox(height: 8),
                          TextFormField(
                            controller: _descricaoController,
                            decoration: InputDecoration(
                              hintText: 'Digite a descrição',
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.secondary,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: Icon(
                                Icons.text_fields,
                                color: Theme.of(context).colorScheme.tertiary,
                                size: 20,
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Por favor, insira a descrição';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    // Mensagem Padrão
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mensagem Padrão',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          SizedBox(height: 8),
                          TextFormField(
                            controller: _mensagemController,
                            decoration: InputDecoration(
                              hintText: 'Digite a mensagem padrão',
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.secondary,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: Icon(
                                Icons.text_fields,
                                color: Theme.of(context).colorScheme.tertiary,
                                size: 20,
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                      ),
                    ),

                    // Data Início e Data Final
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
                      child: Row(
                        children: [
                          // Data Início
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Data Início',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                SizedBox(height: 8),
                                TextFormField(
                                  controller: _dataInicioController,
                                  decoration: InputDecoration(
                                    hintText: 'Selecione a data de início',
                                    filled: true,
                                    fillColor: Theme.of(context).colorScheme.secondary,
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).primaryColor,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.calendar_today,
                                      color: Theme.of(context).colorScheme.tertiary,
                                      size: 20,
                                    ),
                                  ),
                                  readOnly: true,
                                  onTap: () => _selectDate(context, true),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 20),
                          // Data Final
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Data Final',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                ),
                                SizedBox(height: 8),
                                TextFormField(
                                  controller: _dataFimController,
                                  decoration: InputDecoration(
                                    hintText: 'Selecione a data final',
                                    filled: true,
                                    fillColor: Theme.of(context).colorScheme.secondary,
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).primaryColor,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.calendar_today,
                                      color: Theme.of(context).colorScheme.tertiary,
                                      size: 20,
                                    ),
                                  ),
                                  readOnly: true,
                                  onTap: () => _selectDate(context, false),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 35),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Definição do widget LabelAndField
class LabelAndField extends StatelessWidget {
  final String label;
  final Widget field;

  const LabelAndField({required this.label, required this.field});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        SizedBox(height: 8),
        field,
      ],
    );
  }
}
