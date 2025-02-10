import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';

class CreateForm extends StatefulWidget {
  @override
  _CreateFormState createState() => _CreateFormState();
}

class FieldData {
  TextEditingController nameController;
  TextEditingController hintController;
  String mask;
  Color borderColor;
  double borderRadius;
  Color fieldStartColor;
  Color fieldEndColor;

  // (A) NOVA PROPRIEDADE PARA SABER SE O CAMPO É TRAVADO
  bool isLocked;

  FieldData({
    required this.nameController,
    required this.hintController,
    this.mask = '',
    this.borderColor = Colors.deepPurple,
    this.borderRadius = 8.0,
    this.fieldStartColor = Colors.white,
    this.fieldEndColor = Colors.white,
    this.isLocked = false, // false por padrão
  });
}

class _CreateFormState extends State<CreateForm> {
  final FirestoreService _firestoreService = FirestoreService();
  String? _selectedEmpresaId;
  String? _selectedCampanhaId;
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _campanhas = [];
  bool _isLoading = false;

  double _scrollOffset = 0.0;

  List<FieldData> _fields = [];
  TextEditingController _redirectUrlController = TextEditingController();

  // Novo campo para o nome do formulário
  TextEditingController _formNameController = TextEditingController();

  // Botão
  Color _buttonStartColor = Colors.blue;
  Color _buttonEndColor = Colors.blueAccent;
  Color _buttonTextColor = Colors.white;
  double _buttonBorderRadius = 8.0;
  Color _buttonHoverColor = Colors.blueGrey;

