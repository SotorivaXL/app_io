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
  static const String cachedInsightsKey = 'cached_insights';

  String? selectedContaAnuncioId;
  String? selectedCampaignId;
  String? selectedGrupoAnuncioId;
  bool _isExpanded = false;
  bool _isLoading = true;
  bool _isFiltering = false;
  final DateRangePickerController _datePickerController =
      DateRangePickerController();

  final String apiUrl =
      "https://us-central1-app-io-1c16f.cloudfunctions.net/getInsights";

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
    _fetchLatestInsights(); // Busca os dados atualizados diretamente do Firestore
  }

  // Método que agrega os insights com base nas contas carregadas
  // Método que agrega os insights com base nas contas carregadas
  Future<void> _fetchLatestInsights() async {
    try {
      setState(() { _isLoading = true; });

      // Carrega as contas se ainda não estiverem carregadas
      await _fetchInitialInsights(shouldSetState: false);
      if (adAccounts.isEmpty) {
        print('Nenhuma conta de anúncio encontrada.');
        setState(() { _isLoading = false; });
        return;
      }

      // Variáveis de agregação
      Map<String, double> aggregated = {};
      double totalSpend = 0.0;
      double totalReach = 0.0;
      double totalLinkClicks = 0.0;

      // Para cada conta, buscar os 30 documentos mais recentes da subcoleção "insights"
      for (var adAccount in adAccounts) {
        String bmId = adAccount['bmId'];
        String contaAnuncioDocId = adAccount['contaAnuncioDocId'];
        print("Processando insights para BM: $bmId, Conta: $contaAnuncioDocId");

        QuerySnapshot<Map<String, dynamic>> insightsSnapshot =
        await FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioDocId)
            .collection('insights')
            .orderBy(FieldPath.documentId, descending: true)
            .limit(30)
            .get();
        print("Total de documentos retornados: ${insightsSnapshot.docs.length}");

        for (var doc in insightsSnapshot.docs) {
          print("Processando documento: ${doc.id}");
          Map<String, dynamic> data = doc.data();
          print("Dados do documento ${doc.id}: $data");
          data.forEach((key, value) {
            double numericValue = 0.0;
            if (value is String) {
              numericValue = double.tryParse(value) ?? 0.0;
            } else if (value is num) {
              numericValue = value.toDouble();
            }
            double previous = aggregated[key] ?? 0.0;
            aggregated[key] = previous + numericValue;
            print("Aggregated [$key]: $previous + $numericValue = ${aggregated[key]}");

            if (key == 'spend') {
              totalSpend += numericValue;
              print("Total spend atualizado: $totalSpend");
            } else if (key == 'reach') {
              totalReach += numericValue;
              print("Total reach atualizado: $totalReach");
            } else if (key == 'inline_link_clicks') {
              totalLinkClicks += numericValue;
              print("Total inline_link_clicks atualizado: $totalLinkClicks");
            }
          });
        }
      }

      double calculatedCpm = totalReach > 0 ? (totalSpend / totalReach) * 1000 : 0.0;
      double calculatedCostPerLinkClick = totalLinkClicks > 0 ? (totalSpend / totalLinkClicks) : 0.0;
      aggregated['cpm'] = calculatedCpm;
      aggregated['cost_per_inline_link_click'] = calculatedCostPerLinkClick;
      print("CPM calculado: $calculatedCpm, Custo por clique: $calculatedCostPerLinkClick");

      setState(() {
        initialInsightsData = aggregated;
        _isLoading = false;
      });
    } catch (e, stacktrace) {
      print('Erro ao buscar insights recentes: $e');
      print(stacktrace);
      setState(() { _isLoading = false; });
      _handleApiError(e);
    }
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
    return 0.0;
  }

  void _openDateRangePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
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
                  disabledDatesTextStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .inverseSurface
                        .withOpacity(0.5),
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
                      fontSize: 12,
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
                  PickerDateRange? selectedRange =
                      _datePickerController.selectedRange;
                  if (selectedRange != null &&
                      selectedRange.startDate != null &&
                      selectedRange.endDate != null) {
                    setState(() {
                      startDate = selectedRange.startDate;
                      endDate = selectedRange.endDate;
                    });

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
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    return ConnectivityBanner(
      child: Scaffold(
        body: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(10, 20, 10, 0),
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(),
                )
              : isDesktop
                  ? Container(
                      constraints: BoxConstraints(
                        maxWidth: 1850,
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 50),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFilters(),
                            const SizedBox(height: 20),
                            _buildMetricCards(),
                            const SizedBox(height: 50),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilters(),
                          const SizedBox(height: 20),
                          _buildMetricCards(),
                          const SizedBox(height: 50),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _isExpanded
                ? Theme.of(context).colorScheme.background
                : Theme.of(context).colorScheme.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsetsDirectional.fromSTEB(28, 0, 0, 0),
                initiallyExpanded: _isExpanded,
                onExpansionChanged: (bool expanded) {
                  setState(() {
                    _isExpanded = expanded;
                  });
                },
                trailing: SizedBox.shrink(),
                backgroundColor: Colors.transparent,
                collapsedBackgroundColor: Colors.transparent,
                title: Center(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.filter_list,
                      size: _isExpanded ? 32.0 : 24.0,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
                children: [
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
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
                              ),
                            )
                          : Text(
                              "Selecione um intervalo de datas",
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
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
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchCampaigns(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        return Text('Erro: ${snapshot.error}');
                      } else {
                        final localCampaigns = snapshot.data ?? [];

                        var processedCampaigns = localCampaigns.map((campaign) {
                          campaign['id'] = campaign['id'].toString();
                          return campaign;
                        }).toList();

                        final ids = Set();
                        processedCampaigns
                            .retainWhere((campaign) => ids.add(campaign['id']));

                        List<Map<String, dynamic>> campaignOptions = [
                          {'id': '', 'name': 'Limpar Filtro', 'isError': true},
                          ...processedCampaigns.map((campaign) {
                            return {
                              'id': campaign['id'],
                              'name': campaign['name'],
                              'isError': false
                            };
                          }).toList(),
                        ];

                        if (selectedCampaignId != null) {
                          bool isSelectedIdValid = campaignOptions.any(
                              (option) => option['id'] == selectedCampaignId);
                          if (!isSelectedIdValid) {
                            selectedCampaignId = null;
                          }
                        }

                        return Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(top: 20.0),
                              child: SizedBox(
                                height: 50,
                                child: CustomDropdown(
                                  items: campaignOptions,
                                  value: selectedCampaignId,
                                  onChanged: (value) async {
                                    setState(() {
                                      selectedCampaignId = value;
                                      if (value != null && value.isNotEmpty) {
                                        selectedCampaigns = campaignOptions
                                            .where((option) =>
                                                option['id'] == value)
                                            .toList();
                                      } else {
                                        selectedCampaigns = [];
                                      }
                                      selectedGrupoAnuncioId = null;
                                      gruposAnunciosList.clear();
                                    });
                                    if (selectedCampaigns.isNotEmpty) {
                                      final grupos =
                                          await _fetchGruposAnuncios();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (mounted) {
                                          setState(() {
                                            gruposAnunciosList = grupos;
                                          });
                                        }
                                      });
                                    }
                                  },
                                  displayText: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Selecione a campanha';
                                    }
                                    final selectedItem =
                                        campaignOptions.firstWhere(
                                            (item) => item['id'] == value,
                                            orElse: () => {
                                                  'name': 'Selecione a campanha'
                                                });
                                    return selectedItem['name'];
                                  },
                                ),
                              ),
                            ),
                            if (selectedCampaigns.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: _fetchGruposAnuncios(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const CircularProgressIndicator();
                                  } else if (snapshot.hasError) {
                                    return CustomDropdown(
                                      items: [],
                                      value: null,
                                      onChanged: (_) {},
                                      displayText: (_) =>
                                          'Erro ao carregar grupos de anúncios',
                                    );
                                  } else {
                                    final localGruposAnuncios =
                                        snapshot.data ?? [];
                                    if (localGruposAnuncios.isEmpty) {
                                      return CustomDropdown(
                                        items: [],
                                        value: null,
                                        onChanged: (_) {},
                                        displayText: (_) =>
                                            'Nenhum grupo de anúncio encontrado',
                                      );
                                    }
                                    return CustomDropdown(
                                      items: localGruposAnuncios,
                                      value: selectedGrupoAnuncioId,
                                      onChanged: (value) {
                                        setState(() {
                                          selectedGrupoAnuncioId = value;
                                        });
                                      },
                                      displayText: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Selecione o grupo de anúncios';
                                        }
                                        final selectedItem =
                                            localGruposAnuncios.firstWhere(
                                                (item) => item['id'] == value,
                                                orElse: () => {
                                                      'name':
                                                          'Selecione o grupo de anúncios'
                                                    });
                                        return selectedItem['name'] ??
                                            'Selecione o grupo de anúncios';
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
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: _isFiltering
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.manage_search,
                            size: 22,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    label: Text(
                      _isFiltering ? 'Filtrando...' : 'Filtrar',
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
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    onPressed: _isFiltering
                        ? null
                        : () async {
                            setState(() {
                              _isFiltering = true;
                            });
                            try {
                              if (startDate == null || endDate == null) {
                                print(
                                    'Erro: Nenhum intervalo de datas foi selecionado.');
                                _handleApiError(
                                    'Por favor, selecione um intervalo de datas.');
                                return;
                              }
                              String dataInicial =
                                  DateFormat('yyyy-MM-dd').format(startDate!);
                              String dataFinal =
                                  DateFormat('yyyy-MM-dd').format(endDate!);

                              String? id;
                              String level;

                              if (selectedGrupoAnuncioId != null &&
                                  selectedCampaignId == null) {
                                id = selectedGrupoAnuncioId;
                                level = "adset";
                                print(
                                    'Buscando insights do grupo de anúncios: $id');
                              } else if (selectedCampaignId != null) {
                                id = selectedCampaignId;
                                level = "campaign";
                                print('Buscando insights da campanha: $id');
                              } else {
                                if (selectedContaAnuncioId == null) {
                                  await _fetchInitialInsights();
                                  if (selectedContaAnuncioId == null) {
                                    print(
                                        'Erro: ID da conta de anúncios não encontrado.');
                                    _handleApiError(
                                        'ID da conta de anúncios não encontrado.');
                                    return;
                                  }
                                }
                                id = selectedContaAnuncioId;
                                level = "account";
                                print('Buscando insights da conta: $id');
                              }

                              final insights = await _fetchMetaInsights(
                                  id!, level, dataInicial, dataFinal);

                              if (insights.isEmpty) {
                                _handleApiError(
                                    'Nenhum dado de insights encontrado.');
                              } else {
                                print(
                                    '\n--- Dados de Insights Recuperados ---');
                                insights.forEach((key, value) {
                                  print('$key: $value');
                                });
                              }
                            } catch (e) {
                              print('Erro ao buscar dados: $e');
                              _handleApiError(e.toString());
                            } finally {
                              setState(() {
                                _isFiltering = false;
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getFormattedValue(String key) {
    final dynamic dataValue = initialInsightsData[key];

    if (dataValue != null) {
      final double numericValue = _parseToDouble(dataValue);
      if (['spend', 'cost_per_inline_link_click', 'cpc'].contains(key)) {
        return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
            .format(numericValue);
      } else {
        return NumberFormat('#,##0', 'pt_BR').format(numericValue);
      }
    }
    return '—';
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
        'icon': FontAwesomeIcons.moneyBillTrendUp
      },
      {
        'title': 'Impressões',
        'key': 'impressions',
        'icon': FontAwesomeIcons.eye
      },
      {
        'title': 'Custo por Mil Pessoas Alcançadas (CPM)',
        'key': 'cpm',
        'icon': FontAwesomeIcons.sackDollar
      },
      {
        'title': 'Cliques no Link',
        'key': 'inline_link_clicks',
        'icon': FontAwesomeIcons.link
      },
      {
        'title': 'Custo por Clique no Link',
        'key': 'cost_per_inline_link_click',
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
            String value = '—';
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
              maxLines: 1,
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

  // Método que carrega as contas de anúncio (sem agregar os insights)
  // Método único que carrega as contas de anúncio (sem agregar insights)
  Future<void> _fetchInitialInsights({bool shouldSetState = true}) async {
    try {
      if (shouldSetState) {
        setState(() {
          _isLoading = true;
        });
      } else {
        _isLoading = true;
      }

      final authProvider =
      Provider.of<appProvider.AuthProvider>(context, listen: false);
      final user = authProvider.user;
      if (user == null) {
        print('Usuário não está logado.');
        if (shouldSetState) setState(() => _isLoading = false);
        return;
      }

      // Buscar documento da empresa
      DocumentSnapshot<Map<String, dynamic>> companyDoc =
      await FirebaseFirestore.instance.collection('empresas').doc(user.uid).get();
      print("CompanyDoc (uid ${user.uid}) exists: ${companyDoc.exists}");
      if (!companyDoc.exists) {
        DocumentSnapshot<Map<String, dynamic>> userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        print("UserDoc exists: ${userDoc.exists}");
        if (!userDoc.exists || !userDoc.data()!.containsKey('createdBy')) {
          print('Documento do usuário ou campo "createdBy" não encontrado.');
          if (shouldSetState) setState(() => _isLoading = false);
          return;
        }
        String companyId = userDoc.data()!['createdBy'];
        companyDoc =
        await FirebaseFirestore.instance.collection('empresas').doc(companyId).get();
        print("CompanyDoc (companyId $companyId) exists: ${companyDoc.exists}");
        if (!companyDoc.exists) {
          print('Documento da empresa não encontrado para companyId: $companyId');
          if (shouldSetState) setState(() => _isLoading = false);
          return;
        }
      }

      // Verificar se os campos necessários existem
      if (!companyDoc.data()!.containsKey('BMs') ||
          !companyDoc.data()!.containsKey('contasAnuncio')) {
        print('Campos BMs ou contasAnuncio não existem no documento da empresa.');
        if (shouldSetState) setState(() => _isLoading = false);
        return;
      }

      var bmIds = companyDoc.data()!['BMs'];
      var contaAnuncioIds = companyDoc.data()!['contasAnuncio'];
      if (bmIds is! List) bmIds = [bmIds];
      if (contaAnuncioIds is! List) contaAnuncioIds = [contaAnuncioIds];
      List<String> bmList = bmIds.map((e) => e.toString()).toList();
      List<String> contaAnuncioList = contaAnuncioIds.map((e) => e.toString()).toList();

      // Limpar a lista para evitar duplicação
      adAccounts = [];
      for (var bm in bmList) {
        for (var conta in contaAnuncioList) {
          DocumentSnapshot<Map<String, dynamic>> adAccountDoc =
          await FirebaseFirestore.instance
              .collection('dashboard')
              .doc(bm)
              .collection('contasAnuncio')
              .doc(conta)
              .get();
          if (adAccountDoc.exists) {
            // Antes de adicionar, verifique se essa conta já não está na lista
            bool exists = adAccounts.any((element) =>
            element['bmId'] == bm && element['contaAnuncioDocId'] == conta);
            if (!exists) {
              adAccounts.add({
                'id': adAccountDoc.data()?['id'],
                'name': adAccountDoc.data()?['name'],
                'bmId': bm,
                'contaAnuncioDocId': conta,
              });
              print("AdAccount carregada: BM: $bm, Conta: $conta, ID: ${adAccountDoc.data()?['id']}");
            } else {
              print("AdAccount já carregada: BM: $bm, Conta: $conta");
            }
          } else {
            print("Conta de anúncio não encontrada para BM: $bm e Conta: $conta");
          }
        }
      }

      if (adAccounts.isEmpty) {
        print("Nenhuma conta de anúncio encontrada.");
      } else {
        // Seleciona a primeira conta (pode ajustar essa lógica)
        selectedContaAnuncioId = adAccounts.first['id'];
        print("ID da conta de anúncios selecionada: $selectedContaAnuncioId");
      }

      if (shouldSetState) {
        setState(() { _isLoading = false; });
      } else {
        _isLoading = false;
      }
    } catch (e, stacktrace) {
      print("Erro ao buscar insights iniciais: $e");
      print(stacktrace);
      if (shouldSetState && mounted) {
        setState(() => _isLoading = false);
      } else {
        _isLoading = false;
      }
    }
  }

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

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        companyId = userDoc['createdBy'];
        empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(companyId)
            .get();

        if (!empresaDoc.exists) {
          print('Documento da empresa não encontrado.');
          return [];
        }
      } else {
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

      if (!empresaDoc.data()!.containsKey('BMs') ||
          !empresaDoc.data()!.containsKey('contasAnuncio')) {
        print(
            'Campos BMs ou contasAnuncio não existem no documento da empresa.');
        return [];
      }

      var bmIds = empresaDoc['BMs'];
      var contaAnuncioIds = empresaDoc['contasAnuncio'];

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
            print('Conta de anúncio não encontrada para BM $bmId');
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
      if (adAccounts.isEmpty) {
        await _fetchInitialInsights(shouldSetState: false);
        if (adAccounts.isEmpty) {
          print('Nenhuma conta de anúncio disponível para buscar campanhas.');
          return [];
        }
      }

      List<Map<String, dynamic>> allCampaigns = [];

      for (var adAccount in adAccounts) {
        String bmId = adAccount['bmId'];
        String contaAnuncioDocId = adAccount['contaAnuncioDocId'];
        String contaAnuncioId = adAccount['id'];

        final contaAnuncioDoc = FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioDocId);

        final campanhasSnapshot =
            await contaAnuncioDoc.collection('campanhas').get();

        for (var doc in campanhasSnapshot.docs) {
          var data = doc.data();
          allCampaigns.add({
            'id': data['id'].toString(),
            'name': data['name'],
            'bmId': bmId,
            'contaAnuncioId': contaAnuncioId,
            'contaAnuncioDocId': contaAnuncioDocId,
            'campaignDocId': doc.id,
          });
        }
      }

      final ids = Set();
      allCampaigns.retainWhere((campaign) => ids.add(campaign['id']));

      return allCampaigns;
    } catch (e, stacktrace) {
      print('Erro ao buscar campanhas: $e');
      print(stacktrace);
      throw 'Erro ao buscar campanhas: $e';
    }
  }

  Future<List<Map<String, dynamic>>> _fetchGruposAnuncios() async {
    try {
      List<Map<String, dynamic>> allGruposAnuncios = [];

      for (var campaign in selectedCampaigns) {
        String bmId = campaign['bmId'];
        String contaAnuncioDocId = campaign['contaAnuncioDocId'];
        String campaignId = campaign['id'];
        String campaignDocId = campaign['campaignDocId'];

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
          if (data['id'] == null || data['name'] == null) {
            print('Grupo de anúncio com dados faltando: ${doc.id}');
            continue;
          }
          allGruposAnuncios.add({
            'id': data['id'].toString(),
            'name': data['name'],
            'bmId': bmId,
            'contaAnuncioDocId': contaAnuncioDocId,
            'campaignId': campaignId,
            'campaignDocId': campaignDocId,
            'grupoAnuncioDocId': doc.id,
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
      if (id.isEmpty) throw Exception('ID não pode ser vazio');
      if (!['account', 'campaign', 'adset'].contains(level.toLowerCase())) {
        throw Exception('Nível inválido');
      }

      // Cria o corpo da requisição (como string JSON)
      final requestBody = json.encode({
        "id": id,
        "level": level,
        "start_date": startDate,
        "end_date": endDate,
      });
      print("Corpo enviado para a Cloud Function: $requestBody");

      // Envia a requisição com o header "application/json"
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: requestBody,
      );
      print("Resposta recebida: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            initialInsightsData = data['data']['insights'][0];
          });
          return initialInsightsData;
        } else {
          throw Exception('Erro: ${data['message']}');
        }
      } else {
        throw Exception(
            'Erro na Cloud Function: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Erro ao buscar insights: $e');
      throw e;
    }
  }

  void _handleApiError(dynamic error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Erro', style: TextStyle(color: Colors.red)),
        content: Text(
          error.toString(),
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
      ),
    );
  }

  void _updateMetrics(Map<String, dynamic> newData) {
    setState(() {
      initialInsightsData = newData;
      selectedCampaigns = [];
      selectedGruposAnuncios = [];
    });
    _buildMetricCards();
  }
}
