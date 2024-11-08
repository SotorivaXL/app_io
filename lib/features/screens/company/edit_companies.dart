import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCompanyModel/add_company_model.dart';
import 'package:app_io/util/CustomWidgets/CustomCountController/custom_count_controller.dart';
import 'package:app_io/util/services/firestore_service.dart';

class EditCompanies extends StatefulWidget {
  final String companyId;
  final String nomeEmpresa;
  final String email;
  final String contract;
  final String cnpj;
  final int countArtsValue;
  final int countVideosValue;
  final bool dashboard;
  final bool leads;
  final bool gerenciarColaboradores;
  final bool configurarDash;
  final bool criarCampanha;
  final bool criarForm;

  EditCompanies({
    required this.companyId,
    required this.nomeEmpresa,
    required this.email,
    required this.contract,
    required this.cnpj,
    required this.countArtsValue,
    required this.countVideosValue,
    required this.dashboard,
    required this.leads,
    required this.gerenciarColaboradores,
    required this.configurarDash,
    required this.criarCampanha,
    required this.criarForm,
  });

  @override
  _EditCompaniesState createState() => _EditCompaniesState();
}

class _EditCompaniesState extends State<EditCompanies> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCompanyModel _model;
  bool _isLoading = false; // Variável de estado para controlar o carregamento

  Map<String, bool> accessRights = {
    'dashboard': false,
    'leads': false,
    'gerenciarColaboradores': false,
    'configurarDash': false,
    'criarCampanha': false,
    'criarForm': false,
  };

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

    accessRights['dashboard'] = widget.dashboard;
    accessRights['leads'] = widget.leads;
    accessRights['gerenciarColaboradores'] = widget.gerenciarColaboradores;
    accessRights['configurarDash'] = widget.configurarDash;
    accessRights['criarCampanha'] = widget.criarCampanha;
    accessRights['criarForm'] = widget.criarForm;
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
        'gerenciarColaboradores': accessRights['gerenciarColaboradores'] ?? false,
        'configurarDash': accessRights['configurarDash'] ?? false,
        'criarCampanha': accessRights['criarCampanha'],
        'criarForm': accessRights['criarForm'],
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

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          appBar: AppBar(
            backgroundColor: Theme.of(context).primaryColor,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: Theme.of(context).colorScheme.outline,
                size: 24,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text(
              'Editar Parceiro',
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
                              padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                              child: TextFormField(
                                controller: _model.tfCompanyTextController,
                                focusNode: _model.tfCompanyFocusNode,
                                autofocus: true,
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Empresa',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Digite o nome da empresa',
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
                                    Icons.corporate_fare,
                                    color: Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
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
                              padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                              child: TextFormField(
                                controller: _model.tfEmailTextController,
                                focusNode: _model.tfEmailFocusNode,
                                autofocus: true,
                                obscureText: false,
                                enabled: false,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Digite o email da empresa',
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
                                    Icons.mail,
                                    color: Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
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
                              padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                              child: TextFormField(
                                controller: _model.tfContractTextController,
                                focusNode: _model.tfContractFocusNode,
                                autofocus: true,
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Contrato',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Digite a data final do contrato',
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
                                    Icons.import_contacts,
                                    color: Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
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
                              padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                              child: TextFormField(
                                controller: _model.tfCnpjTextController,
                                focusNode: _model.tfCnpjFocusNode,
                                autofocus: true,
                                obscureText: false,
                                enabled: false,
                                decoration: InputDecoration(
                                  labelText: 'CNPJ',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Digite o CNPJ da empresa',
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
                                    Icons.contact_emergency_sharp,
                                    color: Theme.of(context).colorScheme.tertiary,
                                    size: 25,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                  color: Theme.of(context).colorScheme.onSecondary,
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
                  // Quantidade de conteúdo semanal: Artes e Vídeos
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
                  // Campo de incremento para Artes
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Align(
                          alignment: AlignmentDirectional(-1, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(20, 0, 0, 0),
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
                  // Campo de incremento para Vídeos
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Align(
                          alignment: AlignmentDirectional(-1, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(20, 0, 0, 0),
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
                  // Acessos da Empresa: Dashboard, Leads, Gerenciar Colaboradores
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
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
                              fontSize: 14,
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
                            "Configurar Dashboard",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
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
                      ],
                    ),
                  ),
                  // Botão de salvar
                  Align(
                    alignment: AlignmentDirectional(0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Align(
                          alignment: AlignmentDirectional(0, 0),
                          child: Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                            child: _isLoading // Exibe a barra de progresso se estiver carregando
                                ? ElevatedButton(
                              onPressed: null, // Botão desabilitado durante o carregamento
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              child: SizedBox(
                                width: 20,
                                height: 20, // Define o tamanho da ProgressBar
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  strokeWidth: 2.0,
                                ),
                              ),
                            )
                                : ElevatedButton.icon(
                              onPressed: _saveCompany, // Função de salvar
                              icon: Icon(
                                Icons.save_alt,
                                color: Theme.of(context).colorScheme.outline, // Define a cor do ícone
                                size: 25,
                              ),
                              label: Text(
                                'Salvar',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}