// add_api_page.dart
import 'dart:async';

import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddApi extends StatefulWidget {
  final bool isEditing;
  final String? existingDocId;
  final Map<String, dynamic>? existingData;

  const AddApi({
    this.isEditing = false,
    this.existingDocId,
    this.existingData,
  });

  @override
  _AddApiState createState() => _AddApiState();
}

class _AddApiState extends State<AddApi> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _apiNameController = TextEditingController();
  final FocusNode _apiNameFocusNode = FocusNode();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _apiDescriptionFocusNode = FocusNode();
  final TextEditingController _documentNameController = TextEditingController();
  final FocusNode _apiDocumentNameFocusNode = FocusNode();

  List<Map<String, TextEditingController>> _keyValueFields = [];

  bool _isLoading = false;
  double _scrollOffset = 0.0;

  // Variáveis para o listener de permissão
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _permissionSubscription;
  bool _permissionRevokedShown = false;

  @override
  void initState() {
    super.initState();
    _initializeForm();
    _subscribePermissionListener();
  }

  void _initializeForm() {
    if (widget.isEditing && widget.existingData != null) {
      // Preenche os campos principais
      _apiNameController.text = widget.existingData!['name'] ?? '';
      _descriptionController.text = widget.existingData!['description'] ?? '';
      _documentNameController.text = widget.existingDocId ?? '';

      // Preenche os campos dinâmicos
      final dynamicFields = Map.from(widget.existingData!)
        ..remove('name')
        ..remove('description')
        ..remove('created_at')
        ..remove('updated_at');

      dynamicFields.forEach((key, value) {
        _keyValueFields.add({
          'key': TextEditingController(text: key),
          'value': TextEditingController(text: value.toString()),
        });
      });
    } else {
      _addKeyValueField();
    }
  }

  void _subscribePermissionListener() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    // Supondo que o usuário que pode editar/Adicionar API esteja cadastrado na coleção "empresas"
    final empresaDocRef = FirebaseFirestore.instance.collection('empresas').doc(user.uid);
    _permissionSubscription = empresaDocRef.snapshots().listen((docSnap) {
      final data = docSnap.data();
      // Se o documento não existir ou se 'isDevAccount' for false, a permissão foi revogada
      if (data == null || (data['isDevAccount'] ?? false) == false) {
        if (!_permissionRevokedShown) {
          _permissionRevokedShown = true;
          // Exibe o popup e, após o usuário confirmar, retorna para a tela anterior
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Permissão Revogada'),
                content: const Text(
                    'Sua permissão para editar/adicionar APIs foi revogada.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Ok'),
                  ),
                ],
              ),
            );
            if (mounted) {
              Navigator.of(context).pop(); // Retorna para a tela anterior
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _apiNameController.dispose();
    _descriptionController.dispose();
    _documentNameController.dispose();
    _keyValueFields.forEach((field) {
      field['key']?.dispose();
      field['value']?.dispose();
    });
    _permissionSubscription?.cancel();
    _apiNameFocusNode.dispose();
    _apiDescriptionFocusNode.dispose();
    _apiDocumentNameFocusNode.dispose();
    super.dispose();
  }

  void _addKeyValueField() {
    setState(() {
      _keyValueFields.add({
        'key': TextEditingController(),
        'value': TextEditingController(),
      });
    });
  }

  void _removeKeyValueField(int index) {
    setState(() {
      _keyValueFields[index]['key']?.dispose();
      _keyValueFields[index]['value']?.dispose();
      _keyValueFields.removeAt(index);
    });
  }

  Future<void> _saveApi() async {
    if (_formKey.currentState?.validate() ?? false) {
      final apiData = {
        'name': _apiNameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Adiciona campos dinâmicos
      final Set<String> keys = {};
      for (var field in _keyValueFields) {
        final key = field['key']?.text.trim() ?? '';
        final value = field['value']?.text.trim() ?? '';

        if (key.isNotEmpty && value.isNotEmpty) {
          if (keys.contains(key)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Chave duplicada: $key')),
            );
            return;
          }
          keys.add(key);
          apiData[key] = value;
        }
      }

      try {
        if (widget.isEditing && widget.existingDocId != null) {
          // Modo edição
          await FirebaseFirestore.instance
              .collection('APIs')
              .doc(widget.existingDocId)
              .update(apiData);
        } else {
          // Modo criação
          apiData['created_at'] = FieldValue.serverTimestamp();

          if (_documentNameController.text.trim().isNotEmpty) {
            final docRef = FirebaseFirestore.instance
                .collection('APIs')
                .doc(_documentNameController.text.trim());

            if (await docRef.get().then((doc) => doc.exists)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Documento já existe!')),
              );
              return;
            }
            await docRef.set(apiData);
          } else {
            await FirebaseFirestore.instance.collection('APIs').add(apiData);
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(widget.isEditing
                  ? 'API atualizada com sucesso!'
                  : 'API adicionada com sucesso!')),
        );
        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildKeyValueField(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: TextFormField(
              controller: _keyValueFields[index]['key'],
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Nome da Variável',
                labelStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.secondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (value) =>
              (value?.isEmpty ?? true) ? 'Campo obrigatório' : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: TextFormField(
              controller: _keyValueFields[index]['value'],
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Valor da Variável',
                labelStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.secondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (value) =>
              (value?.isEmpty ?? true) ? 'Campo obrigatório' : null,
            ),
          ),
          if (!widget.isEditing)
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.red),
              onPressed: () => _removeKeyValueField(index),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    return ConnectivityBanner(
      child: Scaffold(
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
                              color: Theme.of(context).colorScheme.onBackground,
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
                        widget.isEditing ? 'Editar API' : 'Adicionar API',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ],
                  ),
                  // Ícone de salvar
                  Stack(
                    children: [
                      _isLoading
                          ? const CircularProgressIndicator()
                          : IconButton(
                        icon: Icon(
                          Icons.save_alt_rounded,
                          color: Theme.of(context).colorScheme.onBackground,
                          size: 30,
                        ),
                        onPressed: _isLoading ? null : _saveApi,
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
        body: SafeArea(
          top: true,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _apiNameController,
                      focusNode: _apiNameFocusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Digite o nome da API',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(
                          Icons.api,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 20,
                        ),
                      ),
                      validator: (value) =>
                      value!.isEmpty ? 'Campo obrigatório' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      focusNode: _apiDescriptionFocusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Digite a descrição da API',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        labelText: 'Descrição',
                        labelStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      maxLines: 3,
                      validator: (value) =>
                      value!.isEmpty ? 'Campo obrigatório' : null,
                    ),
                    const SizedBox(height: 16),
                    if (!widget.isEditing)
                      TextFormField(
                        controller: _documentNameController,
                        focusNode: _apiDocumentNameFocusNode,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Digite o nome do documento (Opcional)',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          labelText: 'Nome do Documento',
                          labelStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.secondary,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: Icon(
                            Icons.text_snippet,
                            color: Theme.of(context).colorScheme.tertiary,
                            size: 20,
                          ),
                        ),
                        validator: (value) {
                          if (value?.isNotEmpty ?? false) {
                            if (!RegExp(r'^[\w-]+$').hasMatch(value!)) {
                              return 'Use apenas letras, números, _ e -';
                            }
                          }
                          return null;
                        },
                      ),
                    if (!widget.isEditing) const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _keyValueFields.length,
                      itemBuilder: (context, index) => _buildKeyValueField(index),
                    ),
                    if (!widget.isEditing)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: _addKeyValueField,
                          icon: Icon(
                            Icons.add,
                            color: Theme.of(context).colorScheme.outline,
                            size: 22,
                          ),
                          label: Text(
                            'Adicionar Campo',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.fromLTRB(15, 7, 15, 7),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                        ),
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