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
                    color: Theme.of(context).colorScheme.inverseSurface.withOpacity(0.5),
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
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchCampaigns(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        return Text('Erro: ${snapshot.error}');
                      } else {
                        // Não atualiza diretamente campaignsList aqui
                        final localCampaigns = snapshot.data ?? [];

                        // Processa localmente as campanhas sem modificar o estado
                        var processedCampaigns = localCampaigns.map((campaign) {
                          campaign['id'] = campaign['id'].toString();
                          return campaign;
                        }).toList();

                        final ids = Set();
                        processedCampaigns
                            .retainWhere((campaign) => ids.add(campaign['id']));

                        // Cria a lista de opções local
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

                        // Verifica se selectedCampaignId ainda é válido
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
                                      final grupos = await _fetchGruposAnuncios();
                                      // Agenda atualização após o frame atual
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
                                    final selectedItem = campaignOptions
                                        .firstWhere(
                                            (item) => item['id'] == value,
                                        orElse: () => {
                                          'name':
                                          'Selecione a campanha'
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
                                        final selectedItem = localGruposAnuncios.firstWhere(
                                              (item) => item['id'] == value,
                                          orElse: () => {
                                            'name': 'Selecione o grupo de anúncios'
                                          },
                                        );
                                        return selectedItem['name'] ?? 'Selecione o grupo de anúncios';
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
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    onPressed: _isFiltering
                        ? null
                        : () async {
                      // Desativa o botão e exibe o CircularProgressIndicator
                      setState(() {
                        _isFiltering = true;
                      });
                      try {
                        if (startDate == null || endDate == null) {
                          print('Erro: Nenhum intervalo de datas foi selecionado.');
                          _handleApiError('Por favor, selecione um intervalo de datas.');
                          return;
                        }

                        String dataInicial =
                        DateFormat('yyyy-MM-dd').format(startDate!);
                        String dataFinal = DateFormat('yyyy-MM-dd').format(endDate!);

                        String? id;
                        String level;

                        // Hierarquia correta de seleção
                        if (selectedGrupoAnuncioId != null && selectedCampaignId == null) {
                          // Nível Adset (grupo de anúncios)
                          id = selectedGrupoAnuncioId;
                          level = "adset";
                          print('Buscando insights do grupo de anúncios: $id');
                        } else if (selectedCampaignId != null) {
                          // Nível Campaign
                          id = selectedCampaignId;
                          level = "campaign";
                          print('Buscando insights da campanha: $id');
                        } else {
                          // Nível Account (conta de anúncios)
                          if (selectedContaAnuncioId == null) {
                            await _fetchInitialInsights();
                            if (selectedContaAnuncioId == null) {
                              print('Erro: ID da conta de anúncios não encontrado.');
                              _handleApiError('ID da conta de anúncios não encontrado.');
                              return;
                            }
                          }
                          id = selectedContaAnuncioId;
                          level = "account";
                          print('Buscando insights da conta: $id');
                        }

                        final insights = await _fetchMetaInsights(
                          id!,
                          level,
                          dataInicial,
                          dataFinal,
                        );

                        if (insights.isEmpty) {
                          _handleApiError('Nenhum dado de insights encontrado.');
                        } else {
                          print('\n--- Dados de Insights Recuperados ---');
                          insights.forEach((key, value) {
                            print('$key: $value');
                          });
                        }
                      } catch (e) {
                        print('Erro ao buscar dados: $e');
                        _handleApiError(e.toString());
                      } finally {
                        // Reativa o botão após o carregamento ou erro
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
        // Formata como valor monetário
        return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(numericValue);
      } else {
        // Formata como número com separador de milhares
        return NumberFormat('#,##0', 'pt_BR').format(numericValue);
      }
    }
    return '—'; // Valor padrão se não houver dados
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
        if (shouldSetState) {
          setState(() {
            _isLoading = false;
          });
        } else {
          _isLoading = false;
        }
        return;
      }

      String? companyId;
      DocumentSnapshot<Map<String, dynamic>>? empresaDoc;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        if (userDoc.data()!.containsKey('createdBy')) {
          companyId = userDoc['createdBy'];
          empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(companyId)
              .get();

          if (!empresaDoc.exists) {
            print('Documento da empresa não encontrado para o companyId: $companyId');
            if (shouldSetState) {
              setState(() {
                _isLoading = false;
              });
            } else {
              _isLoading = false;
            }
            return;
          }
        } else {
          print('Campo "createdBy" não encontrado no documento do usuário.');
          if (shouldSetState) {
            setState(() {
              _isLoading = false;
            });
          } else {
            _isLoading = false;
          }
          return;
        }
      } else {
        empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(user.uid)
            .get();

        if (empresaDoc.exists) {
          companyId = user.uid;
        } else {
          print('Usuário não é "user" nem "empresa".');
          if (shouldSetState) {
            setState(() {
              _isLoading = false;
            });
          } else {
            _isLoading = false;
          }
          return;
        }
      }

      if (!empresaDoc.data()!.containsKey('BMs') ||
          !empresaDoc.data()!.containsKey('contasAnuncio')) {
        print('Campos BMs ou contasAnuncio não existem no documento da empresa.');
        if (shouldSetState) {
          setState(() {
            _isLoading = false;
          });
        } else {
          _isLoading = false;
        }
        return;
      }

      var bmIds = empresaDoc['BMs'];
      var contaAnuncioIds = empresaDoc['contasAnuncio'];

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

      bmIds = bmIds.map((e) => e.toString()).toList();
      contaAnuncioIds = contaAnuncioIds.map((e) => e.toString()).toList();

      adAccounts = [];

      for (var bmId in bmIds) {
        for (var contaAnuncioDocId in contaAnuncioIds) {
          final adAccountDoc = await FirebaseFirestore.instance
              .collection('dashboard')
              .doc(bmId)
              .collection('contasAnuncio')
              .doc(contaAnuncioDocId)
              .get();

          if (adAccountDoc.exists) {
            adAccounts.add({
              'id': adAccountDoc.data()?['id'],
              'name': adAccountDoc.data()?['name'],
              'bmId': bmId,
              'contaAnuncioDocId': contaAnuncioDocId,
            });
          } else {
            print(
                'Conta de anúncio não encontrada para BM ID $bmId e Conta Anúncio Doc ID $contaAnuncioDocId');
          }
        }
      }

      if (adAccounts.isNotEmpty) {
        selectedContaAnuncioId = adAccounts.first['id'];
        print('ID da conta de anúncios selecionada: $selectedContaAnuncioId');
      } else {
        print('Nenhuma conta de anúncio encontrada.');
        if (shouldSetState) {
          setState(() {
            _isLoading = false;
          });
        } else {
          _isLoading = false;
        }
        return;
      }

      Map<String, dynamic> combinedInsights = {};

      for (var adAccount in adAccounts) {
        String bmId = adAccount['bmId'];
        String contaAnuncioDocId = adAccount['contaAnuncioDocId'];

        final dadosInsightsDoc = await FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioDocId)
            .collection('insights')
            .doc('dados_insights')
            .get();

        if (dadosInsightsDoc.exists) {
          Map<String, dynamic>? insightsData = dadosInsightsDoc.data();

          if (insightsData != null) {
            if (insightsData.containsKey('insights')) {
              List<dynamic>? insightsList = insightsData['insights'];
              if (insightsList != null && insightsList is List) {
                for (var insight in insightsList) {
                  if (insight is Map<String, dynamic>) {
                    insight.forEach((key, value) {
                      if (value is String) {
                        final numValue = num.tryParse(value);
                        if (numValue != null) {
                          combinedInsights[key] =
                              (combinedInsights[key] ?? 0) + numValue;
                        }
                      } else if (value is num) {
                        combinedInsights[key] =
                            (combinedInsights[key] ?? 0) + value;
                      }
                    });
                  }
                }
              }
            } else {
              insightsData.forEach((key, value) {
                if (value is String) {
                  final numValue = num.tryParse(value);
                  if (numValue != null) {
                    combinedInsights[key] =
                        (combinedInsights[key] ?? 0) + numValue;
                  }
                } else if (value is num) {
                  combinedInsights[key] =
                      (combinedInsights[key] ?? 0) + value;
                }
              });
            }
          }
        }
      }

      if (shouldSetState) {
        setState(() {
          initialInsightsData = combinedInsights;
          _isLoading = false;
        });
      } else {
        initialInsightsData = combinedInsights;
        _isLoading = false;
      }

    } catch (e, stacktrace) {
      print('Erro ao buscar insights iniciais: $e');
      print(stacktrace);
      if (shouldSetState && mounted) {
        setState(() {
          _isLoading = false;
        });
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
        print('Campos BMs ou contasAnuncio não existem no documento da empresa.');
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
        // Em vez de chamar setState diretamente, chamamos a função sem atualizar o estado
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
          // Verifique se 'id' e 'name' não são nulos
          if (data['id'] == null || data['name'] == null) {
            print('Grupo de anúncio com dados faltando: ${doc.id}');
            continue; // Pule este item
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
      // Nova validação de parâmetros
      if (id.isEmpty) throw Exception('ID não pode ser vazio');
      if (!['account', 'campaign', 'adset'].contains(level.toLowerCase())) {
        throw Exception('Nível inválido');
      }

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
          // Verifique se 'insights' não está vazio
          if (data['data']['insights'] != null && data['data']['insights'].isNotEmpty) {
            setState(() {
              initialInsightsData = data['data']['insights'][0];
            });
            return initialInsightsData;
          } else {
            throw Exception('Nenhum insight encontrado para os parâmetros fornecidos.');
          }
        } else {
          throw Exception('Erro: ${data['message']}');
        }
      } else {
        throw Exception('Erro na Cloud Function: ${response.statusCode} - ${response.body}');
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

      // Atualize outras variáveis de estado se necessário
      selectedCampaigns = [];
      selectedGruposAnuncios = [];
    });

    // Forçar reconstrução dos widgets
    _buildMetricCards();
  }
}