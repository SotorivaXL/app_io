import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCompanyModel/add_company_model.dart';
import 'package:app_io/util/CustomWidgets/CustomCountController/custom_count_controller.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_holo_date_picker/flutter_holo_date_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:extended_image/extended_image.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

const List<String> _kPermKeys = [
  'dashboard',
  'leads',
  'gerenciarColaboradores',
  'gerenciarParceiros',
  'configurarDash',
  'criarForm',
  'criarCampanha',
  'copiarTelefones',
  'executarAPIs',
  'alterarSenha',
  'gerenciarProdutos',
  // módulos
  'modChats',
  'modConfig',
  'modIndicadores',
  'modPainel',
  'modRelatorios',
];

// Defaults usados quando a chave não estiver presente
const Map<String, bool> _kPermDefaults = {
  'dashboard'             : true,
  'leads'                 : true,
  'gerenciarColaboradores': true,
  'gerenciarParceiros'    : false,
  'configurarDash'        : false,
  'criarForm'             : false,
  'criarCampanha'         : false,
  'copiarTelefones'       : false,
  'executarAPIs'          : false,
  'alterarSenha'          : true,
  'gerenciarProdutos'     : true,
  // módulos (imagem)
  'modChats'       : true,
  'modConfig'      : true,
  'modIndicadores' : true,
  'modPainel'      : true,
  'modRelatorios'  : true,
};

// Garante que todas as chaves existam como bool (sem arrays/map aninhado)
Map<String, bool> _normalizeRights(Map<String, bool> raw) {
  final out = <String, bool>{};
  for (final k in _kPermKeys) {
    out[k] = (raw[k] == true);
  }
  // completa com defaults para chaves ausentes
  _kPermDefaults.forEach((k, v) => out.putIfAbsent(k, () => v));
  return out;
}

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
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _croppedData;
  String? _photoUrl;
  // GlobalKey para acessar o editor do ExtendedImage
  final GlobalKey<ExtendedImageEditorState> _editorKey = GlobalKey<ExtendedImageEditorState>();

  // For generating a random background color when no image exists
  late Color _randomColor;

  // Access rights map (padrão já com permissões desejadas)
