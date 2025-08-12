/* ----------------  IMPORTS  ---------------- */
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
  Uint8List? _croppedData;               // caso usuário troque a foto
  String?   _photoUrl;                   // URL original ou recém-upload
  final _editorKey = GlobalKey<ExtendedImageEditorState>();

  /* ───────── estado geral ───────── */
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtl.text = widget.data['nome'] ?? '';
    _descCtl.text = widget.data['descricao'] ?? '';
    _type         = widget.data['tipo'] ?? 'Físico';
    _photoUrl     = widget.data['foto'] as String?;
  }

  /* ----------------  UI helpers  ---------------- */
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
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        style: TextStyle(
            fontFamily: 'Poppins', fontSize: 14, color: cs.onSecondary),
      ),
    );
  }

  Widget _avatar() {
    final cs   = Theme.of(context).colorScheme;
    final img  = _croppedData ??
        (_photoUrl != null ? NetworkImage(_photoUrl!) : null);
    return GestureDetector(
      onTap: _pickReplacePhoto,
      child: CircleAvatar(
        radius: 50,
        backgroundColor: cs.secondary,
        backgroundImage: img is Uint8List ? MemoryImage(img) : img as ImageProvider?,
        child: img == null
            ? Icon(Icons.photo_camera,
            size: 40, color: Colors.white.withOpacity(.8))
            : null,
      ),
    );
  }

  Future<void> _pickReplacePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    _crop(bytes);
  }

  Future<void> _crop(Uint8List img) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 400,
          height: 400,
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
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () async {
                final st  = _editorKey.currentState;
                final rect= st?.getCropRect();
                final raw = st?.rawImageData;
                if (st == null || rect == null || raw == null) return;
                final codec   = await ui.instantiateImageCodec(raw);
                final frame   = await codec.getNextFrame();
                final recorder= ui.PictureRecorder();
                final canvas  = Canvas(recorder, rect);
                canvas.drawImageRect(frame.image, rect,
                    Rect.fromLTWH(0,0,rect.width,rect.height), Paint());
                final imgOut  = await recorder
                    .endRecording()
                    .toImage(rect.width.toInt(), rect.height.toInt());
                final data    = await imgOut.toByteData(
                    format: ui.ImageByteFormat.png);
                setState(()=> _croppedData = data!.buffer.asUint8List());
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Cortar'))
        ],
      ),
    );
  }

  /* ----------------  SAVE  ---------------- */
  Future<void> _save() async {
    setState(()=> _saving = true);
    try {
      final uid  = context.read<AuthProvider>().user!.uid;
      final udoc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final companyId = (udoc['createdBy'] as String?)?.isNotEmpty == true
          ? udoc['createdBy'] as String
          : uid;

      final prodRef = FirebaseFirestore.instance
          .collection('empresas')
          .doc(companyId)
          .collection('produtos')
          .doc(widget.prodId);

      /* ––– se trocou a imagem, faz upload e pega nova URL ––– */
      String? fotoUrl = _photoUrl;
      if (_croppedData != null) {
        final path = '$companyId/produtos/${widget.prodId}/foto.png';
        final ref  = FirebaseStorage.instance.ref().child(path);
        await ref.putData(_croppedData!, SettableMetadata(contentType: 'image/png'));
        fotoUrl = await ref.getDownloadURL();
      }

      await prodRef.update({
        'nome'      : _nameCtl.text.trim(),
        'descricao' : _descCtl.text.trim(),
        'tipo'      : _type,
        if (fotoUrl != null) 'foto': fotoUrl,
        'updatedAt' : Timestamp.now(),
      });

      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Produto atualizado com sucesso!'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      showErrorDialog(context,'Falha ao atualizar produto','Erro');
    } finally {
      if (mounted) setState(()=> _saving = false);
    }
  }

  /* ----------------  BUILD  ---------------- */
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
            backgroundColor: cs.secondary,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    InkWell(
                      onTap: ()=> Navigator.pop(context),
                      child: Row(children: [
                        Icon(Icons.arrow_back_ios_new,
                            size: 18, color: cs.onBackground),
                        const SizedBox(width: 4),
                        Text('Voltar',
                            style: TextStyle(
                                color: cs.onSecondary, fontSize: 14)),
                      ]),
                    ),
                    const Spacer(),
                    const Text('Editar Produto',
                        style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700))
                  ],
                ),
              ),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                _avatar(),
                _field(_nameCtl, 'Nome do produto'),
                _field(_descCtl, 'Descrição do produto', maxLines: 3),

                // ─── tipo (Dropdown) ───
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: DropdownButtonFormField2<String>(
                    value: _type,
                    isExpanded: true,
                    onChanged: (v) => setState(() => _type = v!),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(
                        color: cs.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    iconStyleData: IconStyleData(
                      icon: Icon(Icons.keyboard_arrow_down,
                          color: cs.onSecondary),
                      iconSize: 22,
                    ),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: cs.onSecondary,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'Físico', child: Text('Físico')),
                      DropdownMenuItem(
                          value: 'Digital', child: Text('Digital')),
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
                        borderRadius: BorderRadius.circular(25)),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}