import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

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
  FieldData({
    required this.nameController,
    required this.hintController,
    this.mask = '',
    this.borderColor = Colors.deepPurple,
    this.borderRadius = 8.0,
    this.fieldStartColor = Colors.white,
    this.fieldEndColor = Colors.white,
  });
}

class _CreateFormState extends State<CreateForm> {
  final FirestoreService _firestoreService = FirestoreService();
  String? _selectedEmpresaId;
  String? _selectedCampanhaId;
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _campanhas = [];
  bool _isLoading = false;

  List<FieldData> _fields = [];
  TextEditingController _redirectUrlController = TextEditingController();

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
      List<Map<String, dynamic>> campanhas = await _firestoreService.getCampanhas(empresaId);
      setState(() {
        _campanhas = campanhas;
        _selectedCampanhaId = null; // Resetar a campanha selecionada quando a empresa é alterada
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
      _redirectUrlController.clear(); // Limpar o campo do link
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            iconTheme: IconThemeData(color: Theme.of(context).colorScheme.outline),
            title: Text(
              'Criar Formulário',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'BrandingSF',
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
                color: Theme.of(context).colorScheme.outline,
              ),
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
            centerTitle: true,
            elevation: 2,
          ),
          body: SafeArea(
            top: true,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  _buildDropdowns(context),
                  _buildDynamicFields(context),
                  _buildStyleOptions(context),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: TextFormField(
                      controller: _redirectUrlController,
                      decoration: InputDecoration(
                        labelText: 'URL de Redirecionamento',
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
                      keyboardType: TextInputType.url,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: ElevatedButton.icon(
                      onPressed: _addField,
                      icon: Icon(
                        Icons.add,
                        color: Theme.of(context).colorScheme.outline,
                        size: 25,
                      ),
                      label: Text(
                        'Adicionar Campo',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
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
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: _isLoading
                        ? ElevatedButton(
                      onPressed: null, // Desabilita o botão enquanto carrega
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2.0,
                        ),
                      ),
                    )
                        : ElevatedButton(
                      onPressed: _generateHtmlForm,
                      child: Text(
                        'Gerar Formulário HTML',
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
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: ElevatedButton.icon(
                      onPressed: _clearForm,
                      icon: Icon(
                        Icons.clear,
                        color: Theme.of(context).colorScheme.outline,
                        size: 25,
                      ),
                      label: Text(
                        'Limpar Campos',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdowns(BuildContext context) {
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
                  child: DropdownButtonFormField<String>(
                    value: _selectedEmpresaId,
                    onChanged: (val) {
                      setState(() {
                        _selectedEmpresaId = val;
                        _loadCampanhas(val!); // Carregar campanhas quando a empresa muda
                      });
                    },
                    items: _empresas.map((empresa) {
                      return DropdownMenuItem<String>(
                        value: empresa['id'] as String?,
                        child: Text(
                          empresa['NomeEmpresa'] != null ? empresa['NomeEmpresa'] as String : 'Nome não disponível',
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
                      contentPadding: EdgeInsetsDirectional.fromSTEB(16, 20, 16, 20),
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
                          nomeCampanha != null ? nomeCampanha as String : 'Nome não disponível',
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
                      contentPadding: EdgeInsetsDirectional.fromSTEB(16, 20, 16, 20),
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
                      'Selecione a campanha...',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
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
    return Column(
      children: _fields.map((fieldData) {
        int index = _fields.indexOf(fieldData);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                children: [
                  TextFormField(
                    controller: fieldData.nameController,
                    decoration: InputDecoration(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          'Nome do Campo',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedErrorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: fieldData.hintController,
                    decoration: InputDecoration(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          'Hint do Campo',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedErrorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: fieldData.mask,
                    onChanged: (value) {
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
                    ].map((maskOption) {
                      return DropdownMenuItem<String>(
                        value: maskOption['value'],
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10.0),
                          child: Text(
                            maskOption['label']!,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    decoration: InputDecoration(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          'Máscara',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedErrorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    initialValue: fieldData.borderRadius.toString(),
                    decoration: InputDecoration(
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          'Arredondamento da Borda (ex: 8.0)',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedErrorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      setState(() {
                        fieldData.borderRadius = double.tryParse(value) ?? 8.0;
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  ListTile(
                    title: Text(
                      'Gradiente do Campo',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    subtitle: Row(
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
                        SizedBox(width: 10),
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
                  ),
                  const SizedBox(height: 10),
                  IconButton(
                    icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                    onPressed: () => _removeField(index),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStyleOptions(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Divider(),
        Text(
          'Estilos do Formulário',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        ListTile(
          title: Text('Gradiente do Botão'),
          subtitle: Row(
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
              SizedBox(width: 10),
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
        ListTile(
          title: Text('Cor do Texto do Botão'),
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
        ListTile(
          subtitle: TextField(
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            maxLength: 2,
            decoration: InputDecoration(
              label: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.0),
                child: Text(
                  'Arredondamento da Borda (ex: 8.0)',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 8.0),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.tertiary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.tertiary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              errorBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedErrorBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              counterText: '', // Oculta o contador padrão (opcional)
            ),
            onChanged: (value) {
              setState(() {
                _buttonBorderRadius = double.tryParse(value) ?? 8.0;
              });
            },
          ),
        ),
        ListTile(
          title: Text('Cor de Hover do Botão'),
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
        ListTile(
          title: Text('Cor de Foco dos Campos'),
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
      ],
    );
  }

  void _addField() {
    setState(() {
      _fields.add(FieldData(
        nameController: TextEditingController(),
        hintController: TextEditingController(),
      ));
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
                    color: Theme.of(context).colorScheme.onSecondary),
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
                    color: Theme.of(context).colorScheme.outline),
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
        _redirectUrlController.text.isEmpty) {
      showErrorDialog(context,
          'Por favor selecione uma empresa, uma campanha e insira uma URL de redirecionamento!', 'Atenção');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String webhookUrl = "https://us-central1-app-io-1c16f.cloudfunctions.net/addLead";

      String maskScripts = '';
      String fieldsHtml = '';

      for (int i = 0; i < _fields.length; i++) {
        FieldData fieldData = _fields[i];
        String fieldName = fieldData.nameController.text.isNotEmpty ? fieldData.nameController.text : 'campo_${i + 1}';

        if (fieldData.mask.isNotEmpty) {
          String maskFunctionName = 'applyMask${i}';
          String maskScript = '';
          if (fieldData.mask == 'phone') {
            maskScript = '''
            function $maskFunctionName(input) {
              var x = input.value.replace(/\\D/g, '');
              x = x.substring(0, 11);
              var formatted = x.replace(/(\\d{0,2})(\\d{0,5})(\\d{0,4})/, function(match, p1, p2, p3) {
                if (p3) {
                  return '(' + p1 + ') ' + p2 + '-' + p3;
                } else if (p2) {
                  return '(' + p1 + ') ' + p2;
                } else if (p1) {
                  return '(' + p1;
                }
              });
              input.value = formatted;
            }
            ''';
          } else if (fieldData.mask == 'cpf') {
            maskScript = '''
            function $maskFunctionName(input) {
              var x = input.value.replace(/\\D/g, '');
              x = x.substring(0, 11);
              var formatted = x.replace(/(\\d{0,3})(\\d{0,3})(\\d{0,3})(\\d{0,2})/, function(match, p1, p2, p3, p4) {
                var result = '';
                if (p1) result += p1;
                if (p2) result += '.' + p2;
                if (p3) result += '.' + p3;
                if (p4) result += '-' + p4;
                return result;
              });
              input.value = formatted;
            }
            ''';
          } else if (fieldData.mask == 'cnpj') {
            maskScript = '''
            function $maskFunctionName(input) {
              var x = input.value.replace(/\\D/g, '');
              x = x.substring(0, 14);
              var formatted = x.replace(/(\\d{0,2})(\\d{0,3})(\\d{0,3})(\\d{0,4})(\\d{0,2})/, function(match, p1, p2, p3, p4, p5) {
                var result = '';
                if (p1) result += p1;
                if (p2) result += '.' + p2;
                if (p3) result += '.' + p3;
                if (p4) result += '/' + p4;
                if (p5) result += '-' + p5;
                return result;
              });
              input.value = formatted;
            }
            ''';
          } else if (fieldData.mask == 'date') {
            maskScript = '''
            function $maskFunctionName(input) {
              var x = input.value.replace(/\\D/g, '');
              x = x.substring(0, 8);
              var formatted = x.replace(/(\\d{0,2})(\\d{0,2})(\\d{0,4})/, function(match, p1, p2, p3) {
                var result = '';
                if (p1) result += p1;
                if (p2) result += '/' + p2;
                if (p3) result += '/' + p3;
                return result;
              });
              input.value = formatted;
            }
            ''';
          }
          maskScripts += '<script>$maskScript</script>';
        }

        String inputField = '''
        <div style="border-radius: ${fieldData.borderRadius}px; padding: 2px; background: linear-gradient(45deg, ${_colorToHex(fieldData.fieldStartColor)}, ${_colorToHex(fieldData.fieldEndColor)});">
          <input type="text" id="$fieldName" name="$fieldName" placeholder="${fieldData.hintController.text}" value="" style="border: none; border-image: linear-gradient(45deg, ${_colorToHex(fieldData.fieldStartColor)}, ${_colorToHex(fieldData.fieldEndColor)}) 1; border-radius: ${fieldData.borderRadius}px; font-family: 'Montserrat', sans-serif; font-size: 16px; padding: 8px; margin: 0; width: 100%; box-sizing: border-box; background-color: white; cursor: pointer;" ${fieldData.mask.isNotEmpty ? 'oninput="applyMask${i}(this)"' : ''}>
        </div>
        <br>
        ''';

        fieldsHtml += inputField;
      }

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
        </style>
        $maskScripts
      </head>
      <body>
        <form action="$webhookUrl" method="POST" target="_self">
          <input type="hidden" name="empresa_id" value="$_selectedEmpresaId">
          <input type="hidden" name="nome_campanha" value="$_selectedCampanhaId">
          <input type="hidden" name="redirect_url" value="${_redirectUrlController.text}">
          $fieldsHtml
          <input type="submit" value="Enviar Formulário">
        </form>
      </body>
      </html>
      ''';

      Clipboard.setData(ClipboardData(text: htmlForm));
      showErrorDialog(context, 'Formulário HTML gerado e copiado com sucesso para a área de transferência', 'Sucesso');
    } catch (e) {
      showErrorDialog(context, 'Falha ao gerar formulário, tente novamente mais tarde!', 'Atenção');
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