// Access rights padrão
  Map<String, bool> accessRights = {
    'dashboard': true,
    'leads': true,
    'gerenciarColaboradores': true,
    'gerenciarParceiros': false,
    'configurarDash': false,
    'criarForm': false,
    'criarCampanha': false,
    'copiarTelefones': false,
    'executarAPIs': false,
    'alterarSenha': true,
    'gerenciarProdutos': true,
    // módulos novos
    'modChats': true,
    'modConfig': true,
    'modIndicadores': true,
    'modPainel': true,
    'modRelatorios': true,
  };

  // Máscaras
  final MaskTextInputFormatter cnpjMask = MaskTextInputFormatter(
    mask: '##.###.###/####-##',
    filter: { "#": RegExp(r'[0-9]') },
  );

  // Controllers extras (WhatsApp/Z-API)
  final TextEditingController _tfWhatsPhoneController = TextEditingController();
  final TextEditingController _tfInstanceIdController = TextEditingController(); // ZAPI_ID
  final TextEditingController _tfZapiTokenController = TextEditingController();  // ZAPI_TOKEN
  final TextEditingController _tfClientTokenController = TextEditingController(); // clientToken

  @override
  void initState() {
    super.initState();
    _model = AddCompanyModel();
    _randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];
  }

  @override
  void dispose() {
    _tfWhatsPhoneController.dispose();
    _tfInstanceIdController.dispose();
    _tfZapiTokenController.dispose();
    _tfClientTokenController.dispose();
    _model.dispose();
    super.dispose();
  }

  void updateCountArts(int newCount) {
    setState(() => _model.countArtsValue = newCount);
  }

  void updateCountVideos(int newCount) {
    setState(() => _model.countVideosValue = newCount);
  }

  // --------------------------
  //       ADD COMPANY
  // --------------------------
  Future<void> _addCompany() async {
    if (_model.tfPasswordTextController.text != _model.tfPasswordConfirmTextController.text) {
      showErrorDialog(context, "As senhas são diferentes", "Atenção");
      return;
    }

    // Validação mínima dos campos Z-API/phone
    final phoneDigits = _onlyDigits(_tfWhatsPhoneController.text);
// E.164 permite de 10 a 15 dígitos (com DDI). Ex.: BR: 55 + 2 (DDD) + 9 (número) = 13.
    if (phoneDigits.length < 10 || phoneDigits.length > 15) {
      showErrorDialog(
        context,
        "Informe o número com DDI (sem +), ex: 5546991073494",
        "Atenção",
      );
      return;
    }
    if (_tfInstanceIdController.text.trim().isEmpty ||
        _tfZapiTokenController.text.trim().isEmpty) {
      showErrorDialog(context, "Informe ZAPI_ID e ZAPI_TOKEN", "Atenção");
      return;
    }
    // clientToken pode ser opcional, dependendo de você ter ativado na Z-API
    // aqui não forço; mas se quiser obrigar, valide também.

    setState(() => _isLoading = true);

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('createUserAndCompany');

      // Garante que as permissões bloqueadas fiquem false
      final rights = Map<String, bool>.from(accessRights)
        ..['gerenciarParceiros'] = false
        ..['criarCampanha'] = false
        ..['criarForm'] = false
        ..['gerenciarProdutos'] = true;

      final result = await callable.call({
        'email': _model.tfEmailTextController.text,
        'password': _model.tfPasswordTextController.text,
        'nomeEmpresa': _model.tfCompanyTextController.text,
        'contract': _model.tfContractTextController.text,
        'cnpj': _model.tfCnpjTextController.text,
        'founded': _model.tfBirthTextController.text,
        'accessRights': rights,
        'countArtsValue': _model.countArtsValue,
        'countVideosValue': _model.countVideosValue,
        'phoneNumber': _onlyDigits(_tfWhatsPhoneController.text),
        'instanceId': _tfInstanceIdController.text.trim(),
        'token': _tfZapiTokenController.text.trim(),
        'clientToken': _tfClientTokenController.text.trim(),
      });

      if (result.data['success'] == true) {
        final String uid = result.data['uid'] ?? "defaultUid";

        // 2.1) Permissões "flat" na raiz (com defaults e garantindo gerenciarParceiros=false)
        final flatRights = _normalizeRights({
          ...accessRights,
          'gerenciarParceiros': false,
        });
        await FirebaseFirestore.instance
            .collection('empresas')
            .doc(uid)
            .set(flatRights, SetOptions(merge: true));

        // 2.2) Upload da imagem (avatar)
        final photoUrl = await _uploadImage(uid);
        if (photoUrl != null) {
          await FirebaseFirestore.instance
              .collection('empresas')
              .doc(uid)
              .set({'photoUrl': photoUrl}, SetOptions(merge: true));
        }

        // (opcional) salvar o phone config no subcollection se você já usa isso na criação
        await _savePhoneConfig(uid);

        Navigator.pop(context);
        showErrorDialog(context, "Parceiro adicionado com sucesso!", "Sucesso");
      } else {
        showErrorDialog(context, "Falha ao adicionar parceiro", "Atenção");
      }
    } catch (e, stacktrace) {
      print("Erro ao adicionar parceiro: $e");
      print(stacktrace);
      showErrorDialog(context, "Falha ao adicionar parceiro", "Atenção");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Salva empresas/{uid}/phones/{phoneId} com os campos exigidos
  Future<void> _savePhoneConfig(String uid) async {
    final phoneDigits = _onlyDigits(_tfWhatsPhoneController.text);
    final phoneDocId = phoneDigits; // usamos o número (só dígitos) como phoneId/docId

    final data = {
      'phoneId'    : phoneDocId,                           // EXATO
      'instanceId' : _tfInstanceIdController.text.trim(),  // EXATO (ZAPI_ID)
      'token'      : _tfZapiTokenController.text.trim(),   // EXATO (ZAPI_TOKEN)
      'clientToken': _tfClientTokenController.text.trim(), // EXATO
      'phone'      : phoneDigits,                          // número normalizado (útil ter salvo)
      'createdAt'  : FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('empresas')
        .doc(uid)
        .collection('phones')
        .doc(phoneDocId)
        .set(data, SetOptions(merge: true));
  }

  String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  // --------------------------
  //     IMAGE UPLOAD
  // --------------------------
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

  // --------------------------
  //   GENERATE INITIALS FROM COMPANY NAME
  // --------------------------
  String _generateInitialsFromCompany() {
    final text = _model.tfCompanyTextController.text.trim();
    if (text.isEmpty) return "";
    final parts = text.split(" ");
    final first = parts.first.isNotEmpty ? parts.first[0] : "";
    final last = parts.length > 1 ? parts.last[0] : first;
    return (first + last).toUpperCase();
  }

  // --------------------------
  //   GENERATE AVATAR (100x100) WITH RANDOM BACKGROUND AND INITIALS
  // --------------------------
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

  // --------------------------
  //   AVATAR WIDGET
  // --------------------------
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

  // --------------------------
  //   IMAGE PICKER OPTIONS
  // --------------------------
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

  // --------------------------
  //   CUSTOM CROP FUNCTION USING EXTENDED_IMAGE
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
                  setState(() { _croppedData = croppedData; });
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // --------------------------
  //       BUILD
  // --------------------------
  @override
  Widget build(BuildContext context) {
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
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
                                  color: Theme.of(context).colorScheme.onBackground, size: 18),
                              const SizedBox(width: 4),
                              Text('Voltar',
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Adicionar Parceiro',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
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
          body: isDesktop
              ? Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: SafeArea(
                child: SingleChildScrollView(child: _buildMainContent(context)),
              ),
            ),
          )
              : SafeArea(
            child: SingleChildScrollView(child: _buildMainContent(context)),
          ),
        ),
      ),
    );
  }

  // Main content of the form
  Widget _buildMainContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        // Avatar
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: _buildImagePicker(),
        ),
        // Dados da empresa
        _buildCompanyTextField(),
        _buildEmailTextField(),
        _buildContractTextField(),
        _buildCnpjTextField(),
        _buildBirthDateField(context),
        _buildPasswordField(),
        _buildPasswordConfirmField(),

        // WhatsApp / Z-API
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
                child: Text(
                  'WhatsApp / Z-API',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildWhatsPhoneTextField(),
        _buildZapiIdTextField(),
        _buildZapiTokenTextField(),
        _buildClientTokenTextField(),

        _buildAddButton(),
      ],
    );
  }

  // --------------------------
  // INDIVIDUAL FIELDS
  // --------------------------
  Widget _buildCompanyTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _model.tfCompanyTextController,
                focusNode: _model.tfCompanyFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Digite o nome da empresa',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  prefixIcon: Icon(Icons.corporate_fare,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  filled: true, fillColor: Theme.of(context).colorScheme.secondary,
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textInputAction: TextInputAction.next,
                textAlign: TextAlign.start,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _model.tfEmailTextController,
                focusNode: _model.tfEmailFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Digite o email da empresa',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true, fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.mail,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.start, keyboardType: TextInputType.emailAddress,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContractTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _model.tfContractTextController,
                focusNode: _model.tfContractFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Digite a data final do contrato',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true, fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.import_contacts,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.start,
                inputFormatters: [_model.tfContractMask],
                keyboardType: TextInputType.number,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCnpjTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _model.tfCnpjTextController,
                focusNode: _model.tfCnpjFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Digite o CNPJ da empresa',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true, fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.contact_emergency_sharp,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.start,
                inputFormatters: [cnpjMask],
                keyboardType: TextInputType.number,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthDateField(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: GestureDetector(
                onTap: () async {
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
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
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                          ),
                          height: 300,
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16.0),
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
                                    backgroundColor: Theme.of(context).colorScheme.secondary,
                                    itemTextStyle: TextStyle(
                                      color: Theme.of(context).colorScheme.onSecondary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    dividerColor: Theme.of(context).colorScheme.onSecondary,
                                  ),
                                  onChange: (date, _) => setState(() => selectedDate = date),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 30),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    foregroundColor: Theme.of(context).colorScheme.outline,
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
                                      color: Theme.of(context).colorScheme.outline,
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
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.secondary,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.calendar_month,
                          color: Theme.of(context).colorScheme.tertiary, size: 20),
                    ),
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                    readOnly: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
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
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.lock,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                  suffixIcon: InkWell(
                    onTap: () => setState(() => _model.tfPasswordVisibility = !_model.tfPasswordVisibility),
                    focusNode: FocusNode(skipTraversal: true),
                    child: Icon(
                        _model.tfPasswordVisibility ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Theme.of(context).colorScheme.tertiary, size: 20),
                  ),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textInputAction: TextInputAction.next,
                textAlign: TextAlign.start,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordConfirmField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
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
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.lock,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                  suffixIcon: InkWell(
                    onTap: () => setState(() => _model.tfPasswordConfirmVisibility = !_model.tfPasswordConfirmVisibility),
                    focusNode: FocusNode(skipTraversal: true),
                    child: Icon(
                        _model.tfPasswordConfirmVisibility ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Theme.of(context).colorScheme.tertiary, size: 20),
                  ),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textInputAction: TextInputAction.next,
                textAlign: TextAlign.start,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------- WhatsApp / Z-API fields ----------
  Widget _buildWhatsPhoneTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _tfWhatsPhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Número do WhatsApp com DDI',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    Icons.phone_iphone,
                    color: Theme.of(context).colorScheme.tertiary,
                    size: 20,
                  ),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.start,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZapiIdTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _tfInstanceIdController,
                decoration: InputDecoration(
                  hintText: 'ZAPI_ID (instanceId)',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true, fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.memory,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZapiTokenTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _tfZapiTokenController,
                decoration: InputDecoration(
                  hintText: 'ZAPI_TOKEN (token)',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true, fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.vpn_key,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientTokenTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _tfClientTokenController,
                decoration: InputDecoration(
                  hintText: 'Client-Token',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  filled: true, fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.shield,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Align(
      alignment: const AlignmentDirectional(0, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
              onPressed: _isLoading ? null : _addCompany,
              icon: Icon(Icons.save, color: Theme.of(context).colorScheme.outline, size: 20),
              label: Text(
                'ADICIONAR',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
                backgroundColor: Theme.of(context).colorScheme.primary,
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                side: const BorderSide(color: Colors.transparent, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}