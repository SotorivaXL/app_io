import 'dart:io';
import 'dart:typed_data';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

class ImageCrop extends StatefulWidget {
  final File imageFile;

  const ImageCrop({Key? key, required this.imageFile}) : super(key: key);

  @override
  _ImageCropState createState() => _ImageCropState();
}

class _ImageCropState extends State<ImageCrop> {
  // Chave para acessar o editor
  final GlobalKey<ExtendedImageEditorState> _editorKey = GlobalKey<ExtendedImageEditorState>();

  Future<void> _cropImage() async {
    final Uint8List? croppedData = await _editorKey.currentState?.rawImageData;
    if (croppedData != null) {
      // Aqui você pode utilizar os bytes (croppedData) da imagem recortada,
      // por exemplo, fazer upload para o Firebase Storage.
      print('Imagem recortada com sucesso, tamanho: ${croppedData.lengthInBytes}');
      // Navigator.pop(context, croppedData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Cortar Imagem"),
        actions: [
          IconButton(
            icon: Icon(Icons.check),
            onPressed: _cropImage,
          )
        ],
      ),
      body: ExtendedImage.file(
        widget.imageFile,
        fit: BoxFit.contain,
        mode: ExtendedImageMode.editor,
        extendedImageEditorKey: _editorKey,
        initEditorConfigHandler: (state) {
          return EditorConfig(
            maxScale: 8.0,
            cropRectPadding: EdgeInsets.all(20.0),
            hitTestSize: 20.0,
            cropAspectRatio: 1.0, // Exemplo: quadrado
          );
        },
      ),
    );
  }
}