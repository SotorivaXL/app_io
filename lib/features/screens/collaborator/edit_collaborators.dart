import 'dart:math';
import 'package:app_io/util/CustomWidgets/ChangePasswordSheet/change_password_sheet.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:extended_image/extended_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCompanyModel/add_company_model.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class EditCollaborators extends StatefulWidget {
  final String collaboratorId;
  final String name;
  final String email;
  final String role;
  final String birth;
  final bool dashboard;
  final bool leads;
  final bool configurarDash;
  final bool criarCampanha;
  final bool criarForm;
  final bool copiarTelefones;
  final bool executarAPIs;

  EditCollaborators({
    required this.collaboratorId,
    required this.name,
    required this.email,
    required this.role,
    required this.birth,
    required this.dashboard,
    required this.leads,
    required this.configurarDash,
    required this.criarCampanha,
    required this.criarForm,
    required this.copiarTelefones,
    required this.executarAPIs,
  });

  @override
  _EditCollaboratorsState createState() => _EditCollaboratorsState();
}

class _EditCollaboratorsState extends State<EditCollaborators> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCompanyModel _model;
  bool _isLoading = false;

  // Para manipulação da imagem
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _croppedData;
  String? _photoUrl;
  final GlobalKey<ExtendedImageEditorState> _editorKey = GlobalKey<ExtendedImageEditorState>();

  // Cor aleatória caso não haja imagem
  late Color _randomColor;

  double _scrollOffset = 0.0;

  Map<String, bool> accessRights = {
    'dashboard': false,
    'leads': false,
    'configurarDash': false,
    'criarCampanha': false,
    'criarForm': false,
    'copiarTelefones': false,
    'executarAPIs': false,
  };

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _roleController;
  late TextEditingController _birthController;

  bool _isChangingPassword = false;

  @override
  void initState() {
    super.initState();
    _model = AddCompanyModel();

    _nameController = TextEditingController(text: widget.name);
    _emailController = TextEditingController(text: widget.email);
    _roleController = TextEditingController(text: widget.role);

    final formattedBirth = widget.birth.replaceAll('-', '/');
    _birthController = TextEditingController(text: formattedBirth);

    accessRights['dashboard'] = widget.dashboard;
    accessRights['leads'] = widget.leads;
    accessRights['configurarDash'] = widget.configurarDash;
    accessRights['criarCampanha'] = widget.criarCampanha;
    accessRights['criarForm'] = widget.criarForm;
    accessRights['copiarTelefones'] = widget.copiarTelefones;
    accessRights['executarAPIs'] = widget.executarAPIs;

    // Gera uma cor aleatória para o fundo do avatar, caso não haja foto
    _randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];

    // Carrega a foto da empresa do Firebase Storage
    _loadCollaboratorPhoto();
  }

  Future<void> _loadCollaboratorPhoto() async {
    try {
      final ref = FirebaseStorage.instance
          .ref('${widget.collaboratorId}/imagens/user_photo.jpg');
      String url = await ref.getDownloadURL();
      setState(() {
        _photoUrl = url;
      });
    } catch (e) {
      print("Nenhuma foto encontrada: $e");
      setState(() {
        _photoUrl = null;
      });
    }
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

      // Obtém a URL da imagem (seja a nova ou a já existente, ou gerada automaticamente)
      String? updatedPhotoUrl = await _updateCollaboratorImage();
      final photoUrl = updatedPhotoUrl; // Garantindo que photoUrl seja atualizado

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
        'copiarTelefones': accessRights['copiarTelefones'],
        'photoUrl': photoUrl,
      });

      // Volta para a tela anterior
      Navigator.pop(context);

      // Exibe uma mensagem de sucesso
      showErrorDialog(context, "Colaborador atualizado com sucesso!", "Sucesso");

    } catch (e) {
      // Exibe uma mensagem de erro
      showErrorDialog(context, "Falha ao atualizar colaborador, tente novamente mais tarde", "Atenção");
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String?> _updateCollaboratorImage() async {
    final storageRef = FirebaseStorage.instance
        .ref('${widget.collaboratorId}/imagens/user_photo.jpg');

    // Se houver nova imagem (crop realizada), atualiza o Storage e retorna o novo URL
    if (_croppedData != null) {
      try {
        await storageRef.putData(_croppedData!);
        final url = await storageRef.getDownloadURL();
        setState(() => _photoUrl = url);
        return url;
      } catch (e) {
        print("Erro ao atualizar imagem: $e");
        return null;
      }
    } else {
      // Se não houve alteração, verifica se já existe uma URL salva
      if (_photoUrl != null) {
        // Retorna a URL já existente
        return _photoUrl;
      } else {
        // Se _photoUrl estiver nulo, gera o avatar automaticamente e faz o upload
        try {
          String initials = _generateInitials();
          Uint8List imageData = await _generateAvatar(initials);
          await storageRef.putData(imageData);
          final url = await storageRef.getDownloadURL();
          setState(() => _photoUrl = url);
          return url;
        } catch (e) {
          print("Erro ao gerar e salvar avatar automaticamente: $e");
          return null;
        }
      }
    }
  }

  String _generateInitials() {
    final text = widget.name.trim();
    if (text.isEmpty) return "NA";

    final parts = text.split(" ");
    final first = parts.first.isNotEmpty ? parts.first[0] : "N";
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
    textPainter.paint(
      canvas,
      Offset(50 - textPainter.width / 2, 50 - textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(100, 100);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Widget _buildImagePicker() {
    final bool hasCroppedData = _croppedData != null;
    final bool hasPhotoUrl = _photoUrl != null;

    ImageProvider? imageProvider;
    if (hasCroppedData) {
      imageProvider = MemoryImage(_croppedData!);
    } else if (hasPhotoUrl) {
      imageProvider = NetworkImage(_photoUrl!);
    }

    return GestureDetector(
      onTap: _showImagePickerOptions,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: imageProvider == null ? _randomColor : Colors.grey[300],
        backgroundImage: imageProvider,
        child: imageProvider == null
            ? Text(
          _generateInitials(),
          style: const TextStyle(fontSize: 40, color: Colors.white),
        )
            : null,
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

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      _selectedImage = pickedFile;
      final bytes = await pickedFile.readAsBytes();
      _cropImage(bytes);
    }
  }

  // --------------------------
  //   CROP DA IMAGEM
  // --------------------------
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
          targetUid: widget.collaboratorId,
          onClose: () {
            if (!mounted) return;
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
    // Detecta se é desktop
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;
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
                          'Editar Colaborador',
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
                            color: Theme.of(context).colorScheme.onBackground,
                            size: 30,
                          ),
                          onPressed: _isLoading ? null : _saveCollaborator,
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

          // Se for desktop, envolve em Center + Container (maxWidth). Caso contrário, exibe normal.
          body: isDesktop
              ? Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: 1850),
              child: SafeArea(
                top: true,
                child: SingleChildScrollView(
                  child: _buildMainContent(uid),
                ),
              ),
            ),
          )
              : SafeArea(
            top: true,
            child: SingleChildScrollView(
              child: _buildMainContent(uid),
            ),
          ),
        ),
      ),
    );
  }

  /// Método que contém todo o conteúdo do Column original (TextFields, Checkboxes, etc.)
  /// Assim, o build fica mais limpo e não removemos nenhuma linha dos widgets do Column.
  Widget _buildMainContent(String uid) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: _buildImagePicker(),
        ),
        // (Aqui está o mesmo conteúdo que antes, sem remover nada)
        // 1) Campo Nome do Colaborador
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nome do Colaborador',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        SizedBox(height: 8),
                        TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          obscureText: false,
                          decoration: InputDecoration(
                            hintText: 'Digite o nome do colaborador',
                            hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
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
                              Icons.person,
                              color: Theme.of(context).colorScheme.tertiary,
                              size: 20,
                            ),
                            contentPadding: kIsWeb ? EdgeInsets.symmetric(vertical: 25)
                                : EdgeInsets.symmetric(vertical: 15),
                          ),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          textAlign: TextAlign.start,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Por favor, insira o nome do colaborador';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2) Campo Email do Colaborador
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email do Colaborador',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          autofocus: true,
                          obscureText: false,
                          enabled: false,
                          decoration: InputDecoration(
                            hintText: 'Digite o email do colaborador',
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
                            contentPadding: kIsWeb ? EdgeInsets.symmetric(vertical: 25)
                                : EdgeInsets.symmetric(vertical: 15),
                          ),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          textAlign: TextAlign.start,
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3) Campo Cargo do Colaborador
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cargo do Colaborador',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        SizedBox(height: 8),
                        TextFormField(
                          controller: _roleController,
                          autofocus: true,
                          obscureText: false,
                          decoration: InputDecoration(
                            hintText: 'Digite o cargo do colaborador',
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
                              Icons.business_center,
                              color: Theme.of(context).colorScheme.tertiary,
                              size: 20,
                            ),
                            contentPadding: kIsWeb ? EdgeInsets.symmetric(vertical: 25)
                                : EdgeInsets.symmetric(vertical: 15),
                          ),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          textAlign: TextAlign.start,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Por favor, insira o cargo do colaborador';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 4) Campo Data de Nascimento
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data de Nascimento',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                        SizedBox(height: 8),
                        TextFormField(
                          controller: _birthController,
                          autofocus: true,
                          obscureText: false,
                          enabled: false,
                          decoration: InputDecoration(
                            hintText: 'Selecione a data de nascimento',
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
                            contentPadding: kIsWeb ? EdgeInsets.symmetric(vertical: 25)
                                : EdgeInsets.symmetric(vertical: 15),
                          ),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          textAlign: TextAlign.start,
                          // Caso queira permitir a seleção da data, descomente e implemente
                          // onTap: () => _selectDate(context, false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 5) Título: "Marque os acessos do colaborador"
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

        // 6) Checkboxes
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(10, 0, 0, 0),
          child: Column(
            children: [
              // dashboard
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
              // leads
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
              // configurarDash
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
              // criarForm
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
              // criarCampanha
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
              // copiarTelefones
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
            ],
          ),
        ),

        // 7) StreamBuilder para verificar se pode alterar senha
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

            if (snapshot.hasData && snapshot.data != null) {
              bool canChangePassword = snapshot.data!.get('alterarSenha') ?? false;

              if (canChangePassword) {
                return Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
                    child: ElevatedButton.icon(
                      onPressed: _isChangingPassword ? null : _showChangePasswordSheet,
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
                        padding: EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        side: BorderSide(
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                );
              }
            }

            return SizedBox.shrink(); // Não exibe nada se não tiver permissão.
          },
        )
      ],
    );
  }
}