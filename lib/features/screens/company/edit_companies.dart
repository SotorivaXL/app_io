import 'package:app_io/util/CustomWidgets/ChangePasswordSheet/change_password_sheet.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCompanyModel/add_company_model.dart';
import 'package:app_io/util/CustomWidgets/CustomCountController/custom_count_controller.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

class EditCompanies extends StatefulWidget {
  final String companyId;
  final String nomeEmpresa;
  final String email;
  final String contract;
  final String cnpj;
  final String founded;
  final int countArtsValue;
  final int countVideosValue;
  final bool dashboard;
  final bool leads;
  final bool gerenciarColaboradores;
  final bool configurarDash;
  final bool criarCampanha;
  final bool criarForm;
  final bool copiarTelefones;
  final bool alterarSenha;

  EditCompanies({
    required this.companyId,
    required this.nomeEmpresa,
    required this.email,
    required this.contract,
    required this.cnpj,
    required this.founded,
    required this.countArtsValue,
    required this.countVideosValue,
    required this.dashboard,
    required this.leads,
    required this.gerenciarColaboradores,
    required this.configurarDash,
    required this.criarCampanha,
    required this.criarForm,
    required this.copiarTelefones,
    required this.alterarSenha,
  });

  @override
  _EditCompaniesState createState() => _EditCompaniesState();
}

