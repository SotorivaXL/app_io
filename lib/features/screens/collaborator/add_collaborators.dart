import 'dart:math';

import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:extended_image/extended_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCollaboratorModel/add_collaborator_model.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_holo_date_picker/flutter_holo_date_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui' as ui;

class AddCollaborators extends StatefulWidget {
  @override
  _AddCollaboratorsState createState() => _AddCollaboratorsState();
}

class _AddCollaboratorsState extends State<AddCollaborators> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCollaboratorsModel _model;
  String? userId;
  bool _isLoading = false;
  double _scrollOffset = 0.0;
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _croppedData;
  String? _photoUrl;
  // GlobalKey para acessar o editor do ExtendedImage
  final GlobalKey<ExtendedImageEditorState> _editorKey = GlobalKey<ExtendedImageEditorState>();

  // For generating a random background color when no image exists
  late Color _randomColor;

  // Inicializa o mapa para armazenar os direitos de acesso
  Map<String, bool> accessRights = {
    // MÓDULOS
    'modChats': true,
    'modIndicadores': true,
    'modPainel': false,
    'modConfig': true,
    'modRelatorios': false, // opcional

    // PERMISSÕES INTERNAS (Painel)
    'gerenciarParceiros': false,
    'gerenciarColaboradores': false,
    'criarForm': false,
    'criarCampanha': false,
    'gerenciarProdutos': false,

    // OUTROS (se usados em outras telas)
    'leads': false,
    'copiarTelefones': false,
    'executarAPIs': false,
  };

  void _setPerm(String key, bool value) {
    setState(() {
      accessRights[key] = value;

      if (key == 'modPainel' && value == false) {
        accessRights['gerenciarParceiros'] = false;
        accessRights['gerenciarColaboradores'] = false;
        accessRights['criarForm'] = false;
        accessRights['criarCampanha'] = false;
        accessRights['gerenciarProdutos'] = false; // <-- NOVO
      }

      const subPerms = [
        'gerenciarParceiros',
        'gerenciarColaboradores',
        'criarForm',
        'criarCampanha',
        'gerenciarProdutos',
      ];
      if (subPerms.contains(key) && value == true) {
        accessRights['modPainel'] = true;
      }
    });
  }

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

    _model.tfBirthTextController ??= TextEditingController();
    _model.tfBirthFocusNode ??= FocusNode();

    _model.tfPasswordTextController ??= TextEditingController();
    _model.tfPasswordFocusNode ??= FocusNode();

    _model.tfPasswordConfirmTextController ??= TextEditingController();
    _model.tfPasswordConfirmFocusNode ??= FocusNode();

    _randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];
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
        'birth': _model.tfBirthTextController?.text ?? '',
        'accessRights': accessRights,
      });

      if (result.data['success']) {
        String uid = result.data['uid'] ?? "defaultUid";

        // Faz o upload da imagem e obtém a URL
        final photoUrl = await _uploadImage(uid);

        // Usa set com merge:true para criar/atualizar o documento com photoUrl
        if (photoUrl != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set(
            {
              'photoUrl': photoUrl,
            },
            SetOptions(merge: true),
          );
          print("photoUrl salvo com sucesso: $photoUrl");
        } else {
          print("photoUrl é nulo");
        }

        Navigator.pop(context);
        showErrorDialog(context, "Parceiro adicionado com sucesso!", "Sucesso");
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

  Widget _buildPermissionsList() {
    final cs = Theme.of(context).colorScheme;

    CheckboxListTile cb({
      required String keyName,
      required String label,
    }) {
      final cs = Theme.of(context).colorScheme;
      return CheckboxListTile(
        title: Text(label, style: TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 14,
          color: cs.onSecondary,
        )),
        value: accessRights[keyName] ?? false,
        onChanged: (v) => _setPerm(keyName, v ?? false), // ⬅️ aqui
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: cs.tertiary,
        checkColor: cs.outline,
        side: BorderSide(color: cs.tertiary, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        dense: true,
      );
    }

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Text(title, style: TextStyle(
        fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600,
        color: cs.onSecondary,
      )),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('Acesso aos módulos'),
        cb(keyName: 'modChats',        label: 'Chats'),
        cb(keyName: 'modIndicadores',  label: 'Indicadores'),
        cb(keyName: 'modPainel',       label: 'Configurações'),
        cb(keyName: 'modRelatorios',   label: 'Relatórios'), // se usar

        section('Permissões internas (Painel)'),
        cb(keyName: 'gerenciarParceiros',     label: 'Gerenciar Parceiros'),
        cb(keyName: 'gerenciarColaboradores', label: 'Gerenciar Colaboradores'),
        cb(keyName: 'criarForm',              label: 'Criar Formulário'),
        cb(keyName: 'criarCampanha',          label: 'Criar Campanha'),
        cb(keyName: 'gerenciarProdutos',      label: 'Gerenciar Produtos'),

        section('Outros'),
        cb(keyName: 'leads',            label: 'Leads'),
        cb(keyName: 'copiarTelefones',  label: 'Copiar telefones dos Leads'),
        cb(keyName: 'executarAPIs',     label: 'Executar APIs'),
      ],
    );
  }

  Future<String?> _uploadImage(String uid) async {
    Uint8List imageData;
    if (_croppedData != null) {
      imageData = _croppedData!;
    } else {
      String initials = _generateInitialsFromCompany();
      imageData = await _generateAvatar(initials);
    }
    try {
      final ref = FirebaseStorage.instance.ref().child('$uid/imagens/user_photo.jpg');
      await ref.putData(imageData);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      print('Erro no upload da imagem: $e');
      return null;
    }
  }

  String _generateInitialsFromCompany() {
    final text = _model.tfNameTextController.text.trim();
    if (text.isEmpty) return "";
    final parts = text.split(" ");
    final first = parts.first.isNotEmpty ? parts.first[0] : "";
    final last = parts.length > 1 ? parts.last[0] : first;
    return (first + last).toUpperCase();
  }

  Future<Uint8List> _generateAvatar(String initials) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 100, 100));
    final randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];
    final paint = Paint()..color = randomColor;
    canvas.drawCircle(const Offset(50, 50), 50, paint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(50 - textPainter.width / 2, 50 - textPainter.height / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(100, 100);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Widget _buildImagePicker() {
    final bool hasCroppedImage = _croppedData != null;
    return GestureDetector(
      onTap: _showImagePickerOptions,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: hasCroppedImage ? Colors.grey[300] : _randomColor,
        backgroundImage: hasCroppedImage ? MemoryImage(_croppedData!) : null,
        child: hasCroppedImage
            ? null
            : Text(
          _generateInitialsFromCompany(),
          style: const TextStyle(fontSize: 40, color: Colors.white),
        ),
      ),
    );
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(
                  'Escolher da Galeria',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSecondary
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(
                  'Tirar Foto',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSecondary
                  ),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              if (_photoUrl != null || _croppedData != null)
                ListTile(
                  leading: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Remover Foto',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.error
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _croppedData = null;
                      _photoUrl = null;
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // Modificação para solicitar permissão antes de acessar a câmera
  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      _selectedImage = pickedFile;
      final bytes = await pickedFile.readAsBytes();
      _cropImage(bytes);
    }
  }

  Future<Uint8List?> _cropImageFromEditor() async {
    final ExtendedImageEditorState? state = _editorKey.currentState;
    if (state == null) return null;
    final Rect? cropRect = state.getCropRect();
    if (cropRect == null) return null;
    final Uint8List? rawData = state.rawImageData;
    if (rawData == null) return null;
    final codec = await ui.instantiateImageCodec(rawData);
    final frame = await codec.getNextFrame();
    final fullImage = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    canvas.drawImageRect(
      fullImage,
      cropRect,
      Rect.fromLTWH(0, 0, cropRect.width, cropRect.height),
      paint,
    );
    final croppedImage = await recorder.endRecording().toImage(
      cropRect.width.toInt(),
      cropRect.height.toInt(),
    );
    final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _cropImage(Uint8List imageData) async {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 500,
            height: 500,
            // Passe os bytes da imagem como argumento posicional
            child: ExtendedImage.memory(
              imageData,
              fit: BoxFit.contain,
              mode: ExtendedImageMode.editor,
              extendedImageEditorKey: _editorKey,
              initEditorConfigHandler: (_) {
                return EditorConfig(
                  cropRectPadding: const EdgeInsets.all(20),
                  maxScale: 8.0,
                  cropAspectRatio: 1.0,
                );
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
                    color: Theme.of(context).colorScheme.onSecondary
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(
                "Cortar",
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSecondary
                ),
              ),
              onPressed: () async {
                final Uint8List? croppedData = await _cropImageFromEditor();
                if (croppedData != null) {
                  setState(() {
                    _croppedData = croppedData;
                  });
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ADICIONADO: detecta se é desktop
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: appBarHeight,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              child: Padding(
                // Conteúdo original do seu Padding
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
                          'Adicionar Colaborador',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
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
                                icon: Icon(
                                  Icons.save_as_sharp,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onBackground,
                                  size: 30,
                                ),
                                onPressed: _isLoading ? null : _addCollaborator,
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
          // ADICIONADO: limite de largura se for desktop; caso contrário, layout normal
          body: isDesktop
              ? Align(
                  alignment: Alignment.topCenter,
                  // Alinha o conteúdo ao topo e centraliza horizontalmente
                  child: Container(
                    constraints: BoxConstraints(maxWidth: 1500),
                    child: SafeArea(
                      top: false,
                      child: Container(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20.0),
                                child: _buildImagePicker(),
                              ),
                              // Seus campos e checkboxes originais
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
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                  20, 0, 20, 0),
                                          child: TextFormField(
                                            controller:
                                                _model.tfNameTextController,
                                            focusNode: _model.tfNameFocusNode,
                                            autofocus: true,
                                            obscureText: false,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Digite o nome do colaborador',
                                              hintStyle: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                                letterSpacing: 0,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondary,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              prefixIcon: Icon(
                                                Icons.person,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .tertiary,
                                                size: 20,
                                              ),
                                              contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                                  : EdgeInsets.symmetric(vertical: 20),
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
                                            textInputAction:
                                                TextInputAction.next,
                                            textAlign: TextAlign.start,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                  20, 0, 20, 0),
                                          child: TextFormField(
                                            controller:
                                                _model.tfEmailTextController,
                                            focusNode: _model.tfEmailFocusNode,
                                            autofocus: true,
                                            obscureText: false,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Digite o email do colaborador',
                                              hintStyle: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                                letterSpacing: 0,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondary,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              prefixIcon: Icon(
                                                Icons.mail,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .tertiary,
                                                size: 20,
                                              ),
                                              contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                                  : EdgeInsets.symmetric(vertical: 20),
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
                                            textInputAction:
                                                TextInputAction.next,
                                            textAlign: TextAlign.start,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                  20, 0, 20, 0),
                                          child: TextFormField(
                                            controller:
                                                _model.tfRoleTextController,
                                            focusNode: _model.tfRoleFocusNode,
                                            autofocus: true,
                                            obscureText: false,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Digite o cargo do colaborador',
                                              hintStyle: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                                letterSpacing: 0,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondary,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              prefixIcon: Icon(
                                                Icons.business_center,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .tertiary,
                                                size: 20,
                                              ),
                                              contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                                  : EdgeInsets.symmetric(vertical: 20),
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
                                            textInputAction:
                                                TextInputAction.done,
                                            textAlign: TextAlign.start,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                  20, 0, 20, 0),
                                          child: GestureDetector(
                                            onTap: () async {
                                              await showModalBottomSheet(
                                                context: context,
                                                isScrollControlled: true,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.vertical(
                                                    top: Radius.circular(25),
                                                  ),
                                                ),
                                                builder:
                                                    (BuildContext context) {
                                                  DateTime selectedDate =
                                                      DateTime.now();

                                                  return Padding(
                                                    padding: EdgeInsets.only(
                                                      bottom:
                                                          MediaQuery.of(context)
                                                              .viewInsets
                                                              .bottom,
                                                    ),
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .secondary,
                                                        borderRadius:
                                                            BorderRadius
                                                                .vertical(
                                                          top: Radius.circular(
                                                              25),
                                                        ),
                                                      ),
                                                      height: 300,
                                                      child: Column(
                                                        children: [
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(16.0),
                                                            child: Text(
                                                              "Selecione a Data de Nascimento",
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    'Poppins',
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child:
                                                                DatePickerWidget(
                                                              initialDate:
                                                                  DateTime
                                                                      .now(),
                                                              firstDate:
                                                                  DateTime(
                                                                      1900),
                                                              lastDate: DateTime
                                                                  .now(),
                                                              dateFormat:
                                                                  "dd-MMMM-yyyy",
                                                              locale:
                                                                  DateTimePickerLocale
                                                                      .pt_br,
                                                              looping: false,
                                                              // Desativa o loop para evitar que datas iniciais fiquem abaixo da data atual
                                                              pickerTheme:
                                                                  DateTimePickerTheme(
                                                                backgroundColor: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .secondary,
                                                                // Fundo
                                                                itemTextStyle:
                                                                    TextStyle(
                                                                  color: Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .onSecondary,
                                                                  // Cor do texto
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                                dividerColor: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .onSecondary, // Cor do divisor
                                                              ),
                                                              onChange:
                                                                  (date, _) {
                                                                setState(() {
                                                                  selectedDate =
                                                                      date;
                                                                });
                                                              },
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding:
                                                                EdgeInsetsDirectional
                                                                    .fromSTEB(
                                                                        0,
                                                                        0,
                                                                        0,
                                                                        30),
                                                            child:
                                                                ElevatedButton(
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .primary,
                                                                foregroundColor:
                                                                    Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .outline,
                                                              ),
                                                              onPressed: () {
                                                                setState(() {
                                                                  // Formata a data selecionada no formato dd/mm/yyyy
                                                                  _model.tfBirthTextController
                                                                          .text =
                                                                      "${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}";
                                                                });
                                                                Navigator.pop(
                                                                    context);
                                                              },
                                                              child: Text(
                                                                "Confirmar",
                                                                style: TextStyle(
                                                                    fontFamily:
                                                                        'Poppins',
                                                                    fontSize:
                                                                        14,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    color: Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .outline),
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
                                                controller: _model
                                                    .tfBirthTextController,
                                                decoration: InputDecoration(
                                                  hintText:
                                                      'Selecione a data de nascimento',
                                                  hintStyle: TextStyle(
                                                    fontFamily: 'Poppins',
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 16,
                                                    letterSpacing: 0,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSecondary,
                                                  ),
                                                  filled: true,
                                                  fillColor: Theme.of(context)
                                                      .colorScheme
                                                      .secondary,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                  prefixIcon: Icon(
                                                    Icons.calendar_month,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .tertiary,
                                                    size: 20,
                                                  ),
                                                  contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                                      : EdgeInsets.symmetric(vertical: 20),
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
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                  20, 0, 20, 0),
                                          child: TextFormField(
                                            controller:
                                                _model.tfPasswordTextController,
                                            focusNode:
                                                _model.tfPasswordFocusNode,
                                            autofocus: true,
                                            obscureText:
                                                !_model.tfPasswordVisibility,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Crie uma senha para o colaborador',
                                              hintStyle: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                                letterSpacing: 0,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondary,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              prefixIcon: Icon(
                                                Icons.lock,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .tertiary,
                                                size: 20,
                                              ),
                                              suffixIcon: InkWell(
                                                onTap: () => setState(
                                                  () => _model
                                                          .tfPasswordVisibility =
                                                      !_model
                                                          .tfPasswordVisibility,
                                                ),
                                                focusNode: FocusNode(
                                                    skipTraversal: true),
                                                child: Icon(
                                                  _model.tfPasswordVisibility
                                                      ? Icons
                                                          .visibility_off_outlined
                                                      : Icons
                                                          .visibility_outlined,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .tertiary,
                                                  size: 20,
                                                ),
                                              ),
                                              contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                                  : EdgeInsets.symmetric(vertical: 20),
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
                                            textInputAction:
                                                TextInputAction.next,
                                            textAlign: TextAlign.start,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                                          padding:
                                              EdgeInsetsDirectional.fromSTEB(
                                                  20, 0, 20, 0),
                                          child: TextFormField(
                                            controller: _model
                                                .tfPasswordConfirmTextController,
                                            focusNode: _model
                                                .tfPasswordConfirmFocusNode,
                                            autofocus: true,
                                            obscureText: !_model
                                                .tfPasswordConfirmVisibility,
                                            decoration: InputDecoration(
                                              hintText:
                                                  'Confirme a senha do colaborador',
                                              hintStyle: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                                letterSpacing: 0,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondary,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              prefixIcon: Icon(
                                                Icons.lock,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .tertiary,
                                                size: 20,
                                              ),
                                              suffixIcon: InkWell(
                                                onTap: () => setState(
                                                  () => _model
                                                          .tfPasswordConfirmVisibility =
                                                      !_model
                                                          .tfPasswordConfirmVisibility,
                                                ),
                                                focusNode: FocusNode(
                                                    skipTraversal: true),
                                                child: Icon(
                                                  _model.tfPasswordConfirmVisibility
                                                      ? Icons
                                                          .visibility_off_outlined
                                                      : Icons
                                                          .visibility_outlined,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .tertiary,
                                                  size: 20,
                                                ),
                                              ),
                                              contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                                  : EdgeInsets.symmetric(vertical: 20),
                                            ),
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: 0,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSecondary,
                                            ),
                                            textInputAction:
                                                TextInputAction.next,
                                            textAlign: TextAlign.start,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding:
                                    EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: EdgeInsetsDirectional.fromSTEB(
                                          20, 10, 20, 10),
                                      child: Text(
                                        'Marque os acessos do colaborador:',
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
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 0, 20),
                                child: _buildPermissionsList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : SafeArea(
                  top: false,
                  child: Container(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20.0),
                            child: _buildImagePicker(),
                          ),
                          // Exatamente o mesmo conteúdo que já estava aqui
                          // para a versão mobile/tablet
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
                                      padding:
                                      EdgeInsetsDirectional.fromSTEB(
                                          20, 0, 20, 0),
                                      child: TextFormField(
                                        controller:
                                        _model.tfNameTextController,
                                        focusNode: _model.tfNameFocusNode,
                                        autofocus: true,
                                        obscureText: false,
                                        decoration: InputDecoration(
                                          hintText:
                                          'Digite o nome do colaborador',
                                          hintStyle: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 16,
                                            letterSpacing: 0,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(10),
                                            borderSide: BorderSide.none,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.person,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                            size: 20,
                                          ),
                                          contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                              : EdgeInsets.symmetric(vertical: 15),
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
                                        textInputAction:
                                        TextInputAction.next,
                                        textAlign: TextAlign.start,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                      padding:
                                      EdgeInsetsDirectional.fromSTEB(
                                          20, 0, 20, 0),
                                      child: TextFormField(
                                        controller:
                                        _model.tfEmailTextController,
                                        focusNode: _model.tfEmailFocusNode,
                                        autofocus: true,
                                        obscureText: false,
                                        decoration: InputDecoration(
                                          hintText:
                                          'Digite o email do colaborador',
                                          hintStyle: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 16,
                                            letterSpacing: 0,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(10),
                                            borderSide: BorderSide.none,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.mail,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                            size: 20,
                                          ),
                                          contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                              : EdgeInsets.symmetric(vertical: 15),
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
                                        textInputAction:
                                        TextInputAction.next,
                                        textAlign: TextAlign.start,
                                        keyboardType:
                                        TextInputType.emailAddress,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                      padding:
                                      EdgeInsetsDirectional.fromSTEB(
                                          20, 0, 20, 0),
                                      child: TextFormField(
                                        controller:
                                        _model.tfRoleTextController,
                                        focusNode: _model.tfRoleFocusNode,
                                        autofocus: true,
                                        obscureText: false,
                                        decoration: InputDecoration(
                                          hintText:
                                          'Digite o cargo do colaborador',
                                          hintStyle: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 16,
                                            letterSpacing: 0,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(10),
                                            borderSide: BorderSide.none,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.business_center,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                            size: 20,
                                          ),
                                          contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                              : EdgeInsets.symmetric(vertical: 15),
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
                                        textInputAction:
                                        TextInputAction.done,
                                        textAlign: TextAlign.start,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                      padding:
                                      EdgeInsetsDirectional.fromSTEB(
                                          20, 0, 20, 0),
                                      child: GestureDetector(
                                        onTap: () async {
                                          await showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.vertical(
                                                top: Radius.circular(25),
                                              ),
                                            ),
                                            builder:
                                                (BuildContext context) {
                                              DateTime selectedDate =
                                              DateTime.now();

                                              return Padding(
                                                padding: EdgeInsets.only(
                                                  bottom:
                                                  MediaQuery.of(context)
                                                      .viewInsets
                                                      .bottom,
                                                ),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .secondary,
                                                    borderRadius:
                                                    BorderRadius
                                                        .vertical(
                                                      top: Radius.circular(
                                                          25),
                                                    ),
                                                  ),
                                                  height: 300,
                                                  child: Column(
                                                    children: [
                                                      Padding(
                                                        padding:
                                                        const EdgeInsets
                                                            .all(16.0),
                                                        child: Text(
                                                          "Selecione a Data de Nascimento",
                                                          style: TextStyle(
                                                            fontFamily:
                                                            'Poppins',
                                                            fontSize: 18,
                                                            fontWeight:
                                                            FontWeight
                                                                .bold,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child:
                                                        DatePickerWidget(
                                                          initialDate:
                                                          DateTime
                                                              .now(),
                                                          firstDate:
                                                          DateTime(
                                                              1900),
                                                          lastDate: DateTime
                                                              .now(),
                                                          dateFormat:
                                                          "dd-MMMM-yyyy",
                                                          locale:
                                                          DateTimePickerLocale
                                                              .pt_br,
                                                          looping: false,
                                                          // Desativa o loop para evitar que datas iniciais fiquem abaixo da data atual
                                                          pickerTheme:
                                                          DateTimePickerTheme(
                                                            backgroundColor: Theme.of(
                                                                context)
                                                                .colorScheme
                                                                .secondary,
                                                            // Fundo
                                                            itemTextStyle:
                                                            TextStyle(
                                                              color: Theme.of(
                                                                  context)
                                                                  .colorScheme
                                                                  .onSecondary,
                                                              // Cor do texto
                                                              fontSize: 18,
                                                              fontWeight:
                                                              FontWeight
                                                                  .bold,
                                                            ),
                                                            dividerColor: Theme.of(
                                                                context)
                                                                .colorScheme
                                                                .onSecondary, // Cor do divisor
                                                          ),
                                                          onChange:
                                                              (date, _) {
                                                            setState(() {
                                                              selectedDate =
                                                                  date;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding:
                                                        EdgeInsetsDirectional
                                                            .fromSTEB(
                                                            0,
                                                            0,
                                                            0,
                                                            30),
                                                        child:
                                                        ElevatedButton(
                                                          style:
                                                          ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                            Theme.of(
                                                                context)
                                                                .colorScheme
                                                                .primary,
                                                            foregroundColor:
                                                            Theme.of(
                                                                context)
                                                                .colorScheme
                                                                .outline,
                                                          ),
                                                          onPressed: () {
                                                            setState(() {
                                                              // Formata a data selecionada no formato dd/mm/yyyy
                                                              _model.tfBirthTextController
                                                                  .text =
                                                              "${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}";
                                                            });
                                                            Navigator.pop(
                                                                context);
                                                          },
                                                          child: Text(
                                                            "Confirmar",
                                                            style: TextStyle(
                                                                fontFamily:
                                                                'Poppins',
                                                                fontSize:
                                                                14,
                                                                fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                                color: Theme.of(
                                                                    context)
                                                                    .colorScheme
                                                                    .outline),
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
                                            controller: _model
                                                .tfBirthTextController,
                                            decoration: InputDecoration(
                                              hintText:
                                              'Selecione a data de nascimento',
                                              hintStyle: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                                letterSpacing: 0,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSecondary,
                                              ),
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                BorderRadius.circular(
                                                    10),
                                                borderSide: BorderSide.none,
                                              ),
                                              prefixIcon: Icon(
                                                Icons.calendar_month,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .tertiary,
                                                size: 20,
                                              ),
                                              contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                                  : EdgeInsets.symmetric(vertical: 15),
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
                                      padding:
                                      EdgeInsetsDirectional.fromSTEB(
                                          20, 0, 20, 0),
                                      child: TextFormField(
                                        controller:
                                        _model.tfPasswordTextController,
                                        focusNode:
                                        _model.tfPasswordFocusNode,
                                        autofocus: true,
                                        obscureText:
                                        !_model.tfPasswordVisibility,
                                        decoration: InputDecoration(
                                          hintText:
                                          'Crie uma senha para o colaborador',
                                          hintStyle: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 16,
                                            letterSpacing: 0,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(10),
                                            borderSide: BorderSide.none,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.lock,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                            size: 20,
                                          ),
                                          suffixIcon: InkWell(
                                            onTap: () => setState(
                                                  () => _model
                                                  .tfPasswordVisibility =
                                              !_model
                                                  .tfPasswordVisibility,
                                            ),
                                            focusNode: FocusNode(
                                                skipTraversal: true),
                                            child: Icon(
                                              _model.tfPasswordVisibility
                                                  ? Icons
                                                  .visibility_off_outlined
                                                  : Icons
                                                  .visibility_outlined,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .tertiary,
                                              size: 20,
                                            ),
                                          ),
                                          contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                              : EdgeInsets.symmetric(vertical: 15),
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
                                        textInputAction:
                                        TextInputAction.next,
                                        textAlign: TextAlign.start,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                      padding:
                                      EdgeInsetsDirectional.fromSTEB(
                                          20, 0, 20, 0),
                                      child: TextFormField(
                                        controller: _model
                                            .tfPasswordConfirmTextController,
                                        focusNode: _model
                                            .tfPasswordConfirmFocusNode,
                                        autofocus: true,
                                        obscureText: !_model
                                            .tfPasswordConfirmVisibility,
                                        decoration: InputDecoration(
                                          hintText:
                                          'Confirme a senha do colaborador',
                                          hintStyle: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w500,
                                            fontSize: 16,
                                            letterSpacing: 0,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(10),
                                            borderSide: BorderSide.none,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.lock,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                            size: 20,
                                          ),
                                          suffixIcon: InkWell(
                                            onTap: () => setState(
                                                  () => _model
                                                  .tfPasswordConfirmVisibility =
                                              !_model
                                                  .tfPasswordConfirmVisibility,
                                            ),
                                            focusNode: FocusNode(
                                                skipTraversal: true),
                                            child: Icon(
                                              _model.tfPasswordConfirmVisibility
                                                  ? Icons
                                                  .visibility_off_outlined
                                                  : Icons
                                                  .visibility_outlined,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .tertiary,
                                              size: 20,
                                            ),
                                          ),
                                          contentPadding: isDesktop ? EdgeInsets.symmetric(vertical: 25)
                                              : EdgeInsets.symmetric(vertical: 15),
                                        ),
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSecondary,
                                        ),
                                        textInputAction:
                                        TextInputAction.next,
                                        textAlign: TextAlign.start,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding:
                            EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsetsDirectional.fromSTEB(
                                      20, 10, 20, 10),
                                  child: Text(
                                    'Marque os acessos do colaborador:',
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
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 0, 20),
                            child: _buildPermissionsList(),
                          ),
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
