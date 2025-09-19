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

  // ===== NOVO: módulos exibidos na tabbar =====
  final bool modChats;
  final bool modIndicadores;
  final bool modPainel;
  final bool modRelatorios; // se você usa a aba Relatórios

  // ===== NOVO: permissões internas do Painel =====
  final bool gerenciarParceiros;
  final bool gerenciarColaboradores;
  final bool criarForm;
  final bool criarCampanha;
  final bool gerenciarProdutos;

  // ===== Mantidos (outras telas) =====
  final bool leads;
  final bool copiarTelefones;
  final bool executarAPIs;

  EditCollaborators({
    required this.collaboratorId,
    required this.name,
    required this.email,
    required this.role,
    required this.birth,

    // módulos
    required this.modChats,
    required this.modIndicadores,
    required this.modPainel,
    this.modRelatorios = false,

    // internas painel
    this.gerenciarParceiros = false,
    this.gerenciarColaboradores = false,
    this.criarForm = false,
    this.criarCampanha = false,
    this.gerenciarProdutos = false,

    // outros
    this.leads = false,
    this.copiarTelefones = false,
    this.executarAPIs = false,
  });

  @override
  _EditCollaboratorsState createState() => _EditCollaboratorsState();
}

class _EditCollaboratorsState extends State<EditCollaborators> {
  final FirestoreService _firestoreService = FirestoreService();
  late AddCompanyModel _model;
  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _croppedData;
  String? _photoUrl;
  final GlobalKey<ExtendedImageEditorState> _editorKey = GlobalKey<ExtendedImageEditorState>();

  late Color _randomColor;
  double _scrollOffset = 0.0;

