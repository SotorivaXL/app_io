import 'package:app_io/util/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_io/util/services/firestore_service.dart';

class CreateForm extends StatefulWidget {
  @override
  _CreateFormState createState() => _CreateFormState();
}

class _CreateFormState extends State<CreateForm> {
  final FirestoreService _firestoreService = FirestoreService();
  String? _selectedEmpresaId;
  String? _selectedCampanhaId;
  List<Map<String, dynamic>> _empresas = [];
  List<Map<String, dynamic>> _campanhas = [];
  bool _isLoading = false;

  List<TextEditingController> _controllers = [];
  List<bool> _isPhoneField = [];
  TextEditingController _redirectUrlController =
  TextEditingController(); // Novo controlador

  @override
  void initState() {
    super.initState();
    _loadEmpresas();
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
        _selectedCampanhaId =
        null; // Resetar a campanha selecionada quando a empresa é alterada
      });
    } catch (e) {
      showErrorDialog(context, 'Erro ao carregar campanha', 'Erro');
    }
  }

  void _clearForm() {
    setState(() {
      _selectedEmpresaId = null;
      _selectedCampanhaId = null;
      _controllers.forEach((controller) => controller.clear());
      _controllers.clear();
      _isPhoneField.clear();
      _redirectUrlController.clear(); // Limpar o campo do link
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          iconTheme:
          IconThemeData(color: Theme.of(context).colorScheme.outline),
          automaticallyImplyLeading: true,
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
                    onPressed:
                    null, // Desabilita o botão enquanto carrega
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: 25, vertical: 15),
                      backgroundColor:
                      Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
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
                      padding:
                      EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
                      backgroundColor:
                      Theme.of(context).colorScheme.primary,
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
                        _loadCampanhas(
                            val!); // Carregar campanhas quando a empresa muda
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
                          nomeCampanha != null
                              ? nomeCampanha as String
                              : 'Nome não disponível',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondary, // Cor dos itens do dropdown
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
                      'Selecione a campanha...',
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
      ],
    );
  }

  Widget _buildDynamicFields(BuildContext context) {
    return Column(
      children: _controllers.map((controller) {
        int index = _controllers.indexOf(controller);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Campo ${index + 1}',
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
                ),
              ),
              Checkbox(
                value:
                _isPhoneField.length > index ? _isPhoneField[index] : false,
                onChanged: (value) {
                  setState(() {
                    if (_isPhoneField.length > index) {
                      _isPhoneField[index] = value!;
                    } else {
                      _isPhoneField.add(value!);
                    }
                  });
                },
              ),
              IconButton(
                icon: Icon(Icons.delete,
                    color: Theme.of(context).colorScheme.error),
                onPressed: () => _removeField(index),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _addField() {
    setState(() {
      _controllers.add(TextEditingController());
      _isPhoneField.add(false);
    });
  }

  void _removeField(int index) {
    setState(() {
      _controllers.removeAt(index);
      _isPhoneField
          .removeAt(index); // Remove a configuração de telefone correspondente
    });
  }

  void _generateHtmlForm() async {
    if (_selectedEmpresaId == null || _selectedCampanhaId == null || _redirectUrlController.text.isEmpty) {
      showErrorDialog(context,
          'Por favor selecione uma empresa, uma campanha e insira uma URL de redirecionamento!', 'Atenção');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String webhookUrl =
          "https://us-central1-app-io-1c16f.cloudfunctions.net/addLead";
      final String phoneMaskScript = '''
        <script>
          function applyPhoneMask(input) {
            var x = input.value.replace(/\\D/g, '');
            x = x.match(/(\\d{0,2})(\\d{0,5})(\\d{0,4})/);
            input.value = (!x[2]) ? x[1] : '(' + x[1] + ') ' + x[2] + (x[3] ? '-' + x[3] : '');
          }
        </script>
      ''';

      String fieldsHtml = '';
      for (int i = 0; i < _controllers.length; i++) {
        String fieldName = _controllers[i].text.isNotEmpty
            ? _controllers[i].text
            : 'campo_${i + 1}';
        String inputField = '''
        <input type="text" id="$fieldName" name="$fieldName" placeholder="${_controllers[i].text}" value="" style="border: 2px solid #2196F3; border-radius: 8px; font-family: 'Montserrat', sans-serif; font-size: 16px; padding: 8px; margin-bottom: 8px; width: 100%; box-sizing: border-box;">
        <br>
        ''';

        if (_isPhoneField[i]) {
          inputField = '''
          <input type="text" id="$fieldName" name="$fieldName" placeholder="${_controllers[i].text}" value="" oninput="applyPhoneMask(this)" style="border: 2px solid #2196F3; border-radius: 8px; font-family: 'Montserrat', sans-serif; font-size: 16px; padding: 8px; margin-bottom: 8px; width: 100%; box-sizing: border-box;">
          <br>
          ''';
        }

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
            border: 2px solid #2196F3;
            border-radius: 8px;
            font-family: 'Montserrat', sans-serif;
            font-size: 16px;
            padding: 8px;
            margin-bottom: 8px;
            width: 100%;
            box-sizing: border-box;
          }
          input[type="submit"] {
            background: linear-gradient(45deg, #FF5722, #FF9800);
            border: none;
            border-radius: 8px;
            color: white;
            font-family: 'Montserrat', sans-serif;
            font-size: 16px;
            padding: 12px;
            width: 100%;
            cursor: pointer;
            margin-top: 16px;
          }
        </style>
        $phoneMaskScript
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
      showErrorDialog(
          context,
          'Formulário HTML gerado e copiado com sucesso para a área de transferência',
          'Sucesso');
    } catch (e) {
      showErrorDialog(context, 'Falha ao gerar formulário, tente novamente mais tarde!', 'Atenção');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}