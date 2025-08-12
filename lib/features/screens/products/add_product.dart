/* ----------------  IMPORTS  ---------------- */
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:extended_image/extended_image.dart';
import 'package:provider/provider.dart';
import 'package:app_io/auth/providers/auth_provider.dart';

class AddProduct extends StatefulWidget {
  const AddProduct({Key? key}) : super(key: key);

  @override
  State<AddProduct> createState() => _AddProductState();
}

class _AddProductState extends State<AddProduct> {
  /* ───────── texto ───────── */
  final _nameCtl = TextEditingController();
  final _descCtl = TextEditingController();
  String _type   = 'Físico';

  /* ───────── imagem ───────── */
  final ImagePicker _picker = ImagePicker();
  XFile?     _selectedImage;
  Uint8List? _croppedData;
  String?    _photoUrl;                        // depois do upload
  final _editorKey = GlobalKey<ExtendedImageEditorState>();
  late Color _randomColor;

  /* ───────── estado geral ───────── */
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _randomColor = Colors
        .primaries[Random().nextInt(Colors.primaries.length)];
  }

  /*------------------------  UI helpers  ------------------------*/
  Widget _field(TextEditingController ctl, String hint,
      {int maxLines = 1}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: TextField(
        controller: ctl,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: cs.onSecondary),
          filled: true,
          fillColor: cs.secondary,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
        style: TextStyle(
            fontFamily: 'Poppins', fontSize: 14, color: cs.onSecondary),
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
            : Icon(Icons.photo_camera,
            size: 40, color: Colors.white.withOpacity(.8)),
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
              title: const Text('Galeria'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Câmera'),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
            if (_croppedData != null || _photoUrl != null)
              ListTile(
                leading: Icon(Icons.delete, color: cs.error),
                title: const Text('Remover'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _croppedData = null;
                    _photoUrl    = null;
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
    final bytes = await file.readAsBytes();
    _crop(bytes);
  }

  Future<void> _crop(Uint8List img) async {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 400,
            height: 400,
            child: ExtendedImage.memory(
              img,
              fit: BoxFit.contain,          //  ←  acrescentar esta linha
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
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () async {
                  final state = _editorKey.currentState;
                  if (state == null) return;
                  final rect = state.getCropRect();
                  final raw  = state.rawImageData;
                  if (rect == null || raw == null) return;
                  final codec =
                  await ui.instantiateImageCodec(raw);
                  final frame = await codec.getNextFrame();
                  final recorder = ui.PictureRecorder();
                  final canvas =
                  Canvas(recorder, rect);
                  canvas.drawImageRect(
                      frame.image,
                      rect,
                      Rect.fromLTWH(0, 0, rect.width, rect.height),
                      Paint());
                  final cropped = await recorder
                      .endRecording()
                      .toImage(rect.width.toInt(),
                      rect.height.toInt());
                  final data = await cropped.toByteData(
                      format: ui.ImageByteFormat.png);
                  setState(() => _croppedData =
                      data!.buffer.asUint8List());
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Cortar'))
          ],
        ));
  }

  /*------------------------  SAVE  ------------------------*/
  Future<void> _save() async {
    if (_nameCtl.text.trim().isEmpty) {
      showErrorDialog(context, 'Informe o nome do produto', 'Atenção');
      return;
    }
    setState(() => _saving = true);

    try {
      /* --- companyId do usuário atual --- */
      final uid   = context.read<AuthProvider>().user!.uid;
      final udoc  = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final companyId = (udoc['createdBy'] as String?)?.isNotEmpty == true
          ? udoc['createdBy'] as String
          : uid;

      /* --- cria doc vazio primeiro para ter o id --- */
      final docRef = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(companyId)
          .collection('produtos')
          .add({
        'nome'      : _nameCtl.text.trim(),
        'descricao' : _descCtl.text.trim(),
        'tipo'      : _type,
        'createdAt' : Timestamp.now(),
      });

      /* --- upload da imagem, se houver --- */
      String? fotoUrl;
      if (_croppedData != null) {
        final path =
            '$companyId/produtos/${docRef.id}/foto.png';
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putData(_croppedData!);
        fotoUrl = await ref.getDownloadURL();
        await docRef.update({'foto': fotoUrl});
      }

      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Produto criado com sucesso!'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      showErrorDialog(context, 'Falha ao salvar o produto', 'Erro');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /*------------------------  BUILD ------------------------*/
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ConnectivityBanner(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: cs.background,
          appBar: AppBar(
            toolbarHeight: 100,
            automaticallyImplyLeading: false,
            backgroundColor: cs.secondary,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Row(children: [
                        Icon(Icons.arrow_back_ios_new,
                            size: 18, color: cs.onBackground),
                        const SizedBox(width: 4),
                        Text('Voltar',
                            style:
                            TextStyle(color: cs.onSecondary, fontSize: 14))
                      ]),
                    ),
                    const Spacer(),
                    const Text('Adicionar Produto',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700))
                  ],
                ),
              ),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(children: [
              const SizedBox(height: 20),
              _avatar(),
              _field(_nameCtl, 'Nome do produto'),
              _field(_descCtl, 'Descrição do produto', maxLines: 3),
              // ─── tipo (Dropdown) ───
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),  // ⭢ mesmo padding
                child: DropdownButtonFormField2<String>(
                  value: _type,
                  isExpanded: true,                  // ocupa toda a largura
                  onChanged: (v) => setState(() => _type = v!),

                  /// decoração idêntica aos TextFields criados em _field()
                  decoration: InputDecoration(
                    hintText: 'Tipo do produto',
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: cs.onSecondary,
                    ),
                    filled: true,
                    fillColor: cs.secondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    // mesma altura interna
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),

                  // menu suspenso (DropDown) com mesmo visual
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
                    DropdownMenuItem(value: 'Físico' , child: Text('Físico')),
                    DropdownMenuItem(value: 'Digital', child: Text('Digital')),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _saving
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('SALVAR'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onSurface,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25))),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ),
      ),
    );
  }
}