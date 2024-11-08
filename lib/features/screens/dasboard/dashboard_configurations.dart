import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DashboardConfigurations extends StatefulWidget {
  const DashboardConfigurations({super.key});

  @override
  State<DashboardConfigurations> createState() => _DashboardConfigurationsState();
}

class _DashboardConfigurationsState extends State<DashboardConfigurations> {
  final Map<String, dynamic> anuncios = {
    'BMs': [],
    'contasAnuncio': [],
  };

  List<String> empresas = [];
  String? empresaSelecionada;
  List<Map<String, dynamic>> contasAnuncioList = [];

  Future<List<Map<String, dynamic>>> _fetchBMs() async {
    final dashboardCollection = FirebaseFirestore.instance.collection('dashboard');
    final snapshot = await dashboardCollection.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, 'name': doc['name']})
        .toList();
  }

  Future<void> _fetchContasAnuncioPorBM(String bmId) async {
    final dashboardDoc = FirebaseFirestore.instance.collection('dashboard').doc(bmId);
    final contasSnapshot = await dashboardDoc.collection('contasAnuncio').get();
    setState(() {
      contasAnuncioList = contasSnapshot.docs
          .map((subDoc) => {'id': subDoc.id, 'name': subDoc['name']})
          .toList();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchEmpresas() async {
    final empresasCollection = FirebaseFirestore.instance.collection('empresas');
    final snapshot = await empresasCollection.get();
    return snapshot.docs
        .map((doc) => {'id': doc.id, 'NomeEmpresa': doc['NomeEmpresa']})
        .toList();
  }

  void _saveAnuncios() {
    print(anuncios);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações do Dashboard'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min, // Definindo Column para ocupar apenas o espaço necessário
            children: [
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchBMs(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          items: snapshot.data!.map((bm) {
                            return DropdownMenuItem<String>(
                              value: bm['id'] as String,
                              child: Text(
                                bm['name'],
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSecondary
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                anuncios['BMs'].add({
                                  'id': value,
                                  'name': snapshot.data!
                                      .firstWhere((bm) => bm['id'] == value)['name']
                                });
                                _fetchContasAnuncioPorBM(value);
                              });
                            }
                          },
                          decoration: const InputDecoration(
                              hintText: 'Selecione as BMs',
                              hintStyle: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12
                              )
                          ),
                          dropdownColor: Theme.of(context).colorScheme.background,
                        ),
                      ),
                    ],
                  );
                },
              ),
              Wrap(
                children: anuncios['BMs']
                    .map<Widget>((bm) => Chip(
                  label: Text(bm['name']),
                  onDeleted: () {
                    setState(() {
                      anuncios['BMs'].remove(bm);
                      contasAnuncioList.clear();
                    });
                  },
                ))
                    .toList(),
              ),
              const SizedBox(height: 16.0),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      items: contasAnuncioList.map((conta) {
                        return DropdownMenuItem<String>(
                          value: conta['id'] as String,
                          child: Text(
                            conta['name'],
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSecondary
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            anuncios['contasAnuncio'].add({
                              'id': value,
                              'name': contasAnuncioList
                                  .firstWhere((conta) => conta['id'] == value)['name']
                            });
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        hintText: 'Selecione as contas de anuncio',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12
                        )
                      ),
                      isExpanded: true,
                      menuMaxHeight: 200.0,
                      dropdownColor: Theme.of(context).colorScheme.background,
                    ),
                  ),
                ],
              ),
              Wrap(
                children: anuncios['contasAnuncio']
                    .map<Widget>((conta) => Chip(
                  label: Text(conta['name']),
                  onDeleted: () {
                    setState(() {
                      anuncios['contasAnuncio'].remove(conta);
                    });
                  },
                ))
                    .toList(),
              ),
              const SizedBox(height: 16.0),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchEmpresas(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          items: snapshot.data!.map((empresa) {
                            return DropdownMenuItem<String>(
                              value: empresa['id'] as String,
                              child: Text(empresa['NomeEmpresa']),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              empresaSelecionada = value;
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Selecionar Empresa'),
                          dropdownColor: Theme.of(context).colorScheme.background,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveAnuncios,
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}