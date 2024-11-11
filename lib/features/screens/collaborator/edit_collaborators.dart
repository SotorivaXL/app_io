import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCompanyModel/add_company_model.dart';
import 'package:app_io/util/services/firestore_service.dart';

class EditCollaborators extends StatefulWidget {
  final String collaboratorId;
  final String name;
  final String email;
  final String role;
  final bool dashboard;
  final bool leads;
  final bool configurarDash;
  final bool criarCampanha;
  final bool criarForm;

  EditCollaborators({
    required this.collaboratorId,
    required this.name,
    required this.email,
    required this.role,
    required this.dashboard,
    required this.leads,
    required this.configurarDash,
    required this.criarCampanha,
    required this.criarForm,
  });

  @override
  _EditCollaboratorsState createState() => _EditCollaboratorsState();
}

class _EditCollaboratorsState extends State<EditCollaborators> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCompanyModel _model;
  bool _isLoading = false;

  Map<String, bool> accessRights = {
    'dashboard': false,
    'leads': false,
    'configurarDash': false,
    'criarCampanha': false,
    'criarForm': false,
  };

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _roleController;

  @override
  void initState() {
    super.initState();
    _model = AddCompanyModel();

    _nameController = TextEditingController(text: widget.name);
    _emailController = TextEditingController(text: widget.email);
    _roleController = TextEditingController(text: widget.role);

    accessRights['dashboard'] = widget.dashboard;
    accessRights['leads'] = widget.leads;
    accessRights['configurarDash'] = widget.configurarDash;
    accessRights['criarCampanha'] = widget.criarCampanha;
    accessRights['criarForm'] = widget.criarForm;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _roleController.dispose();

    _model.dispose();
    super.dispose();
  }

  Future<void> _saveCollaborator() async {
    setState(() {
      _isLoading = true;
    });

    if (widget.collaboratorId.isEmpty) {
      showErrorDialog(context, "Falha ao carregar usuário", "Atenção");
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {

      // Atualize os dados do colaborador no Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.collaboratorId)
          .update({
        'name': _nameController.text,
        'email': _emailController.text,
        'role': _roleController.text,
        'dashboard': accessRights['dashboard'],
        'leads': accessRights['leads'],
        'configurarDash': accessRights['configurarDash'],
        'criarCampanha': accessRights['criarCampanha'],
        'criarForm': accessRights['criarForm'],
      });

      // Volta para a tela anterior
      Navigator.pop(context);

      // Exibe uma mensagem de sucesso
      showErrorDialog(context, "Colaborador atualizado com sucesso!", "Sucesso");

    } catch (e) {
      // Exibe uma mensagem de erro
      showErrorDialog(context, "Falha ao atualizar colaborador, tente novamente mais tarde", "Atenção");
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
              'Editar Colaborador',
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
                                controller: _nameController,
                                autofocus: true,
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Nome',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Digite o nome do colaborador',
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
                                controller: _emailController,
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
                                  hintText: 'Digite o email do colaborador',
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
                                controller: _roleController,
                                autofocus: true,
                                obscureText: false,
                                decoration: InputDecoration(
                                  labelText: 'Cargo',
                                  labelStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0,
                                    color: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  hintText: 'Digite o cargo do colaborador',
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
                                ? ElevatedButton(
                              onPressed: null,
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
                                : ElevatedButton.icon(
                              onPressed: _saveCollaborator,
                              icon: Icon(
                                Icons.save_alt,
                                color: Theme.of(context).colorScheme.outline,
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