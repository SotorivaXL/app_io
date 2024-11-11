import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCollaboratorModel/add_collaborator_model.dart';
import 'package:app_io/util/services/firestore_service.dart';

class AddCollaborators extends StatefulWidget {
  @override
  _AddCollaboratorsState createState() => _AddCollaboratorsState();
}

class _AddCollaboratorsState extends State<AddCollaborators> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCollaboratorsModel _model;
  String? userId;
  bool _isLoading = false;

  // Inicializa o mapa para armazenar os direitos de acesso
  Map<String, bool> accessRights = {
    'dashboard': false,
    'leads': false,
    'gerenciarColaboradores': false,
    'gerenciarParceiros': false,
    'configurarDash': false,
    'criarForm': false,
    'criarCampanha': false,
  };

  @override
  void initState() {
    super.initState();
    _model = AddCollaboratorsModel();

    _model.tfNameTextController ??= TextEditingController();
    _model.tfNameFocusNode ??= FocusNode();

    _model.tfEmailTextController ??= TextEditingController();
    _model.tfEmailFocusNode ??= FocusNode();

    _model.tfRoleTextController ??= TextEditingController();
    _model.tfRoleFocusNode ??= FocusNode();

    _model.tfPasswordTextController ??= TextEditingController();
    _model.tfPasswordFocusNode ??= FocusNode();

    _model.tfPasswordConfirmTextController ??= TextEditingController();
    _model.tfPasswordConfirmFocusNode ??= FocusNode();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _addCollaborator() async {
    FocusScope.of(context).unfocus();

    if (_model.tfPasswordTextController.text !=
        _model.tfPasswordConfirmTextController.text) {
      showErrorDialog(context, "As senhas são diferentes", "Atenção");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final HttpsCallable callable =
      FirebaseFunctions.instance.httpsCallable('createUserAndCompany');
      final result = await callable.call({
        'email': _model.tfEmailTextController?.text ?? '',
        'password': _model.tfPasswordTextController?.text ?? '',
        'name': _model.tfNameTextController?.text ?? '',
        'role': _model.tfRoleTextController?.text ?? '',
        'accessRights': accessRights,
      });

      if (result.data['success']) {
        Navigator.pop(context);
        showErrorDialog(
            context, "Parceiro adicionado com sucesso!", "Sucesso");
      } else {
        showErrorDialog(context, "Falha ao adicionar colaborador.", "Atenção");
      }
    } catch (e) {
      Navigator.pop(context);
      showErrorDialog(context, "Erro ao adicionar colaborador.", "Erro");
    } finally {
      setState(() {
        _isLoading = false;
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
                Icons.arrow_back_ios_new,
                color: Theme.of(context).colorScheme.outline,
                size: 24,
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            title: Text(
              'Adicionar Colaborador',
              style: TextStyle(
                fontFamily: 'BrandingSF',
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            centerTitle: true,
            elevation: 2,
          ),
          body: SafeArea(
            top: true,
            child: Container(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
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
                                      : Image.asset(
                                          'images/icons/icon io_app.png',
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),*/
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
                                  controller: _model.tfNameTextController,
                                  focusNode: _model.tfNameFocusNode,
                                  autofocus: true,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText: 'Nome',
                                    labelStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
                                    ),
                                    hintText: 'Digite o nome do colaborador',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
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
                                        color:
                                        Theme.of(context).colorScheme.tertiary,
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
                                      Icons.person,
                                      color: Theme.of(context).colorScheme.tertiary,
                                      size: 25,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0,
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
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
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    labelStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
                                    ),
                                    hintText: 'Digite o email do colaborador',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
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
                                        color:
                                        Theme.of(context).colorScheme.tertiary,
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
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                                  controller: _model.tfRoleTextController,
                                  focusNode: _model.tfRoleFocusNode,
                                  autofocus: true,
                                  obscureText: false,
                                  decoration: InputDecoration(
                                    labelText: 'Cargo',
                                    labelStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
                                    ),
                                    hintText: 'Digite o cargo do colaborador',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
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
                                        color:
                                        Theme.of(context).colorScheme.tertiary,
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
                                      Icons.business_center,
                                      color: Theme.of(context).colorScheme.tertiary,
                                      size: 25,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0,
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
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
                            child: Align(
                              alignment: AlignmentDirectional(0, 0),
                              child: Padding(
                                padding:
                                EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                                child: TextFormField(
                                  controller: _model.tfPasswordTextController,
                                  focusNode: _model.tfPasswordFocusNode,
                                  autofocus: true,
                                  obscureText: !_model.tfPasswordVisibility,
                                  decoration: InputDecoration(
                                    labelText: 'Senha',
                                    labelStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
                                    ),
                                    hintText: 'Crie uma senha para o colaborador',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
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
                                        color:
                                        Theme.of(context).colorScheme.tertiary,
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
                                      Icons.lock,
                                      color: Theme.of(context).colorScheme.tertiary,
                                      size: 25,
                                    ),
                                    suffixIcon: InkWell(
                                      onTap: () => setState(
                                            () => _model.tfPasswordVisibility =
                                        !_model.tfPasswordVisibility,
                                      ),
                                      focusNode: FocusNode(skipTraversal: true),
                                      child: Icon(
                                        _model.tfPasswordVisibility
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color:
                                        Theme.of(context).colorScheme.tertiary,
                                        size: 25,
                                      ),
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0,
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
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
                            child: Align(
                              alignment: AlignmentDirectional(0, 0),
                              child: Padding(
                                padding:
                                EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                                child: TextFormField(
                                  controller:
                                  _model.tfPasswordConfirmTextController,
                                  focusNode: _model.tfPasswordConfirmFocusNode,
                                  autofocus: true,
                                  obscureText: !_model.tfPasswordConfirmVisibility,
                                  decoration: InputDecoration(
                                    labelText: 'Confirmar senha',
                                    labelStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
                                    ),
                                    hintText: 'Confirme a senha do colaborador',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      letterSpacing: 0,
                                      color:
                                      Theme.of(context).colorScheme.onSecondary,
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
                                        color:
                                        Theme.of(context).colorScheme.tertiary,
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
                                      Icons.lock,
                                      color: Theme.of(context).colorScheme.tertiary,
                                      size: 25,
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
                                        color:
                                        Theme.of(context).colorScheme.tertiary,
                                        size: 25,
                                      ),
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0,
                                    color:
                                    Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
                            child: Text(
                              'Marque os acessos do colaborador:',
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
                              child: _isLoading
                                  ? Center(
                                child: CircularProgressIndicator(),
                              )
                                  : ElevatedButton.icon(
                                onPressed:
                                _isLoading ? null : _addCollaborator,
                                icon: Icon(
                                  Icons.add,
                                  color:
                                  Theme.of(context).colorScheme.outline,
                                  size: 25,
                                ),
                                label: Text(
                                  'ADICIONAR',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color:
                                    Theme.of(context).colorScheme.outline,
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          ),
        ),
      ),
    );
  }
}
