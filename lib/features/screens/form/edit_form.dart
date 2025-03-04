import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditFormPage extends StatefulWidget {
  final String empresaId;
  final String campanhaId;
  final String formId;

  EditFormPage({
    required this.empresaId,
    required this.campanhaId,
    required this.formId,
  });

  @override
  _EditFormState createState() => _EditFormState();
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

class _EditFormState extends State<EditFormPage> {
  final FirestoreService _firestoreService = FirestoreService();

  // Dropdowns de empresa e campanha – serão exibidos com os valores selecionados anteriormente
  String? _selectedEmpresaId;
  String? _selectedCampanhaId;
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _campanhas = [];

  List<FieldData> _fields = [];
  TextEditingController _formNameController = TextEditingController();
  TextEditingController _redirectUrlController = TextEditingController();

  // Controlador opcional para o arredondamento do botão (se necessário)
  TextEditingController _buttonBorderRadiusController = TextEditingController();

  // Botão
  Color _buttonStartColor = Colors.blue;
  Color _buttonEndColor = Colors.blueAccent;
  Color _buttonTextColor = Colors.white;
  double _buttonBorderRadius = 8.0;
  Color _buttonHoverColor = Colors.blueGrey;

  // Campos
  Color _inputFocusColor = Colors.blue;

  bool _isLoading = true;
  double _scrollOffset = 0.0;

  // Largura máxima para desktop (ajuste conforme necessário)
  final double maxWidth = 1850.0;

  @override
  void initState() {
    super.initState();
    // Inicialmente, carrega as empresas (para o dropdown) e, em seguida, os dados do formulário
    _loadEmpresas().then((_) {
      // Após carregar as empresas, definimos os dropdowns com os valores passados na rota
      setState(() {
        _selectedEmpresaId = widget.empresaId;
      });
      _loadCampanhas(widget.empresaId).then((_) {
        setState(() {
          _selectedCampanhaId = widget.campanhaId;
        });
        _loadFormData();
      });
    });
  }

  Future<void> _loadEmpresas() async {
    try {
      List<Map<String, dynamic>> empresas =
          await _firestoreService.getEmpresas();
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
      });
    } catch (e) {
      showErrorDialog(context, 'Erro ao carregar campanhas', 'Erro');
    }
  }

  Future<void> _loadFormData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      DocumentSnapshot formSnapshot = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('campanhas')
          .doc(widget.campanhaId)
          .collection('forms')
          .doc(widget.formId)
          .get();

      if (formSnapshot.exists) {
        final formData = formSnapshot.data() as Map<String, dynamic>;
        setState(() {
          _formNameController.text = formData['form_name'] ?? '';
          _redirectUrlController.text = formData['redirect_url'] ?? '';
          _buttonBorderRadius =
              (formData['buttonBorderRadius'] as num).toDouble();
          _buttonBorderRadiusController.text =
              _buttonBorderRadius.toStringAsFixed(1);
          _buttonStartColor = Color(int.parse(
              formData['buttonStartColor'].replaceFirst('#', '0xff')));
          _buttonEndColor = Color(
              int.parse(formData['buttonEndColor'].replaceFirst('#', '0xff')));
          _buttonTextColor = Color(
              int.parse(formData['buttonTextColor'].replaceFirst('#', '0xff')));
          _buttonHoverColor = Color(int.parse(
              formData['buttonHoverColor'].replaceFirst('#', '0xff')));
          _inputFocusColor = Color(
              int.parse(formData['inputFocusColor'].replaceFirst('#', '0xff')));

          // Carregar campos dinâmicos
          _fields = (formData['fields'] as List<dynamic>).map((field) {
            return FieldData(
              nameController: TextEditingController(text: field['name']),
              hintController: TextEditingController(text: field['hint']),
              mask: field['mask'] ?? '',
              borderColor: Color(
                  int.parse(field['borderColor'].replaceFirst('#', '0xff'))),
              borderRadius: (field['borderRadius'] as num).toDouble(),
              fieldStartColor: Color(int.parse(
                  field['fieldStartColor'].replaceFirst('#', '0xff'))),
              fieldEndColor: Color(
                  int.parse(field['fieldEndColor'].replaceFirst('#', '0xff'))),
            );
          }).toList();
        });
      } else {
        showErrorDialog(context, 'O formulário não foi encontrado.', 'Erro');
      }
    } catch (e) {
      showErrorDialog(
          context, 'Erro ao carregar os dados do formulário.', 'Erro');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearForm() {
    // Se desejar que a edição permita limpar os campos, implemente a lógica conforme necessário
    // Por exemplo, você pode recarregar os dados originais
    _loadFormData();
  }

  @override
  Widget build(BuildContext context) {
    // Detecta se estamos em desktop
    bool isDesktop = MediaQuery.of(context).size.width > 1024;

    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
            toolbarHeight: 100.0,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                          onTap: () => Navigator.pop(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back_ios_new,
                                  color: Theme.of(context).colorScheme.onBackground,
                                  size: 18),
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
                          'Editar Formulário',
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
                      onPressed: _addField,
                    ),
                    if (_isLoading)
                      CircularProgressIndicator(
                        color: Theme.of(context).primaryColor,
                      ),
                  ],
                ),
              ),
            ),
            surfaceTintColor: Colors.transparent,
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
          body: _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                      color: Theme.of(context).primaryColor),
                )
              : SafeArea(
                  top: true,
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isDesktop ? maxWidth : double.infinity,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 40.0 : 20.0,
                            vertical: 20.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Dropdowns de empresa e campanha
                              _buildDropdowns(context),
                              // Campo: Nome do Formulário
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10.0),
                                child: TextFormField(
                                  controller: _formNameController,
                                  decoration: InputDecoration(
                                    hintText: 'Nome do Formulário',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 20.0),
                                    filled: true,
                                    fillColor:
                                        Theme.of(context).colorScheme.secondary,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                              ),
                              // Campo: URL de Redirecionamento
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 20, top: 10),
                                child: TextFormField(
                                  controller: _redirectUrlController,
                                  decoration: InputDecoration(
                                    hintText: 'URL de Redirecionamento',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 20.0),
                                    filled: true,
                                    fillColor:
                                        Theme.of(context).colorScheme.secondary,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  keyboardType: TextInputType.url,
                                ),
                              ),
                              // Campos dinâmicos
                              _buildDynamicFields(context),
                              // Estilos do botão
                              _buildStyleOptions(context),
                              // Botão para atualizar formulário
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ElevatedButton(
                                  onPressed: _generateHtmlForm,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 15),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                  ),
                                  child: Text(
                                    'Atualizar Formulário',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.outline,
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
                ),
        ),
      ),
    );
  }

  Widget _buildDropdowns(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 1024;

    return Column(
      children: [
        // Dropdown de Empresa
        Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: isDesktop
              ? Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: DropdownButtonFormField<String>(
                      value: _selectedEmpresaId,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedEmpresaId = val;
                            _loadCampanhas(val);
                          });
                        }
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
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        );
                      }).toList(),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20.0, vertical: 15.0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        hintText: 'Selecione a empresa...',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
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
                    if (val != null) {
                      setState(() {
                        _selectedEmpresaId = val;
                        _loadCampanhas(val);
                      });
                    }
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
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    );
                  }).toList(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.secondary,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 15.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'Selecione a empresa...',
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  dropdownColor: Theme.of(context).colorScheme.background,
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: isDesktop
              ? Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: DropdownButtonFormField<String>(
                      value: _selectedCampanhaId,
                      onChanged: (val) {
                        setState(() {
                          _selectedCampanhaId = val;
                        });
                      },
                      items: _campanhas.map((campanha) {
                        return DropdownMenuItem<String>(
                          value: campanha['id'] as String?,
                          child: Text(
                            campanha['nome_campanha'] != null
                                ? campanha['nome_campanha'] as String
                                : 'Nome não disponível',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        );
                      }).toList(),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20.0, vertical: 15.0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        hintText: 'Selecione a campanha...',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
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
                    return DropdownMenuItem<String>(
                      value: campanha['id'] as String?,
                      child: Text(
                        campanha['nome_campanha'] != null
                            ? campanha['nome_campanha'] as String
                            : 'Nome não disponível',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    );
                  }).toList(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.secondary,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 15.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    hintText: 'Selecione a campanha...',
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                  dropdownColor: Theme.of(context).colorScheme.background,
                ),
        ),
      ],
    );
  }

  Widget _buildDynamicFields(BuildContext context) {
    bool isDesktop = MediaQuery.of(context).size.width > 1024;

    Widget buildFieldCard(int index) {
      final fieldData = _fields[index];
      return Card(
        color: Theme.of(context).colorScheme.secondary,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: Column(
            spacing: 10,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    triggerMode: TooltipTriggerMode.tap,
                    richMessage: TextSpan(
                      children: [
                        WidgetSpan(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 200), // Limita a largura
                            child: Text(
                              "Aviso: use '_' no lugar de espaço e letras minúsculas apenas.",
                              style: TextStyle(
                                color: Colors.white, // Cor do texto
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CircleAvatar(
                      backgroundColor: Colors.orange,
                      radius: 12,
                      child: Icon(
                        Icons.warning,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              // Campo: Nome do Campo
              TextFormField(
                controller: fieldData.nameController,
                readOnly: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z_]')),
                ],
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
              // Campo: Hint do Campo
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
              // Campo: Dropdown para Máscara
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
                  {'label': 'Email', 'value': 'email'},
                ].map((maskOption) {
                  return DropdownMenuItem<String>(
                    value: maskOption['value'],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0),
                      child: Text(
                        maskOption['label']!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
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
              // Campo: Arredondamento da Borda
              TextFormField(
                controller: TextEditingController(
                    text: fieldData.borderRadius.toString()),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.background,
                  hintText: 'Ex: 8.0',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  setState(() {
                    fieldData.borderRadius = double.tryParse(value) ?? 8.0;
                  });
                },
              ),
              // Campo: Gradiente do Campo
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
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _pickFieldStartColor(index),
                          child: Container(
                            width: 20,
                            height: 20,
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
                            width: 20,
                            height: 20,
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
              // Ícone de deletar
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
      // Layout mobile: os cards ocupam toda a largura disponível.
      return Container(
        width: MediaQuery.of(context).size.width,
        // Removendo ou reduzindo o padding horizontal para aumentar a largura dos cards
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
      // Layout desktop: exibe os campos em uma grade com 4 colunas.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.25,
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
    // Se desejar o layout similar à página de criação, também utilize um container centralizado com largura máxima
    bool isDesktop = MediaQuery.of(context).size.width > 1024;
    return isDesktop
        ? Center(
            child: Container(
              padding: EdgeInsets.only(top: 15),
              constraints: BoxConstraints(maxWidth: maxWidth),
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Gradiente do Botão',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Cor do Texto do Botão',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Cor de Hover do Botão',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Cor de Foco dos Campos',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                            controller: _buttonBorderRadiusController,
                            keyboardType:
                                TextInputType.numberWithOptions(decimal: true),
                            maxLength: 2,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor:
                                  Theme.of(context).colorScheme.background,
                              hintText: 'Arredondamento da Borda (ex: 8.0)',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 20.0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              counterText: '',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _buttonBorderRadius =
                                    double.tryParse(value) ?? 8.0;
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
            ),
          )
        : Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: maxWidth),
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Gradiente do Botão',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Cor do Texto do Botão',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Cor de Hover do Botão',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 0.2, horizontal: 6),
                          child: ListTile(
                            title: Text(
                              'Cor de Foco dos Campos',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                            controller: _buttonBorderRadiusController,
                            keyboardType:
                                TextInputType.numberWithOptions(decimal: true),
                            maxLength: 2,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor:
                                  Theme.of(context).colorScheme.background,
                              hintText: 'Arredondamento da Borda (ex: 8.0)',
                              hintStyle: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 20.0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              counterText: '',
                            ),
                            onChanged: (value) {
                              setState(() {
                                _buttonBorderRadius =
                                    double.tryParse(value) ?? 8.0;
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
            ),
          );
  }

  void _addField() {
    setState(() {
      // Se desejar manter a lógica de criação de 3 campos fixos na criação inicial, adicione aqui
      // Para a edição, normalmente você já terá os campos carregados e, se necessário, permite adicionar novos
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
          'Por favor, selecione uma empresa, uma campanha, insira o nome do formulário e a URL de redirecionamento!',
          'Atenção');
      return;
    }

    // Validação dos nomes dos campos
    final RegExp validNamePattern = RegExp(r'^[a-z]+(?:_[a-z]+)*$');
    for (int i = 0; i < _fields.length; i++) {
      String fieldName = _fields[i].nameController.text;
      if (!validNamePattern.hasMatch(fieldName)) {
        showErrorDialog(
            context,
            "O nome do campo '$fieldName' é inválido. Use apenas letras minúsculas e separe as palavras com '_' (sem espaços).",
            "Erro de Validação");
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String webhookUrl =
          "https://us-central1-app-io-1c16f.cloudfunctions.net/addLead";

      String maskScripts = '';
      String fieldsHtml = '';

      // Geração dos scripts de máscara e dos campos dinâmicos
      String phoneFieldsJS = '';
      for (int i = 0; i < _fields.length; i++) {
        FieldData fieldData = _fields[i];
        String fieldName = fieldData.nameController.text.isNotEmpty
            ? fieldData.nameController.text
            : 'campo_${i + 1}';
        String inputType =
            fieldData.mask.toLowerCase() == 'email' ? 'email' : 'text';
        if (fieldData.mask.isNotEmpty &&
            fieldData.mask.toLowerCase() != 'email') {
          String maskFunctionName = 'applyMask$i';
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
            phoneFieldsJS += "'$fieldName',";
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
        String requiredAttribute = 'required';
        String inputTypeAttribute = 'type="$inputType"';
        String onInputAttribute = (fieldData.mask.isNotEmpty &&
                fieldData.mask.toLowerCase() != 'email')
            ? 'oninput="applyMask$i(this)"'
            : '';
        String inputField = '''
          <div style="border-radius: ${fieldData.borderRadius}px; padding: 2px; background: linear-gradient(45deg, ${_colorToHex(fieldData.fieldStartColor)}, ${_colorToHex(fieldData.fieldEndColor)});">
            <input $inputTypeAttribute id="$fieldName" name="$fieldName" placeholder="${fieldData.hintController.text}" value="" style="border: none; border-image: linear-gradient(45deg, ${_colorToHex(fieldData.fieldStartColor)}, ${_colorToHex(fieldData.fieldEndColor)}) 1; border-radius: ${fieldData.borderRadius}px; font-family: 'Montserrat', sans-serif; font-size: 16px; padding: 8px; margin: 0; width: 100%; box-sizing: border-box; background-color: white; cursor: pointer;" $onInputAttribute $requiredAttribute>
          </div>
          <br>
        ''';
        fieldsHtml += inputField;
      }

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
            input[type="text"], input[type="email"] {
              font-family: 'Montserrat', sans-serif;
              font-size: 16px;
              padding: 8px;
              margin-bottom: 8px;
              width: 100%;
              box-sizing: border-box;
            }
            input[type="text"]:focus, input[type="email"]:focus {
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
          $phoneFieldsScript
        </head>
        <body>
          <form id="leadForm">
            <input type="hidden" name="empresa_id" value="$_selectedEmpresaId">
            <input type="hidden" name="nome_campanha" value="$_selectedCampanhaId">
            <input type="hidden" name="redirect_url" value="${_redirectUrlController.text}">
            $fieldsHtml
            <input type="submit" value="Enviar Formulário">
          </form>
        </body>
        </html>
      ''';

      Map<String, dynamic> formData = {
        'form_name': _formNameController.text,
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

      // Atualiza o formulário no Firestore
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('campanhas')
          .doc(widget.campanhaId)
          .collection('forms')
          .doc(widget.formId)
          .update(formData);

      Clipboard.setData(ClipboardData(text: htmlForm));
      // Para fechar a página de edição e indicar sucesso, podemos retornar true:
      Navigator.of(context).pop(true);
      showSuccessDialog(
          context,
          'Formulário atualizado com sucesso e copiado para a área de transferência!',
          'Sucesso');
    } catch (e) {
      showErrorDialog(
          context,
          'Falha ao atualizar o formulário. Tente novamente mais tarde.',
          'Erro');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).padLeft(6, '0').toUpperCase()}';
  }

  // Diálogos de sucesso e erro
  void showSuccessDialog(BuildContext context, String message, String title) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text(title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )),
          content: Text(message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
              )),
          actions: [
            TextButton(
              child: Text(
                "OK",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void showErrorDialog(BuildContext context, String message, String title) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text(title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              )),
          content: Text(message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
              )),
          actions: [
            TextButton(
              child: Text(
                "OK",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}
