import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:app_io/util/CustomWidgets/ChangePasswordSheet/change_password_sheet.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_io/data/models/RegisterCompanyModel/add_company_model.dart';
import 'package:app_io/util/CustomWidgets/CustomCountController/custom_count_controller.dart';
import 'package:app_io/util/services/firestore_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:extended_image/extended_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_holo_date_picker/flutter_holo_date_picker.dart';
import 'package:flutter/services.dart';

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
  final bool executarAPIs;
  final bool gerenciarProdutos;

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
    required this.executarAPIs,
    required this.gerenciarProdutos,
  });

  @override
  _EditCompaniesState createState() => _EditCompaniesState();
}

class _EditCompaniesState extends State<EditCompanies> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCompanyModel _model;
  bool _isLoading = false;
  double _scrollOffset = 0.0;

  // WhatsApp / Z-API
  final TextEditingController _tfWhatsPhoneController = TextEditingController();
  final TextEditingController _tfInstanceIdController = TextEditingController(); // ZAPI_ID
  final TextEditingController _tfZapiTokenController = TextEditingController();  // ZAPI_TOKEN
  final TextEditingController _tfClientTokenController = TextEditingController(); // clientToken

  String? _originalPhoneDocId; // para saber se trocou o docId do phone

  String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  Map<String, bool> accessRights = {
    'dashboard': false,
    'leads': false,
    'gerenciarColaboradores': false,
    'configurarDash': false,
    'criarCampanha': false,
    'criarForm': false,
    'copiarTelefones': false,
    'alterarSenha': false,
    'executarAPIs': false,
    'gerenciarProdutos': true,
    // módulos novos (se não vierem do Firestore, defaults serão aplicados no normalize)
    'modChats': true,
    'modConfig': true,
    'modIndicadores': true,
    'modPainel': true,
    'modRelatorios': true,
  };

  bool _isChangingPassword = false;

  // Para manipulação da imagem
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _croppedData;
  String? _photoUrl;
  final GlobalKey<ExtendedImageEditorState> _editorKey = GlobalKey<ExtendedImageEditorState>();

  // Cor aleatória caso não haja imagem
  late Color _randomColor;

  @override
  void initState() {
    super.initState();
    _model = AddCompanyModel();

    // Preenche os controladores com os dados recebidos
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
    accessRights['executarAPIs'] = widget.executarAPIs;
    accessRights['gerenciarProdutos'] = widget.gerenciarProdutos;

    // Gera uma cor aleatória para o fundo do avatar, caso não haja foto
    _randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];

    // Carrega a foto da empresa do Firebase Storage
    _loadCompanyPhoto();

    // Carrega telefone/Z-API (pega o 1º phone de empresas/{uid}/phones)
    _loadPhoneConfig();
  }

  Future<void> _savePermissionsFlat() async {
    final flatRights = _normalizeRights({
      ...accessRights,
      // reforços que você quiser travar
      'gerenciarParceiros': false,
    });

    await FirebaseFirestore.instance
        .collection('empresas')
        .doc(widget.companyId)
        .set(flatRights, SetOptions(merge: true));
  }

  Future<void> _loadPhoneConfig() async {
    try {
      final phonesCol = FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.companyId)
          .collection('phones');

      // pega o primeiro phone cadastrado (ou adapte para escolher um específico)
      final qs = await phonesCol.limit(1).get();
      if (qs.docs.isNotEmpty) {
        final d = qs.docs.first;
        final m = d.data();
        setState(() {
          _originalPhoneDocId    = d.id;
          _tfWhatsPhoneController.text = (m['phone'] ?? d.id).toString();
          _tfInstanceIdController.text = (m['instanceId'] ?? '').toString();
          _tfZapiTokenController.text  = (m['token'] ?? '').toString();
          _tfClientTokenController.text= (m['clientToken'] ?? '').toString();
        });
      } else {
        setState(() => _originalPhoneDocId = null);
      }
    } catch (e) {
      debugPrint('Erro ao carregar config de telefone: $e');
      setState(() => _originalPhoneDocId = null);
    }
  }

  Future<void> _savePhoneConfig(String companyId) async {
    final phoneDigits = _onlyDigits(_tfWhatsPhoneController.text);
    final newDocId    = phoneDigits; // use o número como docId

    final phonesCol = FirebaseFirestore.instance
        .collection('empresas')
        .doc(companyId)
        .collection('phones');

    final data = {
      'phoneId'    : newDocId,
      'instanceId' : _tfInstanceIdController.text.trim(),
      'token'      : _tfZapiTokenController.text.trim(),
      'clientToken': _tfClientTokenController.text.trim(),
      'phone'      : phoneDigits,
      'updatedAt'  : FieldValue.serverTimestamp(),
    };

    final batch = FirebaseFirestore.instance.batch();

    // se o número (docId) mudou, apaga o antigo
    if (_originalPhoneDocId != null &&
        _originalPhoneDocId!.isNotEmpty &&
        _originalPhoneDocId != newDocId) {
      batch.delete(phonesCol.doc(_originalPhoneDocId));
    }

    // faz o upsert do doc novo/atual
    batch.set(phonesCol.doc(newDocId), data, SetOptions(merge: true));

    await batch.commit();

    setState(() {
      _originalPhoneDocId = newDocId.isEmpty ? null : newDocId;
    });
  }

  Future<void> _loadCompanyPhoto() async {
    try {
      final ref = FirebaseStorage.instance
          .ref('${widget.companyId}/imagens/user_photo.jpg');
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
    _tfWhatsPhoneController.dispose();
    _tfInstanceIdController.dispose();
    _tfZapiTokenController.dispose();
    _tfClientTokenController.dispose();
    _model.dispose();
    super.dispose();
  }

  // Definição das funções de atualização dos contadores de artes e vídeos
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

  // --------------------------
  //       SALVAR DADOS
  // --------------------------
  Future<void> _saveCompany() async {
    final phoneDigits = _onlyDigits(_tfWhatsPhoneController.text);
    if (phoneDigits.length < 10 || phoneDigits.length > 15) {
      showErrorDialog(
        context,
        "Informe o número com DDI (sem +), ex: 5546991073494",
        "Atenção",
      );
      return;
    }
    if (widget.companyId.isEmpty) {
      showErrorDialog(context, "Falha ao carregar usuário", "Atenção");
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      // Obtém a URL da imagem (seja a nova ou a já existente, ou gerada automaticamente)
      String? updatedPhotoUrl = await _updateCompanyImage();
      final photoUrl = updatedPhotoUrl; // Garantindo que photoUrl seja atualizado

      final rights = Map<String, bool>.from(accessRights)
        ..['gerenciarParceiros'] = false
        ..['criarCampanha'] = false
        ..['criarForm'] = false;

      // Atualiza os dados da empresa no Firestore, incluindo o campo photoUrl
      await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.companyId)
          .set({
        'NomeEmpresa'     : _model.tfCompanyTextController.text,
        'contract'        : _model.tfContractTextController.text,
        'countArtsValue'  : _model.countArtsValue,
        'countVideosValue': _model.countVideosValue,
        'photoUrl'        : photoUrl,
      }, SetOptions(merge: true));

      await _savePhoneConfig(widget.companyId);

// 🔒 Apenas campos flat na raiz (inclui mod*); nada de "accessRights" aninhado, nada em "users"
      await _savePermissionsFlat();

      Navigator.pop(context);
      showErrorDialog(context, "Parceiro atualizado com sucesso!", "Sucesso");

    } catch (e) {
      print("Erro ao atualizar parceiro: $e");
      showErrorDialog(context, "Erro ao atualizar parceiro", "Erro");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --------------------------
  //   UPLOAD/DELETE DA IMAGEM
  // --------------------------
  Future<String?> _updateCompanyImage() async {
    final storageRef = FirebaseStorage.instance
        .ref('${widget.companyId}/imagens/user_photo.jpg');

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

  // --------------------------
  //   GERA INICIAIS E AVATAR
  // --------------------------
  String _generateInitials() {
    final text = widget.nomeEmpresa.trim();
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

  // --------------------------
  //   WIDGET DO AVATAR
  // --------------------------
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

  // --------------------------
  // SELECIONAR IMAGEM
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

  // --------------------------
  //   BUILD
  // --------------------------
  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
                                  color: Theme.of(context).colorScheme.onBackground,
                                  size: 18),
                              const SizedBox(width: 4),
                              Text('Voltar',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Editar Parceiro',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSecondary)),
                      ],
                    ),
                    Stack(
                      children: [
                        _isLoading
                            ? const CircularProgressIndicator()
                            : IconButton(
                          icon: Icon(Icons.save_as_sharp,
                              color: Theme.of(context).colorScheme.onBackground,
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
          body: isDesktop
              ? Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1850),
              child: _buildMainContent(context, uid),
            ),
          )
              : _buildMainContent(context, uid),
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, String uid) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Avatar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: _buildImagePicker(),
            ),
            // Nome da Empresa
            _buildCompanyTextField(),
            // Email (desabilitado)
            _buildEmailTextField(),
            // Contrato
            _buildContractTextField(),
            // CNPJ (desabilitado)
            _buildCnpjTextField(),
            // Fundação (desabilitado)
            _buildBirthTextField(),

            // --- WhatsApp / Z-API ---
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

            // Botão Alterar Senha (se permitido)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('empresas').doc(uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }
                if (snapshot.hasError) {
                  return const Text('Erro ao carregar dados');
                }
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  bool canChangePassword = data?['alterarSenha'] ?? false;
                  if (canChangePassword) {
                    return Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
                      child: ElevatedButton.icon(
                        onPressed: _isChangingPassword ? null : _showChangePasswordSheet,
                        icon: Icon(Icons.settings_backup_restore_rounded,
                            color: Theme.of(context).colorScheme.outline,
                            size: 20),
                        label: Text(
                          'Alterar senha',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          side: const BorderSide(
                            color: Colors.transparent,
                            width: 1,
                          ),
                        ),
                      ),
                    );
                  }
                }
                return const SizedBox.shrink();
              },
            )
          ],
        ),
      ),
    );
  }

  // --------------------------
  // CAMPOS INDIVIDUAIS
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
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.corporate_fare,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
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
                enabled: false,
                decoration: InputDecoration(
                  hintText: 'Digite o email da empresa',
                  hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSecondary),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.mail,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.start,
                keyboardType: TextInputType.emailAddress,
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
                      color: Theme.of(context).colorScheme.onSecondary),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.import_contacts,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
                enabled: false,
                decoration: InputDecoration(
                  hintText: 'Digite o CNPJ da empresa',
                  hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSecondary),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.contact_emergency_sharp,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
                ),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.start,
                inputFormatters: [_model.tfCnpjMask],
                keyboardType: TextInputType.number,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthTextField() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
              child: TextFormField(
                controller: _model.tfBirthTextController,
                autofocus: true,
                enabled: false,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.calendar_month,
                      color: Theme.of(context).colorScheme.tertiary, size: 20),
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
                  hintText: 'Número do WhatsApp com DDI (sem +). Ex: 5546991073494',
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
                    Icons.memory,
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
                    Icons.vpn_key,
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
                    Icons.shield,
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordSheet() {
    showModalBottomSheet(
      backgroundColor: Theme.of(context).colorScheme.background,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      builder: (_) {
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
}