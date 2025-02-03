import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCompanyModel/add_company_model.dart';
import 'package:app_io/util/CustomWidgets/CustomCountController/custom_count_controller.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:flutter_holo_date_picker/flutter_holo_date_picker.dart';

class AddCompany extends StatefulWidget {
  @override
  _AddCompanyState createState() => _AddCompanyState();
}

class _AddCompanyState extends State<AddCompany> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCompanyModel _model;
  String? userId;
  bool _isLoading = false;
  double _scrollOffset = 0.0;

  // Inicializa o mapa para armazenar os direitos de acesso
  Map<String, bool> accessRights = {
    'dashboard': false,
    'leads': false,
    'gerenciarColaboradores': false,
    'gerenciarParceiros': false,
    'configurarDash': false,
    'criarForm': false,
    'criarCampanha': false,
    'copiarTelefones': false,
    'alterarSenha': false,
  };

  @override
  void initState() {
    super.initState();
    _model = AddCompanyModel();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void updateCountArts(int newCount) {
    setState(() {
      _model.countArtsValue = newCount;
    });
  }

  void updateCountVideos(int newCount) {
    setState(() {
      _model.countVideosValue = newCount;
    });
  }

  Future<void> _addCompany() async {
    if (_model.tfPasswordTextController.text !=
        _model.tfPasswordConfirmTextController.text) {
      showErrorDialog(context, "As senhas são diferentes", "Atenção");
      return;
    }

    setState(() {
      _isLoading = true; // Inicia o carregamento
    });

    try {
      final HttpsCallable callable =
      FirebaseFunctions.instance.httpsCallable('createUserAndCompany');
      final result = await callable.call({
        'email': _model.tfEmailTextController?.text ?? '',
        'password': _model.tfPasswordTextController?.text ?? '',
        'nomeEmpresa': _model.tfCompanyTextController?.text ?? '',
        'contract': _model.tfContractTextController?.text ?? '',
        'cnpj': _model.tfCnpjTextController?.text ?? '',
        'founded': _model.tfBirthTextController?.text ?? '',
        'accessRights': accessRights,
        'countArtsValue': _model.countArtsValue,
        'countVideosValue': _model.countVideosValue,
      });

      if (result.data['success']) {
        Navigator.pop(context);
        // Exibe uma mensagem de sucesso
        showErrorDialog(context, "Parceiro adicionado com sucesso!", "Sucesso");
      }
    } catch (e) {
      // Exibe uma mensagem de erro
      showErrorDialog(context, "Falha ao adicionar parceiro", "Atenção");
    } finally {
      setState(() {
        _isLoading = false; // Finaliza o carregamento
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1) Detecta se é desktop pela largura, por exemplo > 1024
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

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
                          'Adicionar Parceiro',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ],
                    ),
                    // Ícone na direita (salvar)
                    Stack(
                      children: [
                        _isLoading
                            ? CircularProgressIndicator()
                            : IconButton(
                          icon: Icon(Icons.save_as_sharp,
                              color: Theme.of(context).colorScheme.onBackground,
                              size: 30),
                          onPressed: _isLoading ? null : _addCompany,
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

          // 2) Define o body com base em isDesktop
          // Se for desktop, envolvemos o conteúdo em Center + Container
          body: isDesktop
              ? Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: 1850),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: _buildMainContent(context),
                ),
              ),
            ),
          )
              : SafeArea(
            child: SingleChildScrollView(
              child: _buildMainContent(context),
            ),
          ),
        ),
      ),
    );
  }

  /// 3) Extraímos todo o conteúdo principal para facilitar a leitura.
  ///    Essa função apenas retorna o "Column" com todos os campos.
  Widget _buildMainContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        // Campo Nome da Empresa
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional(0, 0),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: TextFormField(
                      controller: _model.tfCompanyTextController,
                      focusNode: _model.tfCompanyFocusNode,
                      autofocus: true,
                      obscureText: false,
                      decoration: InputDecoration(
                        hintText: 'Digite o nome da empresa',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          letterSpacing: 0,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        prefixIcon: Icon(
                          Icons.corporate_fare,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      textInputAction: TextInputAction.next,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Campo Email
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional(0, 0),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: TextFormField(
                      controller: _model.tfEmailTextController,
                      focusNode: _model.tfEmailFocusNode,
                      autofocus: true,
                      obscureText: false,
                      decoration: InputDecoration(
                        hintText: 'Digite o email da empresa',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          letterSpacing: 0,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          Icons.mail,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 20,
                        ),
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      textInputAction: TextInputAction.next,
                      textAlign: TextAlign.start,
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Campo Data Final do Contrato
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional(0, 0),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: TextFormField(
                      controller: _model.tfContractTextController,
                      focusNode: _model.tfContractFocusNode,
                      autofocus: true,
                      obscureText: false,
                      decoration: InputDecoration(
                        hintText: 'Digite a data final do contrato',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          letterSpacing: 0,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          Icons.import_contacts,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 20,
                        ),
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      textInputAction: TextInputAction.next,
                      textAlign: TextAlign.start,
                      inputFormatters: [_model.tfContractMask],
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
        // Campo CNPJ
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional(0, 0),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: TextFormField(
                      controller: _model.tfCnpjTextController,
                      focusNode: _model.tfCnpjFocusNode,
                      autofocus: true,
                      obscureText: false,
                      decoration: InputDecoration(
                        hintText: 'Digite o CNPJ da empresa',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          letterSpacing: 0,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          Icons.contact_emergency_sharp,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 20,
                        ),
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.start,
                      inputFormatters: [_model.tfCnpjMask],
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Campo de Data de Abertura (com DatePicker)
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional(0, 0),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: GestureDetector(
                      onTap: () async {
                        await showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(25),
                            ),
                          ),
                          builder: (BuildContext context) {
                            DateTime selectedDate = DateTime.now();

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: MediaQuery.of(context).viewInsets.bottom,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondary,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(25),
                                  ),
                                ),
                                height: 300,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(
                                        "Selecione a Data de Abertura",
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: DatePickerWidget(
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime.now(),
                                        dateFormat: "dd-MMMM-yyyy",
                                        locale: DateTimePickerLocale.pt_br,
                                        looping: false,
                                        pickerTheme: DateTimePickerTheme(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .secondary, // Fundo
                                          itemTextStyle: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary, // Cor do texto
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          dividerColor: Theme.of(context)
                                              .colorScheme
                                              .onSecondary, // Cor do divisor
                                        ),
                                        onChange: (date, _) {
                                          setState(() {
                                            selectedDate = date;
                                          });
                                        },
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsetsDirectional.fromSTEB(
                                          0, 0, 0, 30),
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          foregroundColor: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _model.tfBirthTextController.text =
                                            "${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}";
                                          });
                                          Navigator.pop(context);
                                        },
                                        child: Text(
                                          "Confirmar",
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                      child: AbsorbPointer(
                        child: TextFormField(
                          controller: _model.tfBirthTextController,
                          decoration: InputDecoration(
                            hintText: 'Selecione a data de abertura',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                              letterSpacing: 0,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.secondary,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(
                              Icons.calendar_month,
                              color: Theme.of(context).colorScheme.tertiary,
                              size: 20,
                            ),
                          ),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          readOnly: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Campo Senha
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional(0, 0),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: TextFormField(
                      controller: _model.tfPasswordTextController,
                      focusNode: _model.tfPasswordFocusNode,
                      autofocus: true,
                      obscureText: !_model.tfPasswordVisibility,
                      decoration: InputDecoration(
                        hintText: 'Crie uma senha para a empresa',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          letterSpacing: 0,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          Icons.lock,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 20,
                        ),
                        suffixIcon: InkWell(
                          onTap: () => setState(
                                () =>
                            _model.tfPasswordVisibility =
                            !_model.tfPasswordVisibility,
                          ),
                          focusNode: FocusNode(skipTraversal: true),
                          child: Icon(
                            _model.tfPasswordVisibility
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Theme.of(context).colorScheme.tertiary,
                            size: 20,
                          ),
                        ),
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      textInputAction: TextInputAction.next,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Campo Confirmar Senha
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional(0, 0),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                    child: TextFormField(
                      controller: _model.tfPasswordConfirmTextController,
                      focusNode: _model.tfPasswordConfirmFocusNode,
                      autofocus: true,
                      obscureText: !_model.tfPasswordConfirmVisibility,
                      decoration: InputDecoration(
                        hintText: 'Confirme a senha da empresa',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          letterSpacing: 0,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          Icons.lock,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 20,
                        ),
                        suffixIcon: InkWell(
                          onTap: () => setState(
                                () => _model.tfPasswordConfirmVisibility =
                            !_model.tfPasswordConfirmVisibility,
                          ),
                          focusNode: FocusNode(skipTraversal: true),
                          child: Icon(
                            _model.tfPasswordConfirmVisibility
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Theme.of(context).colorScheme.tertiary,
                            size: 20,
                          ),
                        ),
                      ),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      textInputAction: TextInputAction.next,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Quantidade de conteúdo semanal
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
                child: Text(
                  'Quantidade de conteúdo semanal:',
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  overflow: TextOverflow.visible,
                  maxLines: null,
                ),
              ),
            ],
          ),
        ),
        // Artes
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Align(
                alignment: AlignmentDirectional(-1, 0),
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(30, 0, 0, 0),
                  child: Text(
                    'Artes',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      letterSpacing: 0,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 20, 0),
                child: CustomCountController(
                  count: _model.countArtsValue,
                  updateCount: updateCountArts,
                ),
              ),
            ],
          ),
        ),
        // Vídeos
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Align(
                alignment: AlignmentDirectional(-1, 0),
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(30, 0, 0, 0),
                  child: Text(
                    'Vídeos',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      letterSpacing: 0,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(0, 0, 20, 0),
                child: CustomCountController(
                  count: _model.countVideosValue,
                  updateCount: updateCountVideos,
                ),
              ),
            ],
          ),
        ),
        // Acessos da empresa
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
                child: Text(
                  'Marque os acessos da empresa:',
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  overflow: TextOverflow.visible,
                  maxLines: null,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(10, 0, 0, 0),
          child: Column(
            children: [
              CheckboxListTile(
                title: Text(
                  "Dashboard",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['dashboard'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['dashboard'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Leads",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['leads'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['leads'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Gerenciar Colaboradores",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['gerenciarColaboradores'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['gerenciarColaboradores'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Gerenciar Parceiros",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['gerenciarParceiros'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['gerenciarParceiros'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Configurar Dashboard",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['configurarDash'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['configurarDash'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Criar Formulário",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['criarForm'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['criarForm'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Criar Campanha",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['criarCampanha'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['criarCampanha'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Copiar telefones dos Leads",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['copiarTelefones'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['copiarTelefones'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
              CheckboxListTile(
                title: Text(
                  "Alterar senha",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                value: accessRights['alterarSenha'],
                onChanged: (bool? value) {
                  setState(() {
                    accessRights['alterarSenha'] = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Theme.of(context).primaryColor,
                checkColor: Theme.of(context).colorScheme.outline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5.0),
                ),
                dense: true,
              ),
            ],
          ),
        ),
        // Botão "ADICIONAR"
        Align(
          alignment: AlignmentDirectional(0, 0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: AlignmentDirectional(0, 0),
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
                  child: _isLoading
                      ? Center(
                    child: CircularProgressIndicator(),
                  )
                      : ElevatedButton.icon(
                    onPressed: _isLoading ? null : _addCompany,
                    label: Text(
                      'ADICIONAR',
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
                    icon: Icon(
                      Icons.save,
                      color: Theme.of(context).colorScheme.outline,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}
