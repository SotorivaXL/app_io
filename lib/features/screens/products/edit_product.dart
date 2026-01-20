/* ----------------  IMPORTS  ---------------- */
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:extended_image/extended_image.dart';
import 'package:provider/provider.dart';

class EditProduct extends StatefulWidget {
  final String prodId;
  final Map<String, dynamic> data;
  const EditProduct({Key? key, required this.prodId, required this.data})
      : super(key: key);

  @override
  State<EditProduct> createState() => _EditProductState();
}

class _EditProductState extends State<EditProduct> {
  /* ───────── texto ───────── */
  final _nameCtl = TextEditingController();
  final _descCtl = TextEditingController();
  late String _type;

  /* ───────── imagem ───────── */
  final ImagePicker _picker = ImagePicker();
  Uint8List? _croppedData;     // se usuário trocar a foto
  String?   _photoUrl;         // URL atual (ou nova após upload)
  final _editorKey = GlobalKey<ExtendedImageEditorState>();
  late Color _randomColor;

  /* ───────── estado geral ───────── */
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtl.text = (widget.data['nome'] ?? '').toString();
    _descCtl.text = (widget.data['descricao'] ?? '').toString();
    _type         = (widget.data['tipo'] ?? 'Físico').toString();
    _photoUrl     = (widget.data['foto'] as String?)?.trim();
    _randomColor  = Colors.primaries[Random().nextInt(Colors.primaries.length)];
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  /* ---------------- helpers visuais ---------------- */
  InputDecoration _baseDecoration({
    required ColorScheme cs,
    required String hint,
    IconData? prefixIcon,
    bool dense = true,
    EdgeInsets? contentPadding,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: cs.onSecondary,
      ),
      filled: true,
      fillColor: cs.secondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      isDense: dense,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: cs.tertiary, size: 20),
      contentPadding: contentPadding ?? const EdgeInsets.symmetric(vertical: 20),
    );
  }

  /// Campo single-line (ícone e hint alinhados)
  Widget _fieldOneLine({
    required TextEditingController ctl,
    required String hint,
    required IconData icon,
    required bool isDesktop,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        controller: ctl,
        maxLines: 1,
        textAlignVertical: TextAlignVertical.center,
        decoration: _baseDecoration(
          cs: cs,
          hint: hint,
          prefixIcon: icon,
          contentPadding:
          isDesktop ? const EdgeInsets.symmetric(vertical: 25) : null,
        ),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: cs.onSecondary,
        ),
      ),
    );
  }

  /// Campo multilinha com ícone alinhado ao topo do hint (usa `prefix`)
  Widget _fieldMultiline({
    required TextEditingController ctl,
    required String hint,
    required bool isDesktop,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        controller: ctl,
        minLines: 3,
        maxLines: 3,
        decoration: _baseDecoration(
          cs: cs,
          hint: hint,
          dense: false,
        ).copyWith(
          // usa `prefix` (não `prefixIcon`) para alinhar com o hint no topo
          prefix: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8, top: 2),
            child: Icon(Icons.notes, color: cs.tertiary, size: 18),
          ),
          // sem prefixIcon, ajusta manualmente o espaçamento do texto
          contentPadding: const EdgeInsets.fromLTRB(0, 14, 12, 14),
        ),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: cs.onSecondary,
        ),
      ),
    );
  }

  Widget _imagePicker() {
    final cs = Theme.of(context).colorScheme;
    final hasCropped = _croppedData != null;
    return GestureDetector(
      onTap: _showImagePickerOptions,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: hasCropped || (_photoUrl?.isNotEmpty ?? false)
            ? cs.secondary
            : _randomColor,
        backgroundImage: hasCropped
            ? MemoryImage(_croppedData!)
            : (_photoUrl?.isNotEmpty ?? false)
            ? NetworkImage(_photoUrl!)
            : null,
        child: (hasCropped || (_photoUrl?.isNotEmpty ?? false))
            ? null
            : Icon(Icons.photo_camera, size: 40, color: Colors.white.withOpacity(.9)),
      ),
    );
  }

  void _showImagePickerOptions() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text('Escolher da Galeria',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: cs.onSecondary)),
                onTap: () async {
                  Navigator.pop(context);
                  final x = await _picker.pickImage(source: ImageSource.gallery);
                  if (x == null) return;
                  final bytes = await x.readAsBytes();
                  _crop(bytes);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text('Tirar Foto',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: cs.onSecondary)),
                onTap: () async {
                  Navigator.pop(context);
                  final x = await _picker.pickImage(source: ImageSource.camera);
                  if (x == null) return;
                  final bytes = await x.readAsBytes();
                  _crop(bytes);
                },
              ),
              if (_croppedData != null || (_photoUrl?.isNotEmpty ?? false))
                ListTile(
                  leading: Icon(Icons.delete, color: cs.error),
                  title: Text('Remover Foto',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: cs.error)),
                  onTap: () {
                    Navigator.pop(context);
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

  Future<void> _crop(Uint8List img) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 500,
          height: 500,
          child: ExtendedImage.memory(
            img,
            fit: BoxFit.contain,
            mode: ExtendedImageMode.editor,
            extendedImageEditorKey: _editorKey,
            initEditorConfigHandler: (_) => EditorConfig(
              cropAspectRatio: 1,
              maxScale: 8,
              cropRectPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final st = _editorKey.currentState;
              final rect = st?.getCropRect();
              final raw  = st?.rawImageData;
              if (st == null || rect == null || raw == null) return;

              final codec   = await ui.instantiateImageCodec(raw);
              final frame   = await codec.getNextFrame();
              final recorder= ui.PictureRecorder();
              final canvas  = Canvas(recorder, rect);
              canvas.drawImageRect(
                frame.image,
                rect,
                Rect.fromLTWH(0, 0, rect.width, rect.height),
                Paint(),
              );
              final imgOut = await recorder.endRecording().toImage(
                rect.width.toInt(),
                rect.height.toInt(),
              );
              final data = await imgOut.toByteData(format: ui.ImageByteFormat.png);
              setState(() => _croppedData = data!.buffer.asUint8List());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Cortar'),
          ),
        ],
      ),
    );
  }

  /* ---------------- companyId (mesma lógica do AddProduct) ---------------- */
  Future<String> _resolveCompanyIdSafely(BuildContext context) async {
    final authProv = context.read<AuthProvider?>();
    final user = authProv?.user;
    if (user == null) {
      throw Exception('Usuário não autenticado (AuthProvider.user == null).');
    }

    final udoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = udoc.data() ?? <String, dynamic>{};
    final createdBy = (data['createdBy'] as String?)?.trim();

    return (createdBy != null && createdBy.isNotEmpty) ? createdBy : user.uid;
  }

  /* ---------------- SAVE ---------------- */
  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_nameCtl.text.trim().isEmpty) {
      showErrorDialog(context, 'Informe o nome do produto', 'Atenção');
      return;
    }

    setState(() => _saving = true);
    try {
      final companyId = await _resolveCompanyIdSafely(context);

      final prodRef = FirebaseFirestore.instance
          .collection('empresas')
          .doc(companyId)
          .collection('produtos')
          .doc(widget.prodId);

      // upload da foto (se mudou)
      String? fotoUrl = _photoUrl;
      if (_croppedData != null) {
        final path = '$companyId/produtos/${widget.prodId}/foto.png';
        final ref  = FirebaseStorage.instance.ref().child(path);
        await ref.putData(
          _croppedData!,
          SettableMetadata(contentType: 'image/png'),
        );
        fotoUrl = await ref.getDownloadURL();
      }

      await prodRef.update({
        'nome': _nameCtl.text.trim(),
        'descricao': _descCtl.text.trim(),
        'tipo': _type,
        if (fotoUrl != null) 'foto': fotoUrl,
        'updatedAt': Timestamp.now(),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e, st) {
      // debug útil
      // ignore: avoid_print
      print('Erro ao atualizar produto: $e\n$st');
      if (!mounted) return;
      showErrorDialog(
        context,
        'Falha ao atualizar o produto.\n\nDetalhe técnico:\n$e',
        'Erro',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /* ---------------- BUILD ---------------- */
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 100,
            automaticallyImplyLeading: false,
            surfaceTintColor: Colors.transparent,
            backgroundColor: cs.secondary,
            flexibleSpace: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Voltar + título (mesmo layout do AddCollaborators)
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
                                  color: cs.onBackground, size: 18),
                              const SizedBox(width: 4),
                              Text('Voltar',
                                  style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      color: cs.onSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Editar Produto',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: cs.onSecondary,
                          ),
                        ),
                      ],
                    ),
                    // Botão salvar à direita (stack igual ao add collaborators)
                    Stack(
                      children: [
                        _saving
                            ? const SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                            : IconButton(
                          icon: Icon(Icons.save_as_sharp,
                              color: cs.onBackground, size: 30),
                          onPressed: _saving ? null : _save,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          body: isDesktop
              ? Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: _content(isDesktop),
            ),
          )
              : _content(isDesktop),
        ),
      ),
    );
  }

  Widget _content(bool isDesktop) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _imagePicker(),
            _fieldOneLine(
              ctl: _nameCtl,
              hint: 'Nome do produto',
              icon: Icons.inventory_2,
              isDesktop: isDesktop,
            ),
            _fieldMultiline(
              ctl: _descCtl,
              hint: 'Descrição do produto',
              isDesktop: isDesktop,
            ),
            // Tipo (Dropdown) – mesmo visual
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: DropdownButtonFormField2<String>(
                value: _type,
                isExpanded: true,
                onChanged: (v) => setState(() => _type = v!),
                decoration: _baseDecoration(
                  cs: cs,
                  hint: 'Tipo do produto',
                  prefixIcon: Icons.category_outlined,
                  contentPadding:
                  isDesktop ? const EdgeInsets.symmetric(vertical: 25) : null,
                ),
                dropdownStyleData: DropdownStyleData(
                  decoration: BoxDecoration(
                    color: cs.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                iconStyleData: IconStyleData(
                  icon: Icon(Icons.keyboard_arrow_down, color: cs.onSecondary),
                  iconSize: 22,
                ),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: cs.onSecondary,
                ),
                items: const [
                  DropdownMenuItem(value: 'Físico', child: Text('Físico')),
                  DropdownMenuItem(value: 'Digital', child: Text('Digital')),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}