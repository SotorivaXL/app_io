/* ----------------  IMPORTS  ---------------- */
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:extended_image/extended_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

class AddProduct extends StatefulWidget {
  const AddProduct({Key? key}) : super(key: key);

  @override
  State<AddProduct> createState() => _AddProductState();
}

class _AddProductState extends State<AddProduct> {
  /* ───────── texto ───────── */
  final _nameCtl = TextEditingController();
  final _descCtl = TextEditingController();
  String _type = 'Físico';

  /* ───────── imagem ───────── */
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _croppedData;
  String? _photoUrl; // depois do upload
  final _editorKey = GlobalKey<ExtendedImageEditorState>();
  late Color _randomColor;

  /* ───────── estado geral ───────── */
  bool _saving = false;

  /* ───────── scroll para AppBar colapsável ───────── */
  final _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _randomColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];

    _scrollController.addListener(() {
      if (!mounted) return;
      setState(() => _scrollOffset = _scrollController.offset);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  /*------------------------  UI helpers  ------------------------*/
  InputDecoration _decoration({
    required String hint,
    required ColorScheme cs,
    IconData? prefix,
    bool isDesktop = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: cs.onSecondary,
      ),
      filled: true,
      fillColor: cs.secondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      prefixIcon: prefix != null
          ? Icon(prefix, color: cs.tertiary, size: 20)
          : null,
      contentPadding:
      isDesktop ? const EdgeInsets.symmetric(vertical: 25) : const EdgeInsets.symmetric(vertical: 15),
    );
  }

  Widget _textField({
    required TextEditingController ctl,
    required String hint,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 1024;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        controller: ctl,
        decoration: _decoration(hint: hint, cs: cs, prefix: icon, isDesktop: isDesktop),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: cs.onSecondary,
        ),
      ),
    );
  }

  Widget _multilineField({
    required TextEditingController ctl,
    required String hint,
    required IconData icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 1024;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        controller: ctl,
        maxLines: 3,
        decoration: _decoration(hint: hint, cs: cs, prefix: icon, isDesktop: isDesktop),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: cs.onSecondary,
        ),
      ),
    );
  }

  /*------------------  Avatar / Picker  ------------------*/
  Widget _avatar() {
    final cs = Theme.of(context).colorScheme;
    final hasImage = _croppedData != null;
    return GestureDetector(
      onTap: _showPicker,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: hasImage ? cs.secondary : _randomColor,
        backgroundImage: hasImage ? MemoryImage(_croppedData!) : null,
        child: hasImage
            ? null
            : Icon(Icons.photo_camera, size: 40, color: Colors.white.withOpacity(.8)),
      ),
    );
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text('Galeria', style: TextStyle(fontFamily: 'Poppins', color: cs.onSecondary)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text('Câmera', style: TextStyle(fontFamily: 'Poppins', color: cs.onSecondary)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            if (_croppedData != null || _photoUrl != null)
              ListTile(
                leading: Icon(Icons.delete, color: cs.error),
                title: Text('Remover', style: TextStyle(fontFamily: 'Poppins', color: cs.error)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _croppedData = null;
                    _photoUrl = null;
                  });
                },
              )
          ]),
        );
      },
    );
  }

  Future<void> _pick(ImageSource src) async {
    final file = await _picker.pickImage(source: src);
    if (file == null) return;
    _selectedImage = file;
    final bytes = await file.readAsBytes();
    _crop(bytes);
  }

  Future<void> _crop(Uint8List img) async {
    showDialog(
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
              cropAspectRatio: 1.0,
              maxScale: 8,
              cropRectPadding: const EdgeInsets.all(20),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final state = _editorKey.currentState;
              if (state == null) return;
              final rect = state.getCropRect();
              final raw = state.rawImageData;
              if (rect == null || raw == null) return;

              final codec = await ui.instantiateImageCodec(raw);
              final frame = await codec.getNextFrame();
              final recorder = ui.PictureRecorder();
              final canvas = Canvas(recorder, rect);
              canvas.drawImageRect(
                frame.image,
                rect,
                Rect.fromLTWH(0, 0, rect.width, rect.height),
                Paint(),
              );
              final cropped = await recorder.endRecording().toImage(
                rect.width.toInt(),
                rect.height.toInt(),
              );
              final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
              if (!mounted) return;
              setState(() => _croppedData = data!.buffer.asUint8List());
              Navigator.pop(context);
            },
            child: Text('Cortar', style: TextStyle(color: Theme.of(context).colorScheme.onSecondary)),
          ),
        ],
      ),
    );
  }

  Future<String> _resolveCompanyIdSafely(BuildContext context) async {
    final authProv = context.read<AuthProvider?>();
    final user = authProv?.user;
    if (user == null) {
      throw Exception('Usuário não autenticado (AuthProvider.user == null).');
    }

    final udoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = udoc.data() ?? <String, dynamic>{};
    final createdBy = (data['createdBy'] as String?)?.trim();

    return (createdBy != null && createdBy.isNotEmpty) ? createdBy : user.uid;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (_nameCtl.text.trim().isEmpty) {
      showErrorDialog(context, 'Informe o nome do produto', 'Atenção');
      return;
    }

    setState(() => _saving = true);
    try {
      final companyId = await _resolveCompanyIdSafely(context);

      final docRef = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(companyId)
          .collection('produtos')
          .add({
        'nome': _nameCtl.text.trim(),
        'descricao': _descCtl.text.trim(),
        'tipo': _type,
        'createdAt': Timestamp.now(),
      });

      if (_croppedData != null) {
        final path = '$companyId/produtos/${docRef.id}/foto.png';
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putData(_croppedData!);
        final fotoUrl = await ref.getDownloadURL();
        await docRef.update({'foto': fotoUrl});
      }

      if (!mounted) return;
      Navigator.pop(context); // volta para a lista
    } catch (e, st) {
      // ignore: avoid_print
      print('Erro ao salvar produto: $e');
      // ignore: avoid_print
      print(st);
      if (!mounted) return;
      showErrorDialog(
        context,
        'Falha ao salvar o produto.\n\nDetalhe técnico:\n$e',
        'Erro',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /*------------------------  BUILD ------------------------*/
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width > 1024;
    final appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(56.0, 100.0);

    final form = Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        const SizedBox(height: 20),
        _avatar(),
        _textField(ctl: _nameCtl, hint: 'Nome do produto', icon: Icons.inventory_2),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: TextField(
            controller: _descCtl,
            maxLines: 1,
            textAlignVertical: TextAlignVertical.center,
            decoration: _decoration(
              hint: 'Descrição do produto',
              cs: cs,
              prefix: Icons.notes,
              isDesktop: isDesktop,
            ).copyWith(
              isDense: true,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(Icons.notes, color: cs.tertiary, size: 20),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              contentPadding: isDesktop
                  ? const EdgeInsets.symmetric(vertical: 20)
                  : const EdgeInsets.symmetric(vertical: 14),
            ),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.onSecondary,
            ),
          ),
        ),
        // ─── tipo (Dropdown) ───
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: DropdownButtonFormField2<String>(
            value: _type,
            isExpanded: true,
            onChanged: (v) => setState(() => _type = v!),
            decoration: InputDecoration(
              hintText: 'Tipo do produto',
              hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: cs.onSecondary),
              filled: true,
              fillColor: cs.secondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(Icons.category, color: cs.tertiary, size: 20),
              contentPadding: isDesktop
                  ? const EdgeInsets.symmetric(vertical: 25)
                  : const EdgeInsets.symmetric(vertical: 15),
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
            style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: cs.onSecondary),
            items: const [
              DropdownMenuItem(value: 'Físico', child: Text('Físico')),
              DropdownMenuItem(value: 'Digital', child: Text('Digital')),
            ],
          ),
        ),
        const SizedBox(height: 30),
      ],
    );

    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: cs.background,
          appBar: AppBar(
            toolbarHeight: appBarHeight,
            automaticallyImplyLeading: false,
            surfaceTintColor: Colors.transparent,
            backgroundColor: cs.secondary,
            flexibleSpace: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // voltar + título
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back_ios_new, size: 18, color: cs.onBackground),
                              const SizedBox(width: 4),
                              Text('Voltar', style: TextStyle(color: cs.onSecondary, fontSize: 14)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Adicionar Produto',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: cs.onSecondary,
                          ),
                        ),
                      ],
                    ),
                    // botão salvar (ou loading)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_saving)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.8),
                          )
                        else
                          IconButton(
                            icon: Icon(Icons.save_as_sharp, color: cs.onBackground, size: 30),
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
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: form,
                ),
              ),
            ),
          )
              : SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: form,
            ),
          ),
        ),
      ),
    );
  }
}