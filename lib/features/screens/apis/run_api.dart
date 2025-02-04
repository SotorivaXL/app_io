import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class RunApi extends StatefulWidget {
  const RunApi({super.key});

  @override
  State<RunApi> createState() => _RunApiState();
}

class _RunApiState extends State<RunApi> {
  DateTime? selectedDate;
  String? selectedLevel;
  String? selectedBm;
  String? selectedAdAccount;
  String? selectedCampaign;
  List<String> logs = [];
  bool isLoading = false;
  bool isRunning = false;
  double _scrollOffset = 0.0;

  List<DropdownMenuItem<String>> levels = const [
    DropdownMenuItem(value: 'BM', child: Text('Business Managers')),
    DropdownMenuItem(value: 'CONTA_ANUNCIO', child: Text('Contas de Anúncio')),
    DropdownMenuItem(value: 'CAMPANHA', child: Text('Campanhas')),
    DropdownMenuItem(value: 'GRUPO_ANUNCIO', child: Text('Grupos de Anúncio')),
    DropdownMenuItem(value: 'INSIGHTS', child: Text('Insights')),
  ];

  Future<List<DropdownMenuItem<String>>> _getOptions(String collection, String? parentId) async {
    try {
      Map<String, dynamic> callData = {
        'level': collection,
      };

      // Para todos os níveis (CONTA_ANUNCIO, CAMPANHA, GRUPO_ANUNCIO, INSIGHTS)
      // se houver um parentId (que aqui representa o BM selecionado), envia-o:
      if ((collection == 'CONTA_ANUNCIO' ||
          collection == 'CAMPANHA' ||
          collection == 'GRUPO_ANUNCIO' ||
          collection == 'INSIGHTS') &&
          parentId != null) {
        callData['bmId'] = parentId;
      }

      // Para os níveis CAMPANHA, GRUPO_ANUNCIO e INSIGHTS, envia o ID da Conta de Anúncio
      if (collection == 'CAMPANHA' ||
          collection == 'GRUPO_ANUNCIO' ||
          collection == 'INSIGHTS') {
        if (selectedAdAccount != null) {
          callData['adAccountId'] = selectedAdAccount;
        }
      }

      // Se for GRUPO_ANUNCIO, envia também o ID da campanha (caso já selecionado)
      if (collection == 'GRUPO_ANUNCIO') {
        callData['campaignId'] = selectedCampaign;
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('getSyncOptions')
          .call(callData);

      return (result.data as List)
          .map<DropdownMenuItem<String>>((item) => DropdownMenuItem(
        value: item['value'], // valor real
        child: Text(item['label']),
      ))
          .toList();
    } catch (e) {
      _addLog('Erro ao buscar opções: ${e.toString()}');
      return [];
    }
  }

  void _addLog(String message) {
    setState(() {
      logs.add('${DateTime.now().toIso8601String()}: $message');
    });
  }

  Future<void> _syncData() async {
    setState(() {
      isLoading = true;
      isRunning = true;
    });

    try {
      _addLog('Iniciando sincronização...');

      // Validação para BM (usado em todos os níveis que o exigem)
      if (['CONTA_ANUNCIO', 'CAMPANHA', 'GRUPO_ANUNCIO', 'INSIGHTS'].contains(selectedLevel)) {
        if (selectedBm == null || selectedBm!.isEmpty) {
          _addLog('Selecione um Business Manager válido.');
          setState(() {
            isLoading = false;
            isRunning = false;
          });
          return;
        }
      }

      // Validação para Conta de Anúncio (usado em CAMPANHA, GRUPO_ANUNCIO e INSIGHTS)
      if (['CAMPANHA', 'GRUPO_ANUNCIO', 'INSIGHTS'].contains(selectedLevel)) {
        if (selectedAdAccount == null || selectedAdAccount!.isEmpty) {
          _addLog('Selecione uma Conta de Anúncio válida.');
          setState(() {
            isLoading = false;
            isRunning = false;
          });
          return;
        }
      }

      // Validação para Campanha somente se for GRUPO_ANUNCIO
      if (selectedLevel == 'GRUPO_ANUNCIO') {
        if (selectedCampaign == null || selectedCampaign!.isEmpty) {
          _addLog('Selecione uma Campanha válida.');
          setState(() {
            isLoading = false;
            isRunning = false;
          });
          return;
        }
      }

      final callData = {
        'level': selectedLevel,
        'bmId': selectedBm,
        'adAccountId': selectedAdAccount,
        // Para CAMPANHA, não enviamos campaignId; para GRUPO_ANUNCIO, sim.
        'campaignId': selectedLevel == 'GRUPO_ANUNCIO' ? selectedCampaign : null,
      };

      // Adiciona a data somente para INSIGHTS
      if (selectedLevel == 'INSIGHTS') {
        final DateTime syncDate = selectedDate ?? DateTime.now().subtract(const Duration(days: 1));
        callData['date'] =
        "${syncDate.toLocal().year}-${syncDate.month.toString().padLeft(2, '0')}-${syncDate.day.toString().padLeft(2, '0')}";
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('syncMetaData')
          .call(callData);

      _addLog(result.data['message']);
    } catch (e) {
      _addLog('Erro na sincronização: ${e.toString()}');
    } finally {
      setState(() {
        isLoading = false;
        isRunning = false;
      });
    }
  }

  void _updateDependencies() {
    if (selectedLevel == 'BM') {
      selectedBm = null;
    }
    if (selectedLevel != 'CONTA_ANUNCIO' && selectedLevel != 'INSIGHTS') {
      // Para níveis que usam a Conta de Anúncio
      selectedAdAccount = null;
    }
    // Se o nível não for GRUPO_ANUNCIO, limpa a campanha selecionada
    if (selectedLevel != 'GRUPO_ANUNCIO') {
      selectedCampaign = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    return Scaffold(
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
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Executar API',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ],
                ),
                // Ícone à direita (limpar logs ou indicador de carregamento)
                Stack(
                  children: [
                    isLoading
                        ? const CircularProgressIndicator()
                        : IconButton(
                      icon: const Icon(Icons.refresh),
                      color: Theme.of(context).colorScheme.onBackground,
                      onPressed: () => setState(() {
                        logs.clear();
                      }),
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.secondary,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isRunning ? null : _syncData,
        backgroundColor: isRunning ? Colors.grey : Theme.of(context).colorScheme.tertiary,
        child: isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.play_arrow, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLevelSelector(),
            const SizedBox(height: 20),
            if (selectedLevel != null) _buildDependencySelectors(),
            const SizedBox(height: 20),
            _buildLogPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelSelector() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.secondary,
      ),
      value: selectedLevel,
      hint: const Text('Selecione o nível da sincronização'),
      items: levels,
      onChanged: (value) {
        setState(() {
          selectedLevel = value;
          _updateDependencies();
        });
      },
      menuMaxHeight: MediaQuery.of(context).size.height * 0.3,
      icon: const SizedBox.shrink(),
      isExpanded: true,
    );
  }

  Widget _buildDependencySelectors() {
    return Column(
      children: [
        // Se o nível exigir BM, exibe o seletor de Business Manager
        if (['CONTA_ANUNCIO', 'CAMPANHA', 'GRUPO_ANUNCIO', 'INSIGHTS'].contains(selectedLevel))
          FutureBuilder<List<DropdownMenuItem<String>>>(
            future: _getOptions('BM', null),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: CircularProgressIndicator(),
                );
              }
              return _buildSelector(
                label: 'Business Manager',
                value: selectedBm,
                items: snapshot.data ?? [],
                onChanged: (value) => setState(() {
                  selectedBm = value;
                  selectedAdAccount = null;
                  selectedCampaign = null;
                }),
              );
            },
          ),
        // Se o nível exigir Conta de Anúncio, exibe o seletor
        if (['CAMPANHA', 'GRUPO_ANUNCIO', 'INSIGHTS'].contains(selectedLevel))
          FutureBuilder<List<DropdownMenuItem<String>>>(
            future: _getOptions('CONTA_ANUNCIO', selectedBm),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: CircularProgressIndicator(),
                );
              }
              return _buildSelector(
                label: 'Conta de Anúncio',
                value: selectedAdAccount,
                items: snapshot.data ?? [],
                onChanged: (value) => setState(() {
                  selectedAdAccount = value;
                  // Ao selecionar nova conta, zera eventual campanha já escolhida
                  selectedCampaign = null;
                }),
              );
            },
          ),
        // Exibe o seletor de Campanha somente se o nível for GRUPO_ANUNCIO
        if (selectedLevel == 'GRUPO_ANUNCIO')
          FutureBuilder<List<DropdownMenuItem<String>>>(
            // Aqui passamos o BM selecionado para que o cloud function pesquise as campanhas
            future: _getOptions('CAMPANHA', selectedBm),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: CircularProgressIndicator(),
                );
              }
              return _buildSelector(
                label: 'Campanha',
                value: selectedCampaign,
                items: snapshot.data ?? [],
                onChanged: (value) => setState(() => selectedCampaign = value),
              );
            },
          ),
        if (selectedLevel == 'INSIGHTS') _buildDateSelector(),
      ],
    );
  }

  Widget _buildSelector({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.secondary,
        ),
        value: value,
        hint: Text('Selecione a $label'),
        items: items,
        onChanged: onChanged,
        dropdownColor: Theme.of(context).colorScheme.secondary,
        menuMaxHeight: MediaQuery.of(context).size.height * 0.3,
        icon: const SizedBox.shrink(),
        isExpanded: true,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSecondary,
        ),
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
      ),
    );
  }

  Widget _buildLogPanel() {
    return Expanded(
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Logs de Execução:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  reverse: true,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(logs.reversed.toList()[index]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime initialDate =
        selectedDate ?? DateTime.now().subtract(const Duration(days: 1));
    final DateTime firstDate = DateTime(2000);
    final DateTime lastDate = DateTime.now().subtract(const Duration(days: 1));

    DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        DateTime tempPickedDate = initialDate;
        return AlertDialog(
          title: const Text('Selecione a data'),
          content: SizedBox(
            height: 300,
            width: 300,
            child: CalendarDatePicker(
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
              onDateChanged: (DateTime date) {
                tempPickedDate = date;
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(tempPickedDate),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  // Widget para exibir o campo de seleção de data
  Widget _buildDateSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        readOnly: true,
        onTap: () => _selectDate(context),
        decoration: InputDecoration(
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.secondary,
        ),
        controller: TextEditingController(
          text: selectedDate != null
              ? "${selectedDate!.toLocal().day.toString().padLeft(2, '0')}/${selectedDate!.toLocal().month.toString().padLeft(2, '0')}/${selectedDate!.toLocal().year}"
              : "Selecione a data dos insights",
        ),
      ),
    );
  }
}