  // Campos
  Color _inputFocusColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _loadEmpresas();
  }

  Future<void> _loadEmpresas() async {
    try {
      List<Map<String, dynamic>> empresas = await _firestoreService.getEmpresas();
      setState(() {
        _empresas = empresas;
      });
    } catch (e) {
      showErrorDialog(context, 'Erro ao carregar empresas', 'Erro');
    }
  }

  Future<void> _loadCampanhas(String empresaId) async {
    try {
      List<Map<String, dynamic>> campanhas =
      await _firestoreService.getCampanhas(empresaId);
      setState(() {
        _campanhas = campanhas;
        _selectedCampanhaId = null; // Resetar a campanha quando a empresa muda
      });
    } catch (e) {
      showErrorDialog(context, 'Erro ao carregar campanha', 'Erro');
    }
  }

  void _clearForm() {
    setState(() {
      _selectedEmpresaId = null;
      _selectedCampanhaId = null;
      _fields.clear();
      _redirectUrlController.clear();
      _formNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
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
                                color:
                                    Theme.of(context).colorScheme.onBackground,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Voltar',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  color:
                                      Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Criar Formulário',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ],
                    ),
                    // Botão de adicionar campo
                    IconButton(
                      icon: Icon(
                        Icons.add,
                        color: Theme.of(context).colorScheme.onBackground,
                        size: 30,
                      ),
                      onPressed: _addField, // (B) MANTIVEMOS O MESMO NOME
                    ),
                  ],
                ),
              ),
            ),
            surfaceTintColor: Colors.transparent,
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
          body: SafeArea(
            top: true,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Dropdowns
                  _buildDropdowns(context),

                  // Campo Nome do Formulário
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: isDesktop
                        ? Center(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: 1800), // Largura máxima
                        child: TextFormField(
                          controller: _formNameController,
                          decoration: InputDecoration(
                            hintText: 'Nome do Formulário',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 20.0),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.secondary,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    )
                        : TextFormField(
                      controller: _formNameController,
                      decoration: InputDecoration(
                        hintText: 'Nome do Formulário',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 20.0),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
                    child: isDesktop
                        ? Center(
                      child: Container(
                        constraints: BoxConstraints(maxWidth: 1800), // Largura máxima
                        child: TextFormField(
                          controller: _redirectUrlController,
                          decoration: InputDecoration(
                            hintText: 'URL de Redirecionamento',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 20.0),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.secondary,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                    )
                        : TextFormField(
                      controller: _redirectUrlController,
                      decoration: InputDecoration(
                        hintText: 'URL de Redirecionamento',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 20.0),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Campos dinâmicos
                  _buildDynamicFields(context),

                  // Estilos do botão
                  _buildStyleOptions(context),

                  // Botões
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _generateHtmlForm,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: Text(
                              'Gerar Formulário',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _clearForm,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            label: Text(
                              'Limpar Campos',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildDropdowns(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    return Column(
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                  child: isDesktop
                      ? Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 1800), // Largura máxima
                      child: DropdownButtonFormField<String>(
                        value: _selectedEmpresaId,
                        onChanged: (val) {
                          setState(() {
                            _selectedEmpresaId = val;
                            _loadCampanhas(val!);
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
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.secondary,
                          contentPadding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                          border: UnderlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        hint: Text(
                          'Selecione a empresa...',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        dropdownColor: Theme.of(context).colorScheme.background,
                      ),
                    ),
                  )
                      : DropdownButtonFormField<String>(
                    value: _selectedEmpresaId,
                    onChanged: (val) {
                      setState(() {
                        _selectedEmpresaId = val;
                        _loadCampanhas(val!);
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
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.secondary,
                      contentPadding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                      border: UnderlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    hint: Text(
                      'Selecione a empresa...',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    dropdownColor: Theme.of(context).colorScheme.background,
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
                  child: isDesktop
                      ? Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: 1800), // Largura máxima
                      child: DropdownButtonFormField<String>(
                        value: _selectedCampanhaId,
                        onChanged: (val) {
                          setState(() {
                            _selectedCampanhaId = val;
                          });
                        },
                        items: _campanhas.map((campanha) {
                          final nomeCampanha = campanha['nome_campanha'];
                          return DropdownMenuItem<String>(
                            value: campanha['id'] as String?,
                            child: Text(
                              nomeCampanha != null
                                  ? nomeCampanha as String
                                  : 'Nome não disponível',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.secondary,
                          contentPadding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                          border: UnderlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        hint: Text(
                          'Selecione a campanha...',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        dropdownColor: Theme.of(context).colorScheme.background,
                      ),
                    ),
                  )
                      : DropdownButtonFormField<String>(
                    value: _selectedCampanhaId,
                    onChanged: (val) {
                      setState(() {
                        _selectedCampanhaId = val;
                      });
                    },
                    items: _campanhas.map((campanha) {
                      final nomeCampanha = campanha['nome_campanha'];
                      return DropdownMenuItem<String>(
                        value: campanha['id'] as String?,
                        child: Text(
                          nomeCampanha != null
                              ? nomeCampanha as String
                              : 'Nome não disponível',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.secondary,
                      contentPadding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                      border: UnderlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    hint: Text(
                      'Selecione a campanha...',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    dropdownColor: Theme.of(context).colorScheme.background,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicFields(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    // Função auxiliar para construir o card de cada campo
    Widget buildFieldCard(int index) {
      final fieldData = _fields[index];
      return Card(
        color: Theme.of(context).colorScheme.secondary,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // CAMPO DO NOME
              TextFormField(
                controller: fieldData.nameController,
                readOnly: fieldData.isLocked,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.background,
                  hintText: 'Nome do Campo',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // CAMPO DO HINT
              TextFormField(
                controller: fieldData.hintController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.background,
                  hintText: 'Hint do Campo',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // DROPDOWN MÁSCARA
              DropdownButtonFormField<String>(
                value: fieldData.mask,
                onChanged: fieldData.isLocked
                    ? null
                    : (value) {
                  setState(() {
                    fieldData.mask = value ?? '';
                  });
                },
                dropdownColor: Theme.of(context).colorScheme.background,
                items: [
                  {'label': 'Nenhuma', 'value': ''},
                  {'label': 'Telefone', 'value': 'phone'},
                  {'label': 'CPF', 'value': 'cpf'},
                  {'label': 'CNPJ', 'value': 'cnpj'},
                  {'label': 'Data', 'value': 'date'},
                  {'label': 'Email', 'value': 'email'},
                ].map((maskOption) {
                  return DropdownMenuItem<String>(
                    value: maskOption['value'],
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Text(
                        maskOption['label']!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.background,
                  hintText: 'Máscara',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // GRADIENTE
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gradiente',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _pickFieldStartColor(index),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _fields[index].fieldStartColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _pickFieldEndColor(index),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _fields[index].fieldEndColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ÍCONE DE DELETAR
              Center(
                child: IconButton(
                  icon: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _removeField(index),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!isDesktop) {
      // Layout mobile: os cards ocupam toda a largura disponível e têm altura flexível.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: List.generate(_fields.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: buildFieldCard(index),
            );
          }),
        ),
      );
    } else {
      // Layout desktop: usa grid com 4 colunas.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 61),
        child: GridView.builder(
          shrinkWrap: true, // Evita conflitos com o SingleChildScrollView
          physics: const NeverScrollableScrollPhysics(), // Desabilita o scroll interno
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, // 4 campos por linha no desktop
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _fields.length,
          itemBuilder: (context, index) {
            return buildFieldCard(index);
          },
        ),
      );
    }
  }

  Widget _buildStyleOptions(BuildContext context) {
    return kIsWeb ? Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 55),
      child: Card(
        color: Theme.of(context).colorScheme.secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 3,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                'Estilo do Botão',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Gradiente do Botão',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _pickButtonStartColor,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _buttonStartColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _pickButtonEndColor,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _buttonEndColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Cor do Texto do Botão',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: _pickButtonTextColor,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _buttonTextColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Cor de Hover do Botão',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: _pickButtonHoverColor,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _buttonHoverColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Cor de Foco dos Campos',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: _pickInputFocusColor,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _inputFocusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: 4.0, horizontal: 4.5),
                  child: TextField(
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    maxLength: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.background,
                      hintText: 'Arredondamento da Borda (ex: 8.0)',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 20.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      counterText: '',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _buttonBorderRadius = double.tryParse(value) ?? 8.0;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    ) :
      Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        color: Theme.of(context).colorScheme.secondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 3,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                'Estilo do Botão',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Gradiente do Botão',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _pickButtonStartColor,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _buttonStartColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _pickButtonEndColor,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _buttonEndColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Cor do Texto do Botão',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: _pickButtonTextColor,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _buttonTextColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Cor de Hover do Botão',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: _pickButtonHoverColor,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _buttonHoverColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 0.2, horizontal: 6),
                  child: ListTile(
                    title: Text(
                      'Cor de Foco dos Campos',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: _pickInputFocusColor,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _inputFocusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: 4.0, horizontal: 4.5),
                  child: TextField(
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    maxLength: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.background,
                      hintText: 'Arredondamento da Borda (ex: 8.0)',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 20.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      counterText: '',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _buttonBorderRadius = double.tryParse(value) ?? 8.0;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  // (E) MESMA FUNÇÃO _addField(), MAS COM A LÓGICA PARA CRIAR 3 CAMPOS SE A LISTA ESTIVER VAZIA
  void _addField() {
    setState(() {
      if (_fields.isEmpty) {
        // Cria 3 campos "fixos": nome, whatsapp, email
        _fields.addAll([
          FieldData(
            nameController: TextEditingController(text: 'nome'),
            hintController: TextEditingController(text: 'Digite seu nome'),
            mask: '', // sem máscara
            isLocked: true, // travado
          ),
          FieldData(
            nameController: TextEditingController(text: 'whatsapp'),
            hintController: TextEditingController(text: 'Digite seu WhatsApp'),
            mask: 'phone', // máscara de telefone
            isLocked: true, // travado
          ),
          FieldData(
            nameController: TextEditingController(text: 'email'),
            hintController: TextEditingController(text: 'digite seu E-mail'),
            mask: 'email', // máscara de email
            isLocked: true, // travado
          ),
        ]);
      } else {
        // Caso contrário, cria só 1 campo padrão
        _fields.add(
          FieldData(
            nameController: TextEditingController(),
            hintController: TextEditingController(),
          ),
        );
      }
    });
  }

  void _removeField(int index) {
    setState(() {
      _fields.removeAt(index);
    });
  }

  Future<void> _pickBorderColor(int index) async {
    Color pickedColor = _fields[index].borderColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor da Borda"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _fields[index].borderColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickFieldStartColor(int index) async {
    Color pickedColor = _fields[index].fieldStartColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor Inicial do Gradiente do Campo"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _fields[index].fieldStartColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickFieldEndColor(int index) async {
    Color pickedColor = _fields[index].fieldEndColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor Final do Gradiente do Campo"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _fields[index].fieldEndColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickButtonStartColor() async {
    Color pickedColor = _buttonStartColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor Inicial do Gradiente do Botão"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _buttonStartColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickButtonEndColor() async {
    Color pickedColor = _buttonEndColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor Final do Gradiente do Botão"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _buttonEndColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickButtonTextColor() async {
    Color pickedColor = _buttonTextColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor do Texto do Botão"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _buttonTextColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickButtonHoverColor() async {
    Color pickedColor = _buttonHoverColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor de Hover do Botão"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _buttonHoverColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickInputFocusColor() async {
    Color pickedColor = _inputFocusColor;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text("Escolha a Cor de Foco dos Campos"),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                pickedColor = color;
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text(
                "Cancelar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(
                "Selecionar",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              onPressed: () {
                setState(() {
                  _inputFocusColor = pickedColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _generateHtmlForm() async {
    if (_selectedEmpresaId == null ||
        _selectedCampanhaId == null ||
        _redirectUrlController.text.isEmpty ||
        _formNameController.text.isEmpty) {
      showErrorDialog(
          context,
          'Por favor selecione uma empresa, uma campanha, insira o nome do formulário e a URL de redirecionamento!',
          'Atenção');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String webhookUrl =
          "https://us-central1-app-io-1c16f.cloudfunctions.net/addLead";

      String maskScripts = '';
      String fieldsHtml = '';

      // ----------------------------------------------------------------
      // (1) STRING AUXILIAR PARA ARMAZENAR IDS DE CAMPOS COM mask == 'phone'
      // ----------------------------------------------------------------
      String phoneFieldsJS = '';

      for (int i = 0; i < _fields.length; i++) {
        FieldData fieldData = _fields[i];
        String fieldName = fieldData.nameController.text.isNotEmpty
            ? fieldData.nameController.text
            : 'campo_${i + 1}';

        // Determinar o tipo de input
        String inputType = 'text';
        if (fieldData.mask == 'email') {
          inputType = 'email';
        }

        if (fieldData.mask.isNotEmpty) {
          String maskFunctionName = 'applyMask${i}';
          String maskScript = '';
          if (fieldData.mask == 'phone') {
            maskScript = '''
        function $maskFunctionName(input) {
          var x = input.value.replace(/\\D/g, '');
          x = x.substring(0, 11);
          var formatted = '';
          if (x.length > 0) {
            if (x.length <= 2) {
              formatted = '(' + x;
            } else if (x.length <= 7) {
              formatted = '(' + x.substring(0,2) + ') ' + x.substring(2);
            } else {
              formatted = '(' + x.substring(0,2) + ') ' + x.substring(2,7) + '-' + x.substring(7);
            }
          }
          input.value = formatted;
        }
        ''';

            // ----------------------------------------------------------------
            // (2) SE FOR TELEFONE, ADICIONAMOS ESTE ID NO ARRAY phoneFieldsJS
            // ----------------------------------------------------------------
            phoneFieldsJS += "'$fieldName',";

          } else if (fieldData.mask == 'cpf') {
            maskScript = '''
        function $maskFunctionName(input) {
          var x = input.value.replace(/\\D/g, '');
          x = x.substring(0, 11);
          var formatted = '';
          if (x.length > 0) {
            if (x.length <= 3) {
              formatted = x;
            } else if (x.length <= 6) {
              formatted = x.substring(0,3) + '.' + x.substring(3);
            } else if (x.length <= 9) {
              formatted = x.substring(0,3) + '.' + x.substring(3,6) + '.' + x.substring(6);
            } else {
              formatted = x.substring(0,3) + '.' + x.substring(3,6) + '.' + x.substring(6,9) + '-' + x.substring(9);
            }
          }
          input.value = formatted;
        }
        ''';
          } else if (fieldData.mask == 'cnpj') {
            maskScript = '''
        function $maskFunctionName(input) {
          var x = input.value.replace(/\\D/g, '');
          x = x.substring(0, 14);
          var formatted = '';
          if (x.length > 0) {
            if (x.length <= 2) {
              formatted = x;
            } else if (x.length <= 5) {
              formatted = x.substring(0,2) + '.' + x.substring(2);
            } else if (x.length <= 8) {
              formatted = x.substring(0,2) + '.' + x.substring(2,5) + '.' + x.substring(5);
            } else if (x.length <= 12) {
              formatted = x.substring(0,2) + '.' + x.substring(2,5) + '.' + x.substring(5,8) + '/' + x.substring(8);
            } else {
              formatted = x.substring(0,2) + '.' + x.substring(2,5) + '.' + x.substring(5,8) + '/' + x.substring(8,12) + '-' + x.substring(12);
            }
          }
          input.value = formatted;
        }
        ''';
          } else if (fieldData.mask == 'date') {
            maskScript = '''
        function $maskFunctionName(input) {
          var x = input.value.replace(/\\D/g, '');
          x = x.substring(0, 8);
          var formatted = '';
          if (x.length > 0) {
            if (x.length <= 2) {
              formatted = x;
            } else if (x.length <= 4) {
              formatted = x.substring(0,2) + '/' + x.substring(2);
            } else {
              formatted = x.substring(0,2) + '/' + x.substring(2,4) + '/' + x.substring(4);
            }
          }
          input.value = formatted;
        }
        ''';
          }
          maskScripts += '<script>$maskScript</script>';
        }

        // Adicionar o atributo 'required' para tornar o campo obrigatório
        String requiredAttribute = 'required';

        // Gerar o campo de input
        String inputField = '''
      <div style="border-radius: ${fieldData.borderRadius}px; padding: 2px; background: linear-gradient(45deg, ${_colorToHex(fieldData.fieldStartColor)}, ${_colorToHex(fieldData.fieldEndColor)});">
        <input type="$inputType" id="$fieldName" name="$fieldName" placeholder="${fieldData.hintController.text}" value="" style="border: none; border-image: linear-gradient(45deg, ${_colorToHex(fieldData.fieldStartColor)}, ${_colorToHex(fieldData.fieldEndColor)}) 1; border-radius: ${fieldData.borderRadius}px; font-family: 'Montserrat', sans-serif; font-size: 16px; padding: 8px; margin: 0; width: 100%; box-sizing: border-box; background-color: white; cursor: pointer;" ${fieldData.mask.isNotEmpty && fieldData.mask != 'email' ? 'oninput="applyMask${i}(this)"' : ''} $requiredAttribute>
      </div>
      <br>
      ''';

        fieldsHtml += inputField;
      }

      // ----------------------------------------------------------------
      // (3) CRIAMOS UM <script> PARA DECLARAR O ARRAY phoneFields NO HTML
      // SOMENTE SE phoneFieldsJS NÃO ESTIVER VAZIO
      // ----------------------------------------------------------------
      String phoneFieldsScript = phoneFieldsJS.isNotEmpty
          ? """
        <script>
          var phoneFields = [ $phoneFieldsJS ];
        </script>
        """
          : "";

      String htmlForm = '''
          <html>
          <head>
            <title>Formulário</title>
            <style>
              @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400&display=swap');
              body { font-family: 'Montserrat', sans-serif; font-size: 16px; }
              input[type="text"] {
                font-family: 'Montserrat', sans-serif;
                font-size: 16px;
                padding: 8px;
                margin-bottom: 8px;
                width: 100%;
                box-sizing: border-box;
              }
              input[type="text"]:focus {
                outline: none;
                border-color: ${_colorToHex(_inputFocusColor)};
              }
              input[type="submit"] {
                background: linear-gradient(45deg, ${_colorToHex(_buttonStartColor)}, ${_colorToHex(_buttonEndColor)});
                border: none;
                border-radius: ${_buttonBorderRadius}px;
                color: ${_colorToHex(_buttonTextColor)};
                font-family: 'Montserrat', sans-serif;
                font-size: 16px;
                padding: 12px;
                width: 100%;
                cursor: pointer;
                margin-top: 16px;
              }
              input[type="submit"]:hover {
                background-color: ${_colorToHex(_buttonHoverColor)};
              }
              /* Estilos para mensagens de erro/sucesso */
      .message {
        max-width: 400px;
        margin: 10px auto;
        padding: 10px;
        border-radius: 8px;
        text-align: center;
        display: none;
      }
      .message.success {
        background-color: #d4edda;
        color: #155724;
        border: 1px solid #c3e6cb;
      }
      .message.error {
        background-color: #f8d7da;
        color: #721c24;
        border: 1px solid #f5c6cb;
      }
            </style>
            $maskScripts
            $phoneFieldsScript  <!-- AQUI ESTÁ O SCRIPT PARA DECLARAR phoneFields -->
          </head>
          <body>
            <form id="leadForm">
              <input type="hidden" name="empresa_id" value="$_selectedEmpresaId">
              <input type="hidden" name="nome_campanha" value="$_selectedCampanhaId">
              <input type="hidden" name="redirect_url" value="${_redirectUrlController.text}">
              $fieldsHtml
              <input type="submit" value="Enviar Formulário">
            </form>
            
            <!-- Mensagens de feedback -->
    <div id="successMessage" class="message success"></div>
    <div id="errorMessage" class="message error"></div>
    
    <script>
      document.addEventListener('DOMContentLoaded', function() {
        const form = document.getElementById('leadForm'); // Seleciona o formulário pelo ID
        const successMessage = document.getElementById('successMessage');
        const errorMessage = document.getElementById('errorMessage');

        if (!form) {
          console.error('Formulário não encontrado!');
          return;
        }
        console.log('Formulário encontrado.');

        form.addEventListener('submit', async function(event) {
          event.preventDefault(); // Evita a submissão padrão do formulário
          console.log('Evento de submissão interceptado.');

          const submitBtn = form.querySelector('input[type="submit"], button[type="submit"]');
          if (submitBtn) {
            submitBtn.disabled = true;
            if (submitBtn.tagName.toLowerCase() === 'input') {
              submitBtn.value = 'Enviando...';
            } else {
              submitBtn.innerText = 'Enviando...';
            }
            console.log('Botão de submissão desabilitado e texto alterado.');
          }

          // Ocultar mensagens anteriores
          successMessage.style.display = 'none';
          errorMessage.style.display = 'none';

          // Coleta os dados do formulário
          const formData = new FormData(form);
          const data = {};
          formData.forEach((value, key) => { data[key] = value });
          console.log('Dados do formulário coletados:', data);

          // ----------------------------------------------------------------
          // (4) VERIFICAÇÃO DO TAMANHO DO TELEFONE NO FORMATO (XX) XXXXX-XXXX
          // ----------------------------------------------------------------
          // Se a variável phoneFields existir, verificamos cada campo
          if (typeof phoneFields !== 'undefined') {
            for (var i = 0; i < phoneFields.length; i++) {
              var phoneValue = document.getElementById(phoneFields[i]).value;
              // Verifica se NÃO tem exatamente 15 caracteres
              if (phoneValue.length !== 15) {
                errorMessage.textContent = 'O telefone deve estar no formato (99) 91234-5678.';
                errorMessage.style.display = 'block';
                console.log('Erro de formatação de telefone em:', phoneFields[i], '->', phoneValue);

                if (submitBtn) {
                  submitBtn.disabled = false;
                  if (submitBtn.tagName.toLowerCase() === 'input') {
                    submitBtn.value = 'Enviar Formulário';
                  } else {
                    submitBtn.innerText = 'Enviar Formulário';
                  }
                  console.log('Botão de submissão reabilitado após erro de formatação de telefone.');
                }
                return; // Cancela o envio do form
              }
            }
          }

          try {
            const response = await fetch('$webhookUrl', { // Verifique se esta URL está correta
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
              },
              body: JSON.stringify(data),
            });
            console.log('Requisição enviada. Status:', response.status);

            const result = await response.json();
            console.log('Resposta recebida:', result);

            if (response.ok) {
              // Sucesso: exibe mensagem e redireciona
              successMessage.textContent = result.message;
              successMessage.style.display = 'block';
              console.log('Lead adicionado com sucesso. Redirecionando...');
              window.location.href = result.redirectUrl;
            } else if (response.status === 409) {
              // Duplicata: exibe mensagem de erro e reabilita o botão
              errorMessage.textContent = result.message;
              errorMessage.style.display = 'block';
              console.log('Duplicata detectada:', result.message);
              if (submitBtn) {
                submitBtn.disabled = false;
                if (submitBtn.tagName.toLowerCase() === 'input') {
                  submitBtn.value = 'Enviar Formulário';
                } else {
                  submitBtn.innerText = 'Enviar Formulário';
                }
                console.log('Botão de submissão reabilitado.');
              }
            } else {
              // Outros erros: exibe mensagem de erro e reabilita o botão
              errorMessage.textContent = result.message || 'Houve um erro ao enviar o formulário. Por favor, tente novamente.';
              errorMessage.style.display = 'block';
              console.log('Erro ao enviar formulário:', result.message);
              if (submitBtn) {
                submitBtn.disabled = false;
                if (submitBtn.tagName.toLowerCase() === 'input') {
                  submitBtn.value = 'Enviar Formulário';
                } else {
                  submitBtn.innerText = 'Enviar Formulário';
                }
                console.log('Botão de submissão reabilitado após erro.');
              }
            }
          } catch (error) {
            console.error('Erro na requisição:', error);
            errorMessage.textContent = 'Houve um erro ao enviar o formulário. Por favor, tente novamente.';
            errorMessage.style.display = 'block';
            if (submitBtn) {
              submitBtn.disabled = false;
              if (submitBtn.tagName.toLowerCase() === 'input') {
                submitBtn.value = 'Enviar Formulário';
              } else {
                submitBtn.innerText = 'Enviar Formulário';
              }
              console.log('Botão de submissão reabilitado após erro na requisição.');
            }
          }
        });
      });
    </script>
          </body>
          </html>
          ''';

      // Salvar os dados do formulário no Firestore
      Map<String, dynamic> formData = {
        'empresa_id': _selectedEmpresaId,
        'campanha_id': _selectedCampanhaId,
        'form_name': _formNameController.text, // Novo campo
        'redirect_url': _redirectUrlController.text,
        'html_form': htmlForm,
        'fields': _fields.map((field) {
          return {
            'name': field.nameController.text,
            'hint': field.hintController.text,
            'mask': field.mask,
            'borderColor': _colorToHex(field.borderColor),
            'borderRadius': field.borderRadius,
            'fieldStartColor': _colorToHex(field.fieldStartColor),
            'fieldEndColor': _colorToHex(field.fieldEndColor),
          };
        }).toList(),
        'buttonStartColor': _colorToHex(_buttonStartColor),
        'buttonEndColor': _colorToHex(_buttonEndColor),
        'buttonTextColor': _colorToHex(_buttonTextColor),
        'buttonBorderRadius': _buttonBorderRadius,
        'buttonHoverColor': _colorToHex(_buttonHoverColor),
        'inputFocusColor': _colorToHex(_inputFocusColor),
        'timestamp': FieldValue.serverTimestamp(),
      };

      // Referência à coleção 'forms' dentro da campanha selecionada
      CollectionReference formsCollection = FirebaseFirestore.instance
          .collection('empresas')
          .doc(_selectedEmpresaId)
          .collection('campanhas') // Certifique-se de que o nome está correto
          .doc(_selectedCampanhaId)
          .collection('forms');

      await formsCollection.add(formData);

      Clipboard.setData(ClipboardData(text: htmlForm));
      showErrorDialog(
          context,
          'Formulário HTML gerado e copiado com sucesso para a área de transferência',
          'Sucesso');
    } catch (e) {
      showErrorDialog(context,
          'Falha ao gerar formulário, tente novamente mais tarde!', 'Atenção');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).padLeft(6, '0')}';
  }
}