  // ===== NOVO: mapa de permissões unificado =====
  Map<String, bool> accessRights = {
    // MÓDULOS
    'modChats': true,
    'modIndicadores': true,
    'modPainel': false,
    'modRelatorios': false,

    // INTERNAS (Painel)
    'gerenciarParceiros': false,
    'gerenciarColaboradores': false,
    'criarForm': false,
    'criarCampanha': false,
    'gerenciarProdutos': false,

    // OUTROS
    'leads': false,
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

    _nameController  = TextEditingController(text: widget.name);
    _emailController = TextEditingController(text: widget.email);
    _roleController  = TextEditingController(text: widget.role);

    final formattedBirth = widget.birth.replaceAll('-', '/');
    _birthController = TextEditingController(text: formattedBirth);

    // Preenche o mapa a partir das props novas
    accessRights['modChats']        = widget.modChats;
    accessRights['modIndicadores']  = widget.modIndicadores;
    accessRights['modPainel']       = widget.modPainel;
    accessRights['modRelatorios']   = widget.modRelatorios;

    accessRights['gerenciarParceiros']     = widget.gerenciarParceiros;
    accessRights['gerenciarColaboradores'] = widget.gerenciarColaboradores;
    accessRights['criarForm']              = widget.criarForm;
    accessRights['criarCampanha']          = widget.criarCampanha;
    accessRights['gerenciarProdutos']      = widget.gerenciarProdutos;

    accessRights['leads']           = widget.leads;
    accessRights['copiarTelefones'] = widget.copiarTelefones;
    accessRights['executarAPIs']    = widget.executarAPIs;

    _randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];
    _loadCollaboratorPhoto();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _roleController.dispose();
    _birthController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadCollaboratorPhoto() async {
    try {
      final ref = FirebaseStorage.instance
          .ref('${widget.collaboratorId}/imagens/user_photo.jpg');
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _photoUrl = url);
    } catch (_) {
      if (!mounted) return;
      setState(() => _photoUrl = null);
    }
  }

  // ===== Regras de consistência entre módulo Painel e sub-permissões =====
  void _setPerm(String key, bool value) {
    setState(() {
      accessRights[key] = value;

      // desligou o módulo Painel => zera sub-permissões
      if (key == 'modPainel' && value == false) {
        accessRights['gerenciarParceiros'] = false;
        accessRights['gerenciarColaboradores'] = false;
        accessRights['criarForm'] = false;
        accessRights['criarCampanha'] = false;
        accessRights['gerenciarProdutos'] = false;
      }

      // ligou qualquer sub-permissão => liga o módulo Painel
      const subs = [
        'gerenciarParceiros',
        'gerenciarColaboradores',
        'criarForm',
        'criarCampanha',
        'gerenciarProdutos',
      ];
      if (subs.contains(key) && value == true) {
        accessRights['modPainel'] = true;
      }
    });
  }

  Widget _buildPermissionsList() {
    final cs = Theme.of(context).colorScheme;

    CheckboxListTile cb({
      required String keyName,
      required String label,
    }) {
      return CheckboxListTile(
        title: Text(label, style: TextStyle(
          fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 14,
          color: cs.onSecondary,
        )),
        value: accessRights[keyName] ?? false,
        onChanged: (v) => _setPerm(keyName, v ?? false),
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
        cb(keyName: 'modRelatorios',   label: 'Relatórios'),

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

  Future<void> _saveCollaborator() async {
    setState(() => _isLoading = true);

    if (widget.collaboratorId.isEmpty) {
      showErrorDialog(context, "Falha ao carregar usuário", "Atenção");
      setState(() => _isLoading = false);
      return;
    }

    try {
      final photoUrl = await _updateCollaboratorImage();

      // Sanitiza: se modPainel false, limpa sub-permissões
      final rights = Map<String, bool>.from(accessRights);
      if (!(rights['modPainel'] ?? false)) {
        for (final k in ['gerenciarParceiros','gerenciarColaboradores','criarForm','criarCampanha','gerenciarProdutos']) {
          rights[k] = false;
        }
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.collaboratorId)
          .set({
        'name' : _nameController.text,
        'email': _emailController.text,
        'role' : _roleController.text,
        'photoUrl': photoUrl,

        // ===== grava o novo shape =====
        'modChats'       : rights['modChats'] ?? true,
        'modIndicadores' : rights['modIndicadores'] ?? true,
        'modPainel'      : rights['modPainel'] ?? false,
        'modRelatorios'  : rights['modRelatorios'] ?? false,

        'gerenciarParceiros'     : rights['gerenciarParceiros'] ?? false,
        'gerenciarColaboradores' : rights['gerenciarColaboradores'] ?? false,
        'criarForm'              : rights['criarForm'] ?? false,
        'criarCampanha'          : rights['criarCampanha'] ?? false,
        'gerenciarProdutos' : rights['gerenciarProdutos'] ?? false,

        'leads'           : rights['leads'] ?? false,
        'copiarTelefones' : rights['copiarTelefones'] ?? false,
        'executarAPIs'    : rights['executarAPIs'] ?? false,
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context);
      showErrorDialog(context, "Colaborador atualizado com sucesso!", "Sucesso");
    } catch (e) {
      showErrorDialog(context, "Falha ao atualizar colaborador, tente novamente mais tarde", "Atenção");
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _updateCollaboratorImage() async {
    final storageRef = FirebaseStorage.instance
        .ref('${widget.collaboratorId}/imagens/user_photo.jpg');

    if (_croppedData != null) {
      try {
        await storageRef.putData(_croppedData!);
        final url = await storageRef.getDownloadURL();
        if (!mounted) return url;
        setState(() => _photoUrl = url);
        return url;
      } catch (_) {
        return null;
      }
    } else {
      if (_photoUrl != null) return _photoUrl;
      try {
        final initials = _generateInitials();
        final imageData = await _generateAvatar(initials);
        await storageRef.putData(imageData);
        final url = await storageRef.getDownloadURL();
        if (!mounted) return url;
        setState(() => _photoUrl = url);
        return url;
      } catch (_) {
        return null;
      }
    }
  }

  String _generateInitials() {
    final text = _nameController.text.trim();
    if (text.isEmpty) return "NA";
    final parts = text.split(" ");
    final first = parts.first.isNotEmpty ? parts.first[0] : "N";
    final last  = parts.length > 1 ? parts.last[0] : first;
    return (first + last).toUpperCase();
  }

  Future<Uint8List> _generateAvatar(String initials) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 100, 100));
    final paint = Paint()..color = Colors.primaries[Random().nextInt(Colors.primaries.length)];
    canvas.drawCircle(const Offset(50, 50), 50, paint);
    final tp = TextPainter(
      text: TextSpan(text: initials, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(50 - tp.width / 2, 50 - tp.height / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(100, 100);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Widget _buildImagePicker() {
    final hasCropped = _croppedData != null;
    final hasPhoto   = _photoUrl != null;

    ImageProvider? provider;
    if (hasCropped) {
      provider = MemoryImage(_croppedData!);
    } else if (hasPhoto) {
      provider = NetworkImage(_photoUrl!);
    }

    return GestureDetector(
      onTap: _showImagePickerOptions,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: provider == null ? _randomColor : Colors.grey[300],
        backgroundImage: provider,
        child: provider == null
            ? Text(_generateInitials(), style: const TextStyle(fontSize: 40, color: Colors.white))
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
                title: Text('Escolher da Galeria',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: Theme.of(context).colorScheme.onSecondary)),
                onTap: () { Navigator.of(context).pop(); _pickImage(ImageSource.gallery); },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text('Tirar Foto',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: Theme.of(context).colorScheme.onSecondary)),
                onTap: () { Navigator.of(context).pop(); _pickImage(ImageSource.camera); },
              ),
              if (_photoUrl != null || _croppedData != null)
                ListTile(
                  leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                  title: Text('Remover Foto',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: Theme.of(context).colorScheme.error)),
                  onTap: () { Navigator.of(context).pop(); setState(() { _croppedData = null; _photoUrl = null; }); },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;
    _selectedImage = picked;
    final bytes = await picked.readAsBytes();
    _cropImage(bytes);
  }

  Future<Uint8List?> _cropImageFromEditor() async {
    final state = _editorKey.currentState;
    if (state == null) return null;
    final cropRect = state.getCropRect();
    final rawData  = state.rawImageData;
    if (cropRect == null || rawData == null) return null;
    final codec = await ui.instantiateImageCodec(rawData);
    final frame = await codec.getNextFrame();
    final img   = frame.image;
    final rec   = ui.PictureRecorder();
    final can   = Canvas(rec);
    can.drawImageRect(img, cropRect, Rect.fromLTWH(0, 0, cropRect.width, cropRect.height), Paint());
    final out   = await rec.endRecording().toImage(cropRect.width.toInt(), cropRect.height.toInt());
    final bd    = await out.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  }

  Future<void> _cropImage(Uint8List imageData) async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 500, height: 500,
          child: ExtendedImage.memory(
            imageData,
            fit: BoxFit.contain,
            mode: ExtendedImageMode.editor,
            extendedImageEditorKey: _editorKey,
            initEditorConfigHandler: (_) => EditorConfig(
              cropRectPadding: const EdgeInsets.all(20),
              maxScale: 8.0,
              cropAspectRatio: 1.0,
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text("Cancelar", style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                color: Theme.of(context).colorScheme.onSecondary)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text("Cortar", style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                color: Theme.of(context).colorScheme.onSecondary)),
            onPressed: () async {
              final cropped = await _cropImageFromEditor();
              if (cropped != null) setState(() => _croppedData = cropped);
              if (mounted) Navigator.of(context).pop();
            },
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
      builder: (context) {
        return ChangePasswordSheet(
          targetUid: widget.collaboratorId,
          onClose: () {
            if (!mounted) return;
            setState(() => _isChangingPassword = false);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;
    final appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
                                  color: Theme.of(context).colorScheme.onBackground, size: 18),
                              const SizedBox(width: 4),
                              Text('Voltar', style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 14,
                                color: Theme.of(context).colorScheme.onSecondary,
                              )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Editar Colaborador', style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSecondary,
                        )),
                      ],
                    ),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : IconButton(
                      icon: Icon(Icons.save_as_sharp,
                          color: Theme.of(context).colorScheme.onBackground, size: 30),
                      onPressed: _isLoading ? null : _saveCollaborator,
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
              child: SafeArea(top: true, child: SingleChildScrollView(child: _buildMainContent(uid))),
            ),
          )
              : SafeArea(top: true, child: SingleChildScrollView(child: _buildMainContent(uid))),
        ),
      ),
    );
  }

  Widget _buildMainContent(String uid) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 20.0), child: _buildImagePicker()),

        // Nome
        _textFieldBlock(
          label: 'Nome do Colaborador',
          controller: _nameController,
          icon: Icons.person,
        ),

        // Email (lock)
        _textFieldBlock(
          label: 'Email do Colaborador',
          controller: _emailController,
          icon: Icons.mail,
          enabled: false,
          hint: 'Digite o email do colaborador',
        ),

        // Cargo
        _textFieldBlock(
          label: 'Cargo do Colaborador',
          controller: _roleController,
          icon: Icons.business_center,
          hint: 'Digite o cargo do colaborador',
        ),

        // Nascimento (lock)
        _textFieldBlock(
          label: 'Data de Nascimento',
          controller: _birthController,
          icon: Icons.calendar_month,
          enabled: false,
          hint: 'Selecione a data de nascimento',
        ),

        // Título permissões
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Marque os acessos do colaborador:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSecondary)),
          ),
        ),

        // Lista de permissões nova
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 0, 0),
          child: _buildPermissionsList(),
        ),

        // Alterar senha (controlado por empresas/{uid}.alterarSenha)
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('empresas').doc(uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 24, child: CircularProgressIndicator());
            if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();

            final canChange = snapshot.data!.get('alterarSenha') ?? false;
            if (!canChange) return const SizedBox.shrink();

            return Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: ElevatedButton.icon(
                  onPressed: _isChangingPassword ? null : _showChangePasswordSheet,
                  icon: Icon(Icons.settings_backup_restore_rounded, color: cs.outline, size: 25),
                  label: Text('Alterar senha', style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w600, color: cs.outline)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsetsDirectional.fromSTEB(30, 15, 30, 15),
                    backgroundColor: cs.primary,
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _textFieldBlock({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
    bool enabled = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional(0, 0),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSecondary)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: controller,
                      enabled: enabled,
                      decoration: InputDecoration(
                        hintText: hint ?? 'Digite aqui',
                        hintStyle: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: 14, color: cs.onSecondary),
                        filled: true,
                        fillColor: cs.secondary,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        prefixIcon: Icon(icon, color: cs.tertiary, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w500, color: cs.onSecondary),
                      textAlign: TextAlign.start,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}