class _EditCompaniesState extends State<EditCompanies> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCompanyModel _model;
  bool _isLoading = false;

  double _scrollOffset = 0.0;

  Map<String, bool> accessRights = {
    'dashboard': false,
    'leads': false,
    'gerenciarColaboradores': false,
    'configurarDash': false,
    'criarCampanha': false,
    'criarForm': false,
    'copiarTelefones': false,
    'alterarSenha': false,
  };

  bool _isChangingPassword = false;

  @override
  void initState() {
    super.initState();
    _model = AddCompanyModel();

    // Preenche os controladores de texto e o mapa accessRights com os dados recebidos
    _model.tfCompanyTextController.text = widget.nomeEmpresa;
    _model.tfEmailTextController.text = widget.email;
    _model.tfContractTextController.text = widget.contract;
    _model.tfCnpjTextController.text = widget.cnpj;
    _model.countArtsValue = widget.countArtsValue;
    _model.countVideosValue = widget.countVideosValue;

    final formattedDate = widget.founded.replaceAll('-', '/');
    _model.tfBirthTextController.text = formattedDate;

    accessRights['dashboard'] = widget.dashboard;
    accessRights['leads'] = widget.leads;
    accessRights['gerenciarColaboradores'] = widget.gerenciarColaboradores;
    accessRights['configurarDash'] = widget.configurarDash;
    accessRights['criarCampanha'] = widget.criarCampanha;
    accessRights['criarForm'] = widget.criarForm;
    accessRights['copiarTelefones'] = widget.copiarTelefones;
    accessRights['alterarSenha'] = widget.alterarSenha;
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

  Future<void> _saveCompany() async {
    if (widget.companyId.isEmpty) {
      showErrorDialog(context, "Falha ao carregar usuário", "Atenção");
      return;
    }

    setState(() {
      _isLoading = true; // Inicia o carregamento
    });

    try {
      // Atualize os dados do colaborador no Firestore
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.companyId)
          .update({
        'NomeEmpresa': _model.tfCompanyTextController.text,
        'contract': _model.tfContractTextController.text,
        'countArtsValue': _model.countArtsValue,
        'countVideosValue': _model.countVideosValue,
        'dashboard': accessRights['dashboard'] ?? false,
        'leads': accessRights['leads'] ?? false,
        'gerenciarColaboradores':
        accessRights['gerenciarColaboradores'] ?? false,
        'configurarDash': accessRights['configurarDash'] ?? false,
        'criarCampanha': accessRights['criarCampanha'],
        'criarForm': accessRights['criarForm'],
        'copiarTelefones': accessRights['copiarTelefones'],
        'alterarSenha': accessRights['alterarSenha'],
      });

      // Volta para a tela anterior
      Navigator.pop(context);

      // Exibe uma mensagem de sucesso
      showErrorDialog(context, "Parceiro atualizado com sucesso!", "Sucesso");
    } catch (e) {
      // Exibe uma mensagem de erro
      showErrorDialog(context, "Erro ao atualizar parceiro", "Erro");
    } finally {
      setState(() {
        _isLoading = false; // Finaliza o carregamento
      });
    }
  }

  void _showChangePasswordSheet() {
    showModalBottomSheet(
      backgroundColor: Theme.of(context).colorScheme.background,
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      builder: (context) {
        return ChangePasswordSheet(
          targetUid: widget.companyId,
          onClose: () {
            setState(() {
              _isChangingPassword = false;
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

    String uid = FirebaseAuth.instance.currentUser?.uid ?? ''; // Obtenha o UID do usuário logado.

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
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Voltar',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
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
                          'Editar Parceiro',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ],
                    ),
                    // Stack na direita
                    Stack(
                      children: [
                        _isLoading
                            ? CircularProgressIndicator()
                            : IconButton(
                          icon: Icon(Icons.save_alt_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onBackground,
                              size: 30),
                          onPressed: _isLoading ? null : _saveCompany,
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
          body: SafeArea(
            top: true,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Exibição da imagem da empresa
                  /*Align(
                    alignment: AlignmentDirectional(0, 0),
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                      child: GestureDetector(
                        onTap: _selectImage,
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Flexible(
                              child: Align(
                                alignment: AlignmentDirectional(0, 0),
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                  ),
                                  child: _selectedImage != null
                                      ? Image.file(
                                    _selectedImage!,
                                    fit: BoxFit.cover,
                                  )
                                      : _imageUrl != null
                                      ? Image.network(
                                    _imageUrl!,
                                    fit: BoxFit.cover,
                                  )
                                      : Image.asset(
                                    'images/icons/icon camera.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),*/
                  // Campo de texto para o nome da empresa
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding:
                              EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.corporate_fare,
                                    color:
                                    Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campo de texto para o email
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding:
                              EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                              child: TextFormField(
                                controller: _model.tfEmailTextController,
                                focusNode: _model.tfEmailFocusNode,
                                autofocus: true,
                                obscureText: false,
                                enabled: false,
                                decoration: InputDecoration(
                                  hintText: 'Digite o email da empresa',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.mail,
                                    color:
                                    Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                                textAlign: TextAlign.start,
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campo de texto para o contrato
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding:
                              EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.import_contacts,
                                    color:
                                    Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
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
                  // Campo de texto para o CNPJ
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding:
                              EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                              child: TextFormField(
                                controller: _model.tfCnpjTextController,
                                focusNode: _model.tfCnpjFocusNode,
                                autofocus: true,
                                obscureText: false,
                                enabled: false,
                                decoration: InputDecoration(
                                  hintText: 'Digite o CNPJ da empresa',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                    letterSpacing: 0,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.contact_emergency_sharp,
                                    color:
                                    Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                                textAlign: TextAlign.start,
                                inputFormatters: [_model.tfCnpjMask],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campo de texto para a data de fundação
                  Padding(
                    padding:
                    EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                  20, 0, 20, 0),
                              child: TextFormField(
                                controller: _model.tfBirthTextController,
                                autofocus: true,
                                obscureText: false,
                                enabled: false,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.secondary,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.calendar_month,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Quantidade de conteúdo semanal: Artes e Vídeos
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                          EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
                          child: Text(
                            'Quantidade de conteúdo semanal:',
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                            overflow: TextOverflow.visible,
                            maxLines: null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campo de incremento para Artes
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        Align(
                          alignment: AlignmentDirectional(-1, 0),
                          child: Padding(
                            padding:
                            EdgeInsetsDirectional.fromSTEB(20, 0, 0, 0),
                            child: Text(
                              'Artes',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                letterSpacing: 0,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondary,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                              0, 0, 20, 0),
                          child: CustomCountController(
                            count: _model.countArtsValue,
                            updateCount: updateCountArts,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campo de incremento para Vídeos
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        Align(
                          alignment: AlignmentDirectional(-1, 0),
                          child: Padding(
                            padding:
                            EdgeInsetsDirectional.fromSTEB(20, 0, 0, 0),
                            child: Text(
                              'Vídeos',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                letterSpacing: 0,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondary,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                              0, 0, 20, 0),
                          child: CustomCountController(
                            count: _model.countVideosValue,
                            updateCount: updateCountVideos,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Acessos da Empresa: Dashboard, Leads, Gerenciar Colaboradores
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                          EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                          child: Text(
                            'Marque os acessos da empresa:',
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                            overflow: TextOverflow.visible,
                            maxLines: null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Checkbox para os acessos
                  Padding(
                    padding: EdgeInsetsDirectional.zero,
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: Text(
                            "Dashboard",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['dashboard'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['dashboard'] = value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['leads'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['leads'] = value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
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
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['gerenciarColaboradores'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['gerenciarColaboradores'] =
                                  value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
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
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['configurarDash'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['configurarDash'] =
                                  value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['criarForm'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['criarForm'] = value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['criarCampanha'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['criarCampanha'] =
                                  value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['copiarTelefones'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['copiarTelefones'] =
                                  value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                          value: accessRights['alterarSenha'],
                          onChanged: (bool? value) {
                            setState(() {
                              accessRights['alterarSenha'] =
                                  value ?? false;
                            });
                          },
                          controlAffinity:
                          ListTileControlAffinity.leading,
                          activeColor: Theme.of(context).primaryColor,
                          checkColor:
                          Theme.of(context).colorScheme.outline,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5.0),
                          ),
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('empresas')
                        .doc(uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return CircularProgressIndicator();
                      }

                      if (snapshot.hasError) {
                        return Text('Erro ao carregar dados');
                      }

                      if (snapshot.hasData &&
                          snapshot.data != null &&
                          snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map<String, dynamic>?;

                        bool canChangePassword = data?['alterarSenha'] ?? false;

                        if (canChangePassword) {
                          return Align(
                            alignment: AlignmentDirectional(0, 0),
                            child: Padding(
                              padding:
                              EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
                              child: ElevatedButton.icon(
                                onPressed: _isChangingPassword
                                    ? null
                                    : _showChangePasswordSheet,
                                icon: Icon(
                                  Icons.settings_backup_restore_rounded,
                                  color: Theme.of(context).colorScheme.outline,
                                  size: 25,
                                ),
                                label: Text(
                                  'Alterar senha',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsetsDirectional.fromSTEB(
                                      30, 15, 30, 15),
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
                          );
                        }
                      }
                      return SizedBox.shrink(); // Não exibe nada se não tiver permissão ou se o documento não existir.
                    },
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}