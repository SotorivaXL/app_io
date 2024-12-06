import 'dart:async';
import 'dart:convert';
import 'package:app_io/auth/providers/auth_provider.dart' as appProvider;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomDropDown/custom_dropDown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:http/http.dart' as http;

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
  String? selectedGrupoAnuncio; // Inicialmente nula
}

class _DashboardPageState extends State<DashboardPage> {
  String? selectedContaAnuncioId;
  String? selectedCampaignId;
  String? selectedGrupoAnuncioId;
  bool _isExpanded = false;
  bool _isLoading = true;
  final DateRangePickerController _datePickerController =
  DateRangePickerController();

  final String apiUrl =
      "https://0ea6-2804-6fc-aeb7-7100-e52c-fd68-cf54-241c.ngrok-free.app/dynamic_insights";

  List<Map<String, dynamic>> adAccounts = [];

  List<Map<String, dynamic>> selectedCampaigns = [];
  List<Map<String, dynamic>> campaignsList = [];

  List<Map<String, dynamic>> selectedGruposAnuncios = [];
  List<Map<String, dynamic>> gruposAnunciosList = [];

  Map<String, dynamic> initialInsightsData = {};

  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    _initilizeData();
  }

  void _initilizeData() async {
    await _fetchInitialInsights();
  }

  double _parseToDouble(dynamic value) {
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    } else if (value is num) {
      return value.toDouble();
    }
    return 0.0; // Valor padrão para valores nulos ou não numéricos
  }

  void _openDateRangePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Envolva o AlertDialog em um Theme para personalizar os estilos dos botões
        return Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(),
          ),
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.secondary,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(
              'Selecione o intervalo de datas',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondary,
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SizedBox(
              width: 400,
              height: 350,
              child: SfDateRangePicker(
                maxDate: DateTime.now(),
                controller: _datePickerController,
                backgroundColor: Theme.of(context).colorScheme.secondary,
                view: DateRangePickerView.month,
                selectionMode: DateRangePickerSelectionMode.range,
                showActionButtons: false,
                // Desabilita os botões internos
                initialSelectedRange: startDate != null && endDate != null
                    ? PickerDateRange(startDate, endDate)
                    : null,
                headerStyle: DateRangePickerHeaderStyle(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  textAlign: TextAlign.center,
                  textStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondary,
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                monthCellStyle: DateRangePickerMonthCellStyle(
                  textStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondary,
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  todayTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  blackoutDatesDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                startRangeSelectionColor: Theme.of(context).colorScheme.primary,
                endRangeSelectionColor: Theme.of(context).colorScheme.primary,
                rangeSelectionColor:
                Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
                todayHighlightColor: Theme.of(context).colorScheme.tertiary,
                monthViewSettings: DateRangePickerMonthViewSettings(
                  viewHeaderStyle: DateRangePickerViewHeaderStyle(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    textStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondary,
                      fontFamily: 'Poppins',
                      fontSize: 12, // Ajuste o tamanho da fonte aqui
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                yearCellStyle: DateRangePickerYearCellStyle(
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  todayTextStyle: TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ),
            ),
            // Botões personalizados
            actions: [
              TextButton(
                child: Text(
                  'Cancelar'.toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              TextButton(
                child: Text(
                  'Ok'.toUpperCase(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                onPressed: () {
                  // Certifique-se de que o `selectedRange` não é nulo antes de acessar suas propriedades
                  PickerDateRange? selectedRange =
                      _datePickerController.selectedRange;
                  if (selectedRange != null &&
                      selectedRange.startDate != null &&
                      selectedRange.endDate != null) {
                    setState(() {
                      startDate = selectedRange.startDate;
                      endDate = selectedRange.endDate;
                    });

                    // Adiciona o print das datas selecionadas
                    print(
                        'Data inicial: ${DateFormat('dd/MM/yyyy').format(selectedRange.startDate!)}');
                    print(
                        'Data final: ${DateFormat('dd/MM/yyyy').format(selectedRange.endDate!)}');
                  } else {
                    print(
                        'Nenhuma data foi selecionada ou o intervalo está incompleto.');
                  }
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        body: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(10, 20, 10, 0),
          child: _isLoading
              ? Center(
            child: CircularProgressIndicator(),
          )
              : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFilters(),
                const SizedBox(height: 20),
                _buildMetricCards(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Atualizações no método _buildFilters()
  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _isExpanded
                ? Theme.of(context).colorScheme.background // Cor quando expandido
                : Theme.of(context).colorScheme.secondary, // Cor quando recolhido
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent, // Remove as linhas de divisão
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsetsDirectional.fromSTEB(28, 0, 0, 0),
                initiallyExpanded: _isExpanded,
                onExpansionChanged: (bool expanded) {
                  setState(() {
                    _isExpanded = expanded;
                  });
                },
                // Remove o ícone padrão na lateral direita
                trailing: SizedBox.shrink(),
                backgroundColor: Colors.transparent,
                collapsedBackgroundColor: Colors.transparent,
                title: Center(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.filter_list,
                      size: _isExpanded ? 32.0 : 24.0, // Tamanho do ícone animado
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
                children: [
                  // Botão para abrir o DatePicker
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openDateRangePicker,
                      icon: Icon(
                        Icons.date_range,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      label: startDate != null && endDate != null
                          ? Text(
                        "${DateFormat('dd/MM/yyyy').format(startDate!)} - ${DateFormat('dd/MM/yyyy').format(endDate!)}",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      )
                          : Text(
                        "Selecione um intervalo de datas",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                        Theme.of(context).colorScheme.secondary,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12.0, horizontal: 16.0),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  // FutureBuilder para buscar campanhas
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchCampaigns(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        return Text('Erro: ${snapshot.error}');
                      } else {
                        campaignsList = snapshot.data ?? [];

                        // Converte todos os IDs para String e remove duplicatas
                        campaignsList = campaignsList.map((campaign) {
                          campaign['id'] = campaign['id'].toString();
                          return campaign;
                        }).toList();

                        // Remove duplicatas com base no ID
                        final ids = Set();
                        campaignsList
                            .retainWhere((campaign) => ids.add(campaign['id']));

                        // Lista de opções combinada para itens e selectedItemBuilder
                        List<Map<String, dynamic>> campaignOptions = [
                          {'id': '', 'name': 'Limpar Filtro', 'isError': true},
                          ...campaignsList.map((campaign) {
                            return {
                              'id': campaign['id'],
                              'name': campaign['name'],
                              'isError': false
                            };
                          }).toList(),
                        ];

                        // Certifica-se de que selectedCampaignId é uma String
                        if (selectedCampaignId != null) {
                          selectedCampaignId = selectedCampaignId.toString();
                        }

                        // Verifica se selectedCampaignId está na lista de opções
                        bool isSelectedIdValid = campaignOptions.any(
                                (option) => option['id'] == selectedCampaignId);
                        if (!isSelectedIdValid) {
                          selectedCampaignId = null;
                        }

                        return Column(
                          children: [
                            // Dropdown de Campanhas
                            Padding(
                              padding: EdgeInsets.only(top: 20.0),
                              child: SizedBox(
                                height: 50, // Aumenta a altura do dropdown
                                child: CustomDropdown(
                                  items: campaignOptions,
                                  value: selectedCampaignId,
                                  onChanged: (value) async {
                                    setState(() {
                                      selectedCampaignId = value;

                                      // Atualiza `selectedCampaigns` com a campanha selecionada
                                      if (value != null && value.isNotEmpty) {
                                        selectedCampaigns = campaignOptions
                                            .where((option) => option['id'] == value)
                                            .toList();
                                      } else {
                                        selectedCampaigns = [];
                                      }

                                      // Limpa os grupos de anúncio e a seleção anterior
                                      selectedGrupoAnuncioId = null;
                                      gruposAnunciosList.clear();
                                    });

                                    // Recarrega os grupos de anúncio para a campanha selecionada
                                    if (selectedCampaigns.isNotEmpty) {
                                      final grupos = await _fetchGruposAnuncios();
                                      setState(() {
                                        gruposAnunciosList = grupos;
                                      });
                                    }
                                  },
                                  displayText: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Selecione a campanha'; // Texto padrão
                                    }
                                    final selectedItem = campaignOptions.firstWhere(
                                          (item) => item['id'] == value,
                                      orElse: () => {'name': 'Selecione a campanha'},
                                    );
                                    return selectedItem['name'];
                                  },
                                ),
                              ),
                            ),
                            // Se campanhas foram selecionadas, exibe o dropdown de grupos
                            if (selectedCampaigns.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: _fetchGruposAnuncios(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const CircularProgressIndicator();
                                  } else if (snapshot.hasError) {
                                    // Em caso de erro, exiba um dropdown com a mensagem de erro personalizada
                                    return CustomDropdown(
                                      items: [],
                                      value: null,
                                      onChanged: (_) {}, // Não faz nada
                                      displayText: (_) => 'Erro ao carregar grupos de anúncios',
                                    );
                                  } else {
                                    gruposAnunciosList = snapshot.data ?? [];

                                    // Verifica se a lista está vazia
                                    if (gruposAnunciosList.isEmpty) {
                                      return CustomDropdown(
                                        items: [],
                                        value: null,
                                        onChanged: (_) {}, // Não faz nada
                                        displayText: (_) => 'Nenhum grupo de anúncio encontrado',
                                      );
                                    }

                                    // Exibe o dropdown com os grupos de anúncio
                                    return CustomDropdown(
                                      items: gruposAnunciosList,
                                      value: selectedGrupoAnuncioId,
                                      onChanged: (value) {
                                        setState(() {
                                          selectedGrupoAnuncioId = value;
                                        });
                                      },
                                      displayText: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Selecione o grupo de anúncios'; // Texto padrão
                                        }
                                        final selectedItem = gruposAnunciosList.firstWhere(
                                              (item) => item['id'] == value,
                                          orElse: () => {'name': 'Selecione o grupo de anúncios'},
                                        );
                                        return selectedItem['name'];
                                      },
                                    );
                                  }
                                },
                              ),
                            ],
                          ],
                        );
                      }
                    },
                  ),
                  // Espaçamento antes do botão
                  const SizedBox(height: 20),
                  // Botão "Filtrar" fora do FutureBuilder
                  ElevatedButton.icon(
                    icon: Icon(
                      Icons.manage_search,
                      size: 22,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                    label: Text(
                      'Filtrar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding:
                      EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    onPressed: () async {
                      // Verifica se o campo de data foi preenchido
                      if (startDate == null || endDate == null) {
                        print(
                            'Erro: Nenhum intervalo de datas foi selecionado.');
                        return;
                      }

                      // Obtém o intervalo de datas
                      String dataInicial =
                      DateFormat('yyyy-MM-dd').format(startDate!);
                      String dataFinal =
                      DateFormat('yyyy-MM-dd').format(endDate!);
                      print('Intervalo de datas: $dataInicial - $dataFinal');

                      // Verifica se o ID da conta de anúncios está disponível
                      if (selectedContaAnuncioId == null) {
                        await _fetchInitialInsights();
                        if (selectedContaAnuncioId == null) {
                          print(
                              'Erro: ID da conta de anúncios não encontrado.');
                          return;
                        }
                      }

                      // Determina o ID e o nível selecionado (conta, campanha ou grupo de anúncios)
                      String? id;
                      String level;

                      if (selectedGrupoAnuncioId != null) {
                        id = selectedGrupoAnuncioId;
                        level = "adset";
                        print('ID do grupo de anúncios selecionado: $id');
                      } else if (selectedCampaignId != null) {
                        id = selectedCampaignId;
                        level = "campaign";
                        print('ID da campanha selecionada: $id');
                      } else {
                        id = selectedContaAnuncioId;
                        level = "account";
                        print('ID da conta de anúncios selecionada: $id');
                      }

                      if (id == null) {
                        print('Erro: Nenhum ID válido foi selecionado.');
                        return;
                      }

                      try {
                        // Chama a API para buscar insights
                        final insights = await _fetchMetaInsights(
                            id, level, dataInicial, dataFinal);
                        final pixelData =

                        // Exibe os dados de insights da Meta em prints separados
                        print('\n--- Dados de Insights Recuperados ---');
                        insights.forEach((key, value) {
                          print('$key: $value');
                        });

                      } catch (e) {
                        print('Erro ao buscar dados: $e');
                      }
                    },
                  ),
                  const SizedBox(height: 20), // Espaçamento após o botão
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCards() {
    final List<Map<String, dynamic>> metrics = [
      {
        'title': 'Alcance',
        'key': 'reach',
        'icon': FontAwesomeIcons.chartSimple
      },
      {
        'title': 'Valor Gasto',
        'key': 'spend',
        'icon': FontAwesomeIcons.moneyBillTransfer
      },
      {
        'title': 'Resultado',
        'key': 'CompleteRegistration',
        'icon': FontAwesomeIcons.filterCircleDollar
      },
      {
        'title': 'Custo por Resultado',
        'key': 'cost_per_result',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Visulização da página',
        'key': 'PageView',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Registros Completos',
        'key': 'CompleteRegistration',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Cliques no Link',
        'key': 'inline_link_clicks',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Custo por Clique no Link',
        'key': 'cost_per_inline_link_click',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Cliques (Todos)',
        'key': 'clicks',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Custo por Clique (CPC - Todos)',
        'key': 'cpc',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Impressões',
        'key': 'impressions',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
      {
        'title': 'Custo por Mil Pessoas Alcançadas (CPM)',
        'key': 'cpm',
        'icon': FontAwesomeIcons.circleDollarToSlot
      },
    ];

    final formatter = NumberFormat('#,##0', 'pt_BR');
    final currencyFormatter =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = constraints.maxWidth ~/ 160;
        columns = columns > 0 ? columns : 1;
        double itemWidth =
            (constraints.maxWidth - (columns - 1) * 16) / columns;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: metrics.map((metric) {
            String value = '—'; // Placeholder
            dynamic dataValue = initialInsightsData[metric['key']];

            if (dataValue != null) {
              double numericValue = _parseToDouble(dataValue);
              if (metric['key'] == 'spend' ||
                  metric['key'] == 'cpm' ||
                  metric['key'] == 'cost_per_inline_link_click' ||
                  metric['key'] == 'cpc') {
                value = currencyFormatter.format(numericValue);
              } else {
                value = formatter.format(numericValue);
              }
            }

            return SizedBox(
              width: itemWidth,
              child: _buildMetricCard(metric['title'], value, metric['icon']),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, IconData iconData) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              iconData,
              size: 32,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontFamily: "Poppins",
                fontSize: 14,
                color: Theme.of(context).colorScheme.onBackground,
              ),
              overflow: TextOverflow.ellipsis,
              // Adiciona elipses se o texto for muito longo
              maxLines: 1, // Limita o texto a uma linha
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Método atualizado _fetchInitialInsights()
  Future<void> _fetchInitialInsights({bool shouldSetState = true}) async {
    try {
      setState(() {
        _isLoading = true; // Inicia o carregamento
      });

      final authProvider =
      Provider.of<appProvider.AuthProvider>(context, listen: false);
      final user = authProvider.user;

      if (user == null) {
        print('Usuário não está logado.');
        setState(() {
          _isLoading = false; // Finaliza o carregamento em caso de erro
        });
        return;
      }

      String? companyId;
      DocumentSnapshot<Map<String, dynamic>>? empresaDoc;

      // Verifica se o usuário é um "user"
      print('Verificando se o usuário é um "user"...');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        print('Usuário é um "user". Documento do usuário: ${userDoc.data()}');
        if (userDoc.data()!.containsKey('createdBy')) {
          companyId = userDoc['createdBy'];
          print('CompanyId do usuário encontrado: $companyId');

          // Obtém o documento da empresa usando o companyId
          empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(companyId)
              .get();

          if (!empresaDoc.exists) {
            print(
                'Documento da empresa não encontrado para o companyId: $companyId');
            setState(() {
              _isLoading = false; // Finaliza o carregamento em caso de erro
            });
            return;
          }
        } else {
          print('Campo "createdBy" não encontrado no documento do usuário.');
          setState(() {
            _isLoading = false; // Finaliza o carregamento em caso de erro
          });
          return;
        }
      } else {
        // Verifica se o usuário é uma "empresa"
        print('Usuário não é um "user". Verificando se é uma "empresa"...');
        empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (empresaDoc.exists) {
          print(
              'Usuário é uma "empresa". Documento da empresa: ${empresaDoc.data()}');
          companyId = user.uid;
        } else {
          print(
              'Usuário não é "user" nem "empresa". Documento não encontrado.');
          setState(() {
            _isLoading = false; // Finaliza o carregamento em caso de erro
          });
          return;
        }
      }

      // Verifica se os campos BMs e contasAnuncio existem
      print('Verificando se os campos BMs e contasAnuncio existem...');
      if (!empresaDoc.data()!.containsKey('BMs') ||
          !empresaDoc.data()!.containsKey('contasAnuncio')) {
        print(
            'Campos BMs ou contasAnuncio não existem no documento da empresa.');
        setState(() {
          _isLoading = false; // Finaliza o carregamento em caso de erro
        });
        return;
      }

      // Obtém as BMs e as contas de anúncio vinculadas à empresa
      var bmIds = empresaDoc['BMs'];
      var contaAnuncioIds = empresaDoc['contasAnuncio'];

      print('BM IDs: $bmIds, Conta Anúncio IDs: $contaAnuncioIds');

      // Garante que bmIds e contaAnuncioIds sejam listas de Strings, eliminando aninhamentos
      if (bmIds is! List) {
        bmIds = [bmIds];
      } else {
        bmIds = bmIds.expand((e) => e is List ? e : [e]).toList();
      }

      if (contaAnuncioIds is! List) {
        contaAnuncioIds = [contaAnuncioIds];
      } else {
        contaAnuncioIds =
            contaAnuncioIds.expand((e) => e is List ? e : [e]).toList();
      }

      // Converte os itens das listas para String, caso ainda não sejam
      bmIds = bmIds.map((e) => e.toString()).toList();
      contaAnuncioIds = contaAnuncioIds.map((e) => e.toString()).toList();

      print(
          'BM IDs após processamento: $bmIds, Conta Anúncio IDs após processamento: $contaAnuncioIds');

      adAccounts =
      []; // Garante que adAccounts esteja vazio antes de preenchê-lo

      for (var bmId in bmIds) {
        for (var contaAnuncioDocId in contaAnuncioIds) {
          print(
              'Processando BM ID: $bmId, Conta Anúncio Doc ID: $contaAnuncioDocId');

          // Obtém o documento da conta de anúncio
          final adAccountDoc = await FirebaseFirestore.instance
              .collection('dashboard')
              .doc(bmId)
              .collection('contasAnuncio')
              .doc(contaAnuncioDocId)
              .get();

          if (adAccountDoc.exists) {
            // Armazena o 'id' e 'name' da conta de anúncio
            adAccounts.add({
              'id': adAccountDoc.data()?['id'],
              // 'id' dentro do documento
              'name': adAccountDoc.data()?['name'],
              'bmId': bmId,
              'contaAnuncioDocId': contaAnuncioDocId,
              // ID do documento no Firestore
            });
          } else {
            print(
                'Conta de anúncio não encontrada para BM ID $bmId e Conta Anúncio Doc ID $contaAnuncioDocId');
          }
        }
      }

      if (adAccounts.isNotEmpty) {
        // Seleciona a primeira conta de anúncio
        selectedContaAnuncioId =
        adAccounts.first['id']; // Usa o 'id' dentro do documento
        print('ID da conta de anúncios selecionada: $selectedContaAnuncioId');
      } else {
        print('Nenhuma conta de anúncio encontrada.');
        setState(() {
          _isLoading = false; // Finaliza o carregamento em caso de erro
        });
        return;
      }

      // Agora, prossegue para buscar os insights usando o 'contaAnuncioDocId' para acessar o documento
      Map<String, dynamic> combinedInsights = {};

      for (var adAccount in adAccounts) {
        String bmId = adAccount['bmId'];
        String contaAnuncioDocId =
        adAccount['contaAnuncioDocId']; // ID do documento no Firestore

        print(
            'Processando BM ID: $bmId, Conta Anúncio Doc ID: $contaAnuncioDocId');

        // Acessa o documento "dados_insights" na coleção "insights"
        final dadosInsightsDoc = await FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioDocId)
            .collection('insights')
            .doc('dados_insights')
            .get();

        if (dadosInsightsDoc.exists) {
          print(
              'Documento de insights encontrado para BM ID $bmId e Conta Anúncio Doc ID $contaAnuncioDocId');

          Map<String, dynamic>? insightsData = dadosInsightsDoc.data();

          if (insightsData != null) {
            // Verifica se existe a chave 'insights' no documento
            if (insightsData.containsKey('insights')) {
              List<dynamic>? insightsList = insightsData['insights'];

              if (insightsList != null && insightsList is List) {
                // Itera sobre cada item da lista de insights
                for (var insight in insightsList) {
                  if (insight is Map<String, dynamic>) {
                    insight.forEach((key, value) {
                      if (value is String) {
                        final numValue = num.tryParse(value);
                        if (numValue != null) {
                          if (combinedInsights.containsKey(key)) {
                            combinedInsights[key] += numValue;
                          } else {
                            combinedInsights[key] = numValue;
                          }
                        }
                      } else if (value is num) {
                        if (combinedInsights.containsKey(key)) {
                          combinedInsights[key] += value;
                        } else {
                          combinedInsights[key] = value;
                        }
                      }
                    });
                  } else {
                    print('Formato inesperado de item de insight: $insight');
                  }
                }
              } else {
                print('A lista de insights está vazia ou não é uma lista.');
              }
            } else {
              // Caso o documento 'dados_insights' não tenha a chave 'insights', utiliza os dados do documento diretamente
              insightsData.forEach((key, value) {
                if (value is String) {
                  final numValue = num.tryParse(value);
                  if (numValue != null) {
                    if (combinedInsights.containsKey(key)) {
                      combinedInsights[key] += numValue;
                    } else {
                      combinedInsights[key] = numValue;
                    }
                  }
                } else if (value is num) {
                  if (combinedInsights.containsKey(key)) {
                    combinedInsights[key] += value;
                  } else {
                    combinedInsights[key] = value;
                  }
                }
              });
            }
          } else {
            print('Dados de insights não encontrados no documento.');
          }
        } else {
          print(
              'Documento de insights não encontrado para BM ID $bmId e Conta Anúncio Doc ID $contaAnuncioDocId');
        }
      }

      if (shouldSetState) {
        setState(() {
          initialInsightsData = combinedInsights;
          _isLoading = false; // Finaliza o carregamento após sucesso
        });
      } else {
        initialInsightsData = combinedInsights;
        _isLoading = false; // Finaliza o carregamento após sucesso
      }

      print('Dados de insights combinados: $combinedInsights');
    } catch (e, stacktrace) {
      print('Erro ao buscar insights iniciais: $e');
      print(stacktrace);
      setState(() {
        _isLoading = false; // Finaliza o carregamento em caso de exceção
      });
    }
  }

  // Método para buscar contas de anúncio
  Future<List<Map<String, dynamic>>> _fetchAdAccounts() async {
    try {
      final authProvider =
      Provider.of<appProvider.AuthProvider>(context, listen: false);
      final user = authProvider.user;

      if (user == null) {
        print('Usuário não está logado.');
        return [];
      }

      String? companyId;
      DocumentSnapshot<Map<String, dynamic>> empresaDoc;

      // Verifica se o usuário é um "user"
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        companyId = userDoc['createdBy'];

        // Obtém o documento da empresa usando o companyId
        empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(companyId)
            .get();

        if (!empresaDoc.exists) {
          print(
              'Documento da empresa não encontrado para o companyId: $companyId');
          return [];
        }
      } else {
        // Verifica se o usuário é uma "empresa"
        empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (empresaDoc.exists) {
          companyId = user.uid;
        } else {
          print('Usuário não é "user" nem "empresa"');
          return [];
        }
      }

      // Verifica se o campo contasAnuncio existe
      if (!empresaDoc.data()!.containsKey('BMs') ||
          !empresaDoc.data()!.containsKey('contasAnuncio')) {
        print(
            'Campos BMs ou contasAnuncio não existem no documento da empresa.');
        return [];
      }

      var bmIds = empresaDoc['BMs'];
      var contaAnuncioIds = empresaDoc['contasAnuncio'];

      // Garante que bmIds e contaAnuncioIds sejam listas
      if (bmIds is! List) {
        bmIds = [bmIds];
      }
      if (contaAnuncioIds is! List) {
        contaAnuncioIds = [contaAnuncioIds];
      }

      List<Map<String, dynamic>> adAccounts = [];

      for (var bmId in bmIds) {
        for (var contaAnuncioId in contaAnuncioIds) {
          final adAccountDoc = await FirebaseFirestore.instance
              .collection('dashboard')
              .doc(bmId)
              .collection('contasAnuncio')
              .doc(contaAnuncioId)
              .get();

          if (adAccountDoc.exists) {
            adAccounts.add({
              'id': adAccountDoc.data()?['id'],
              'name': adAccountDoc.data()?['name'],
              'bmId': bmId,
            });
          } else {
            print(
                'Documento da conta de anúncio não encontrado para BM ID: $bmId, Conta Anúncio ID: $contaAnuncioId');
          }
        }
      }

      return adAccounts;
    } catch (e, stacktrace) {
      print('Erro ao buscar contas de anúncio: $e');
      print(stacktrace);
      throw 'Erro ao buscar contas de anúncio: $e';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCampaigns() async {
    try {
      List<Map<String, dynamic>> allCampaigns = [];

      // Verifica se adAccounts está preenchido
      if (adAccounts.isEmpty) {
        // Evita loop infinito ao não chamar setState durante a construção
        await _fetchInitialInsights(shouldSetState: false);
        if (adAccounts.isEmpty) {
          print('Nenhuma conta de anúncio disponível para buscar campanhas.');
          return [];
        }
      }

      // Percorre cada conta de anúncio
      for (var adAccount in adAccounts) {
        String bmId = adAccount['bmId'];
        String contaAnuncioDocId = adAccount['contaAnuncioDocId'];
        String contaAnuncioId = adAccount['id']; // 'id' dentro do documento

        print('Processando BM ID: $bmId, Conta Anúncio ID: $contaAnuncioId');

        // Acessa o documento da conta de anúncio
        final contaAnuncioDoc = FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioDocId);

        // Obtém as campanhas dentro da subcoleção 'campanhas'
        final campanhasSnapshot =
        await contaAnuncioDoc.collection('campanhas').get();

        print(
            'Número de campanhas encontradas para BM $bmId e Conta $contaAnuncioId: ${campanhasSnapshot.docs.length}');

        // Percorre cada documento de campanha
        for (var doc in campanhasSnapshot.docs) {
          var data = doc.data();
          allCampaigns.add({
            'id': data['id'].toString(), // Converte 'id' para String
            'name': data['name'], // 'name' dentro do documento da campanha
            'bmId': bmId,
            'contaAnuncioId': contaAnuncioId,
            'contaAnuncioDocId': contaAnuncioDocId,
            'campaignDocId': doc.id, // ID do documento da campanha no Firestore
          });
        }
      }

      // Remove duplicatas com base no ID
      final ids = Set();
      allCampaigns.retainWhere((campaign) => ids.add(campaign['id']));

      return allCampaigns;
    } catch (e, stacktrace) {
      print('Erro ao buscar campanhas: $e');
      print(stacktrace);
      throw 'Erro ao buscar campanhas: $e';
    }
  }

  // Método para buscar grupos de anúncios
  Future<List<Map<String, dynamic>>> _fetchGruposAnuncios() async {
    try {
      List<Map<String, dynamic>> allGruposAnuncios = [];

      for (var campaign in selectedCampaigns) {
        String bmId = campaign['bmId'];
        String contaAnuncioDocId = campaign['contaAnuncioDocId'];
        String campaignId = campaign['id']; // 'id' da campanha selecionada
        String campaignDocId = campaign[
        'campaignDocId']; // ID do documento da campanha no Firestore

        final gruposAnunciosSnapshot = await FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioDocId)
            .collection('campanhas')
            .doc(campaignDocId)
            .collection('gruposAnuncios')
            .get();

        for (var doc in gruposAnunciosSnapshot.docs) {
          var data = doc.data();
          allGruposAnuncios.add({
            'id': data['id'],
            // 'id' dentro do documento do grupo de anúncios
            'name': data['name'],
            'bmId': bmId,
            'contaAnuncioDocId': contaAnuncioDocId,
            'campaignId': campaignId,
            'campaignDocId': campaignDocId,
            'grupoAnuncioDocId': doc.id,
            // ID do documento do grupo de anúncios no Firestore
          });
        }
      }

      return allGruposAnuncios;
    } catch (e, stacktrace) {
      print('Erro ao buscar grupos de anúncios: $e');
      print(stacktrace);
      throw 'Erro ao buscar grupos de anúncios: $e';
    }
  }

  Future<Map<String, dynamic>> _fetchMetaInsights(
      String id, String level, String startDate, String endDate) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "id": id,
          "level": level,
          "start_date": startDate,
          "end_date": endDate,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          // Atualiza os dados globais com os insights retornados
          setState(() {
            initialInsightsData = data['data']['insights'][0] ?? {};
          });
          return initialInsightsData;
        } else {
          throw Exception('Erro: ${data['data']}');
        }
      } else {
        throw Exception(
            'Erro na API: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Erro ao buscar insights da API: $e');
      throw e;
    }
  }
}
