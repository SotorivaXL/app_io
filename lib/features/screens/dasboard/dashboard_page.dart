import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart' as appProvider;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';


class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
  String? selectedGrupoAnuncio; // Inicialmente nula
}

class _DashboardPageState extends State<DashboardPage> {
  String? selectedCampaignId;
  String? selectedGrupoAnuncio;
  String? selectedAnuncio;
  bool _isExpanded = false;
  final DateRangePickerController _datePickerController = DateRangePickerController();

  List<Map<String, dynamic>> selectedCampaigns = [];
  List<Map<String, dynamic>> campaignsList = [];

  List<Map<String, dynamic>> selectedGruposAnuncios = [];
  List<Map<String, dynamic>> gruposAnunciosList = [];

  List<Map<String, dynamic>> selectedAnuncios = [];
  List<Map<String, dynamic>> anunciosList = [];

  Map<String, dynamic> initialInsightsData = {};

  DateTime? startDate;
  DateTime? endDate;
  @override
  void initState() {
    super.initState();
    _fetchInitialInsights();
  }

  void _openDateRangePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Envolva o AlertDialog em um Theme para personalizar os estilos dos botões
        return Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
            ),
          ),
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.secondary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Text(
              'Selecione o intervalo de datas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
            content: SizedBox(
              width: 400,
              height: 350,
              child: SfDateRangePicker(
                controller: _datePickerController,
                backgroundColor: Theme.of(context).colorScheme.secondary,
                view: DateRangePickerView.month,
                selectionMode: DateRangePickerSelectionMode.range,
                showActionButtons: false, // Desabilita os botões internos
                initialSelectedRange: startDate != null && endDate != null
                    ? PickerDateRange(startDate, endDate)
                    : null,
                headerStyle: DateRangePickerHeaderStyle(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  textAlign: TextAlign.center,
                  textStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                monthCellStyle: DateRangePickerMonthCellStyle(
                  textStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onBackground,
                  ),
                  todayTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.tertiary,
                    fontWeight: FontWeight.bold,
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Personalização dos meses usando yearCellStyle
                yearCellStyle: DateRangePickerYearCellStyle(
                  textStyle: TextStyle(
                    fontSize: 15,
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                  // Destaque para o mês atual (opcional)
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
                  'CANCELAR',
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
                  'OK',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                onPressed: () {
                  PickerDateRange? selectedRange = _datePickerController.selectedRange;
                  if (selectedRange != null) {
                    setState(() {
                      startDate = selectedRange.startDate;
                      endDate = selectedRange.endDate;
                    });
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFilters(),
                const SizedBox(height: 20),
                _buildMetricCards(),
                const SizedBox(height: 20),
                _buildClicksReachImpressionsChart(),
                const SizedBox(height: 20),
                _buildSpendPercentageChart(),
                const SizedBox(height: 20),
                _buildCPCvsCPMChart(),
                const SizedBox(height: 20),
                _buildEngagementChart(),
                const SizedBox(height: 20),
                _buildInlineLinkClicksChart(),
                const SizedBox(height: 20),
                _buildClicksCPCCPMChart(),
                const SizedBox(height: 20),
                _buildRadialBarChart(),
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
        // Envolve o ExpansionTile em um Container para adicionar o arredondamento
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
                  child: SizedBox(
                    height: 20, // Altura padrão para centralizar verticalmente
                    child: Icon(
                      Icons.filter_list,
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
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12.0, horizontal: 16.0),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  // Espaçamento
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchCampaigns(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        return Text('Erro: ${snapshot.error}');
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Text('Nenhuma campanha encontrada.');
                      } else {
                        campaignsList = snapshot.data!;

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

                        return Column(
                          children: [
                            // Dropdown de Campanhas
                            Padding(
                              padding: EdgeInsets.only(top: 20.0),
                              child: SizedBox(
                                height: 50, // Aumenta a altura do dropdown
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  alignment: Alignment.center,
                                  value: selectedCampaignId,
                                  items: campaignOptions.map((option) {
                                    return DropdownMenuItem<String>(
                                      value: option['id'] as String,
                                      child: Center(
                                        child: Text(
                                          option['name'],
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: option['isError']
                                                ? Theme.of(context).colorScheme.error
                                                : Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == '') {
                                        // Limpa o filtro
                                        selectedCampaignId = null;
                                        selectedCampaigns.clear();
                                        selectedGrupoAnuncio = null;
                                        selectedGruposAnuncios.clear();
                                        gruposAnunciosList.clear();
                                        selectedAnuncio = null;
                                        selectedAnuncios.clear();
                                        anunciosList.clear();
                                      } else {
                                        selectedCampaignId = value;
                                        // Atualiza a campanha selecionada
                                        selectedCampaigns = [
                                          campaignsList.firstWhere(
                                                  (campaign) => campaign['id'] == value),
                                        ];
                                        // Limpa as seleções abaixo
                                        selectedGrupoAnuncio = null;
                                        selectedGruposAnuncios.clear();
                                        gruposAnunciosList.clear();
                                        selectedAnuncio = null;
                                        selectedAnuncios.clear();
                                        anunciosList.clear();
                                      }
                                    });
                                  },
                                  selectedItemBuilder: (BuildContext context) {
                                    return campaignOptions.map((option) {
                                      return Align(
                                        alignment: Alignment.center,
                                        child: Text(
                                          option['name'],
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: option['isError']
                                                ? Theme.of(context).colorScheme.error
                                                : Theme.of(context)
                                                .colorScheme
                                                .onSecondary,
                                          ),
                                        ),
                                      );
                                    }).toList();
                                  },
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor:
                                    Theme.of(context).colorScheme.secondary,
                                    contentPadding: EdgeInsets.symmetric(
                                        vertical: 10.0, horizontal: 0),
                                    border: UnderlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    isDense: true,
                                  ),
                                  icon: SizedBox.shrink(),
                                  dropdownColor:
                                  Theme.of(context).colorScheme.secondary,
                                  hint: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Selecione a campanha',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color:
                                        Theme.of(context).colorScheme.onSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Se campanhas foram selecionadas, exibe o dropdown de grupos
                            if (selectedCampaigns.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: _fetchGruposAnuncios(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const CircularProgressIndicator();
                                  } else if (snapshot.hasError) {
                                    return Text('Erro: ${snapshot.error}');
                                  } else if (!snapshot.hasData ||
                                      snapshot.data!.isEmpty) {
                                    return Text(
                                        'Nenhum grupo de anúncios encontrado.');
                                  } else {
                                    gruposAnunciosList = snapshot.data!;

                                    // Lista de opções combinada para itens e selectedItemBuilder
                                    List<Map<String, dynamic>> grupoOptions = [
                                      {'id': '', 'name': 'Limpar Filtro', 'isError': true},
                                      ...gruposAnunciosList.map((grupo) {
                                        return {
                                          'id': grupo['id'],
                                          'name': grupo['name'],
                                          'isError': false
                                        };
                                      }).toList(),
                                    ];

                                    return Column(
                                      children: [
                                        // Dropdown de Grupos de Anúncios
                                        SizedBox(
                                          height: 50, // Aumenta a altura do dropdown
                                          child: DropdownButtonFormField<String>(
                                            isExpanded: true,
                                            alignment: Alignment.center,
                                            value: selectedGrupoAnuncio,
                                            items: grupoOptions.map((option) {
                                              return DropdownMenuItem<String>(
                                                value: option['id'] as String,
                                                child: Center(
                                                  child: Text(
                                                    option['name'],
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                      color: option['isError']
                                                          ? Theme.of(context)
                                                          .colorScheme
                                                          .error
                                                          : Theme.of(context)
                                                          .colorScheme
                                                          .onSecondary,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (value) {
                                              setState(() {
                                                if (value == '') {
                                                  // Limpa o filtro
                                                  selectedGrupoAnuncio = null;
                                                  selectedGruposAnuncios.clear();
                                                  selectedAnuncio = null;
                                                  selectedAnuncios.clear();
                                                  anunciosList.clear();
                                                } else {
                                                  selectedGrupoAnuncio = value;
                                                  selectedGruposAnuncios = [
                                                    gruposAnunciosList.firstWhere(
                                                            (grupo) =>
                                                        grupo['id'] == value),
                                                  ];
                                                  // Limpa as seleções abaixo
                                                  selectedAnuncio = null;
                                                  selectedAnuncios.clear();
                                                  anunciosList.clear();
                                                }
                                              });
                                            },
                                            selectedItemBuilder:
                                                (BuildContext context) {
                                              return grupoOptions.map((option) {
                                                return Align(
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    option['name'],
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                      color: option['isError']
                                                          ? Theme.of(context)
                                                          .colorScheme
                                                          .error
                                                          : Theme.of(context)
                                                          .colorScheme
                                                          .onSecondary,
                                                    ),
                                                  ),
                                                );
                                              }).toList();
                                            },
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              contentPadding: EdgeInsets.symmetric(
                                                  vertical: 10.0, horizontal: 0),
                                              border: UnderlineInputBorder(
                                                borderRadius:
                                                BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              isDense: true,
                                            ),
                                            icon: SizedBox.shrink(),
                                            dropdownColor: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                            hint: Align(
                                              alignment: Alignment.center,
                                              child: Text(
                                                'Selecione o grupo de anúncios',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSecondary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ],
                            // Se grupos foram selecionados, exibe o dropdown de anúncios
                            if (selectedGruposAnuncios.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: _fetchAnuncios(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const CircularProgressIndicator();
                                  } else if (snapshot.hasError) {
                                    return Text('Erro: ${snapshot.error}');
                                  } else if (!snapshot.hasData ||
                                      snapshot.data!.isEmpty) {
                                    return Text('Nenhum anúncio encontrado.');
                                  } else {
                                    anunciosList = snapshot.data!;

                                    // Lista de opções combinada para itens e selectedItemBuilder
                                    List<Map<String, dynamic>> anuncioOptions = [
                                      {'id': '', 'name': 'Limpar Filtro', 'isError': true},
                                      ...anunciosList.map((anuncio) {
                                        return {
                                          'id': anuncio['id'],
                                          'name': anuncio['name'],
                                          'isError': false
                                        };
                                      }).toList(),
                                    ];

                                    return Column(
                                      children: [
                                        // Dropdown de Anúncios
                                        SizedBox(
                                          height: 50, // Aumenta a altura do dropdown
                                          child: DropdownButtonFormField<String>(
                                            isExpanded: true,
                                            alignment: Alignment.center,
                                            value: selectedAnuncio,
                                            items: anuncioOptions.map((option) {
                                              return DropdownMenuItem<String>(
                                                value: option['id'] as String,
                                                child: Center(
                                                  child: Text(
                                                    option['name'],
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                      color: option['isError']
                                                          ? Theme.of(context)
                                                          .colorScheme
                                                          .error
                                                          : Theme.of(context)
                                                          .colorScheme
                                                          .onSecondary,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (value) {
                                              setState(() {
                                                if (value == '') {
                                                  // Limpa o filtro
                                                  selectedAnuncio = null;
                                                  selectedAnuncios.clear();
                                                } else {
                                                  selectedAnuncio = value;
                                                  selectedAnuncios = [
                                                    anunciosList.firstWhere(
                                                            (anuncio) =>
                                                        anuncio['id'] == value),
                                                  ];
                                                }
                                              });
                                            },
                                            selectedItemBuilder:
                                                (BuildContext context) {
                                              return anuncioOptions.map((option) {
                                                return Align(
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    option['name'],
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                      color: option['isError']
                                                          ? Theme.of(context)
                                                          .colorScheme
                                                          .error
                                                          : Theme.of(context)
                                                          .colorScheme
                                                          .onSecondary,
                                                    ),
                                                  ),
                                                );
                                              }).toList();
                                            },
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: Theme.of(context)
                                                  .colorScheme
                                                  .secondary,
                                              contentPadding: EdgeInsets.symmetric(
                                                  vertical: 10.0, horizontal: 0),
                                              border: UnderlineInputBorder(
                                                borderRadius:
                                                BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              isDense: true,
                                            ),
                                            icon: SizedBox.shrink(),
                                            dropdownColor: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                            hint: Align(
                                              alignment: Alignment.center,
                                              child: Text(
                                                'Selecione o anúncio',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSecondary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildMetricCards() {
    // Lista de métricas com títulos, chaves e ícones correspondentes
    final List<Map<String, dynamic>> metrics = [
      {
        'title': 'Alcance',
        'key': 'reach',
        'icon': FontAwesomeIcons.chartSimple,
      },
      {
        'title': 'Resultado',
        'key': 'conversions',
        'icon': FontAwesomeIcons.filterCircleDollar,
      },
      {
        'title': 'Custo por Resultado',
        'key': 'conversions',
        'icon': FontAwesomeIcons.circleDollarToSlot,
      },
      {
        'title': 'Valor Gasto',
        'key': 'spend',
        'icon': FontAwesomeIcons.moneyBillTransfer,
      },
    ];

    final formatter = NumberFormat('#,##0', 'pt_BR');
    final currencyFormatter =
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return LayoutBuilder(
      builder: (context, constraints) {
        // Determina o número de colunas com base na largura disponível
        int columns = constraints.maxWidth ~/
            160; // Cada card precisa de pelo menos 160 pixels
        columns = columns > 0 ? columns : 1;
        double itemWidth = (constraints.maxWidth - (columns - 1) * 16) / columns;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: metrics.map((metric) {
            String value = '—'; // Placeholder quando não há dados
            if (selectedCampaigns.isEmpty && initialInsightsData.isNotEmpty) {
              // Se nenhuma campanha selecionada, usa os dados iniciais
              dynamic dataValue = initialInsightsData[metric['key']];
              if (dataValue != null) {
                // Formata o valor de acordo com o tipo
                if (metric['key'] == 'spend' ||
                    metric['key'] == 'CPM' ||
                    metric['key'] == 'CPC' ||
                    metric['key'] == 'cost_per_result') {
                  // Valores monetários
                  value = currencyFormatter.format(dataValue);
                } else if (metric['key'] == 'frequency') {
                  // Valores decimais
                  value = dataValue.toStringAsFixed(2);
                } else {
                  // Outros valores numéricos
                  value = formatter.format(dataValue);
                }
              }
            } else {
              // Se campanhas selecionadas, você pode implementar a lógica para obter os dados correspondentes
              value = '—'; // Placeholder
            }

            return SizedBox(
              width: itemWidth,
              child: _buildMetricCard(
                metric['title'],
                value,
                metric['icon'],
              ),
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

  Widget _buildClicksReachImpressionsChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Cliques, Alcance e Impressões',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1.5,
              child: Center(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceEvenly,
                    maxY: _getMaxYValue([
                      initialInsightsData['clicks'],
                      initialInsightsData['reach'],
                      initialInsightsData['impressions'],
                    ]),
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: initialInsightsData['clicks']?.toDouble() ?? 0,
                            color: Colors.blueAccent,
                            width: 20,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: initialInsightsData['reach']?.toDouble() ?? 0,
                            color: Colors.greenAccent,
                            width: 20,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 2,
                        barRods: [
                          BarChartRodData(
                            toY: initialInsightsData['impressions']?.toDouble() ?? 0,
                            color: Colors.purpleAccent,
                            width: 20,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ],
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (value, meta) {
                            switch (value.toInt()) {
                              case 0:
                                return Text('Cliques');
                              case 1:
                                return Text('Alcance');
                              case 2:
                                return Text('Impressões');
                              default:
                                return Text('');
                            }
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

// Função para calcular o valor máximo do eixo Y
  double _getMaxYValue(List<dynamic> values) {
    double max = 0;
    for (var value in values) {
      double val = value?.toDouble() ?? 0;
      if (val > max) {
        max = val;
      }
    }
    // Adiciona um buffer de 10% ao valor máximo
    return max * 1.1;
  }



  Widget _buildSpendPercentageChart() {
    // Realiza os cálculos
    double totalSpend = initialInsightsData['spend']?.toDouble() ?? 0;

    double cpcSpend = (initialInsightsData['cpc']?.toDouble() ?? 0) * (initialInsightsData['clicks']?.toDouble() ?? 0);
    double cpmSpend = (initialInsightsData['cpm']?.toDouble() ?? 0) * (initialInsightsData['impressions']?.toDouble() ?? 0) / 1000;
    double costPerLinkClickSpend = (initialInsightsData['cost_per_inline_link_click']?.toDouble() ?? 0) * (initialInsightsData['inline_link_clicks']?.toDouble() ?? 0);

    double totalCalculatedSpend = cpcSpend + cpmSpend + costPerLinkClickSpend;

    double cpcPercentage = (cpcSpend / totalSpend) * 100;
    double cpmPercentage = (cpmSpend / totalSpend) * 100;
    double costPerLinkClickPercentage = (costPerLinkClickSpend / totalSpend) * 100;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Percentual de Gastos',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1.5,
              child: PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(
                      color: Colors.blueAccent,
                      value: cpcPercentage,
                      title: 'CPC (${cpcPercentage.toStringAsFixed(1)}%)',
                      radius: 50,
                      titleStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.greenAccent,
                      value: cpmPercentage,
                      title: 'CPM (${cpmPercentage.toStringAsFixed(1)}%)',
                      radius: 50,
                      titleStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.redAccent,
                      value: costPerLinkClickPercentage,
                      title: 'Custo por Clique (${costPerLinkClickPercentage.toStringAsFixed(1)}%)',
                      radius: 50,
                      titleStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCPCvsCPMChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'CPC vs. CPM',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1.5,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceEvenly,
                  maxY: _getMaxYValue([
                    initialInsightsData['cpc'],
                    initialInsightsData['cpm'],
                  ]),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: initialInsightsData['cpc']?.toDouble() ?? 0,
                          color: Colors.tealAccent,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: initialInsightsData['cpm']?.toDouble() ?? 0,
                          color: Colors.indigoAccent,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ],
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return Text('CPC');
                            case 1:
                              return Text('CPM');
                            default:
                              return Text('');
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngagementChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Engajamento Total',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1.5,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.center,
                  maxY: _getMaxYValue([
                    (initialInsightsData['inline_link_clicks']?.toDouble() ?? 0) +
                        (initialInsightsData['inline_post_engagement']?.toDouble() ?? 0),
                  ]),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: (initialInsightsData['inline_link_clicks']?.toDouble() ?? 0) +
                              (initialInsightsData['inline_post_engagement']?.toDouble() ?? 0),
                          rodStackItems: [
                            BarChartRodStackItem(
                              0,
                              initialInsightsData['inline_link_clicks']?.toDouble() ?? 0,
                              Colors.orangeAccent,
                            ),
                            BarChartRodStackItem(
                              initialInsightsData['inline_link_clicks']?.toDouble() ?? 0,
                              (initialInsightsData['inline_link_clicks']?.toDouble() ?? 0) +
                                  (initialInsightsData['inline_post_engagement']?.toDouble() ?? 0),
                              Colors.pinkAccent,
                            ),
                          ],
                          width: 40,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ],
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          return Text('Engajamento');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineLinkClicksChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Clicks em Links vs. Custo por Clique',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1.5,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxYValue([
                    initialInsightsData['inline_link_clicks'],
                    initialInsightsData['cost_per_inline_link_click'],
                  ]),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: initialInsightsData['inline_link_clicks']?.toDouble() ?? 0,
                          color: Colors.blueAccent,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                      showingTooltipIndicators: [0],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: initialInsightsData['cost_per_inline_link_click']?.toDouble() ?? 0,
                          color: Colors.redAccent,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                      showingTooltipIndicators: [0],
                    ),
                  ],
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return Text('Clicks em Links');
                            case 1:
                              return Text('Custo por Clique');
                            default:
                              return Text('');
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClicksCPCCPMChart() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Clicks, CPC e CPM',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1.5,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceEvenly,
                  maxY: _getMaxYValue([
                    initialInsightsData['clicks'],
                    initialInsightsData['cpc'],
                    initialInsightsData['cpm'],
                  ]),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: initialInsightsData['clicks']?.toDouble() ?? 0,
                          color: Colors.blueAccent,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: initialInsightsData['cpc']?.toDouble() ?? 0,
                          color: Colors.greenAccent,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [
                        BarChartRodData(
                          toY: initialInsightsData['cpm']?.toDouble() ?? 0,
                          color: Colors.purpleAccent,
                          width: 20,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ],
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return Text('Clicks');
                            case 1:
                              return Text('CPC');
                            case 2:
                              return Text('CPM');
                            default:
                              return Text('');
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadialBarChart() {
    double impressionsValue = initialInsightsData['impressions']?.toDouble() ?? 0;
    double reachValue = initialInsightsData['reach']?.toDouble() ?? 0;
    double spendValue = initialInsightsData['spend']?.toDouble() ?? 0;

    // Normalizar os valores para percentuais
    double maxValue = [impressionsValue, reachValue, spendValue].reduce((a, b) => a > b ? a : b);

    double impressionsPercent = (impressionsValue / maxValue) * 100;
    double reachPercent = (reachValue / maxValue) * 100;
    double spendPercent = (spendValue / maxValue) * 100;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Theme.of(context).colorScheme.secondary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Comparação Radial',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onBackground,
              ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          color: Colors.blueAccent,
                          value: 100,
                          radius: 80,
                          title: '',
                        ),
                      ],
                      startDegreeOffset: 270,
                      sectionsSpace: 0,
                      centerSpaceRadius: 0,
                    ),
                  ),
                  PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          color: Theme.of(context).colorScheme.secondary,
                          value: 100 - impressionsPercent,
                          radius: 80,
                          title: '',
                        ),
                      ],
                      startDegreeOffset: 270 + (impressionsPercent / 100) * 360,
                      sectionsSpace: 0,
                      centerSpaceRadius: 0,
                    ),
                  ),
                  PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          color: Colors.greenAccent,
                          value: 100,
                          radius: 60,
                          title: '',
                        ),
                      ],
                      startDegreeOffset: 270,
                      sectionsSpace: 0,
                      centerSpaceRadius: 0,
                    ),
                  ),
                  PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          color: Theme.of(context).colorScheme.secondary,
                          value: 100 - reachPercent,
                          radius: 60,
                          title: '',
                        ),
                      ],
                      startDegreeOffset: 270 + (reachPercent / 100) * 360,
                      sectionsSpace: 0,
                      centerSpaceRadius: 0,
                    ),
                  ),
                  PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          color: Colors.redAccent,
                          value: 100,
                          radius: 40,
                          title: '',
                        ),
                      ],
                      startDegreeOffset: 270,
                      sectionsSpace: 0,
                      centerSpaceRadius: 0,
                    ),
                  ),
                  PieChart(
                    PieChartData(
                      sections: [
                        PieChartSectionData(
                          color: Theme.of(context).colorScheme.secondary,
                          value: 100 - spendPercent,
                          radius: 40,
                          title: '',
                        ),
                      ],
                      startDegreeOffset: 270 + (spendPercent / 100) * 360,
                      sectionsSpace: 0,
                      centerSpaceRadius: 0,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 10, height: 10, color: Colors.blueAccent),
                    SizedBox(width: 5),
                    Text('Impressões'),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 10, height: 10, color: Colors.greenAccent),
                    SizedBox(width: 5),
                    Text('Alcance'),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 10, height: 10, color: Colors.redAccent),
                    SizedBox(width: 5),
                    Text('Gasto'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchInitialInsights() async {
    try {
      final authProvider = Provider.of<appProvider.AuthProvider>(context, listen: false);
      final user = authProvider.user;

      if (user == null) {
        print('Usuário não está logado.');
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
            print('Documento da empresa não encontrado para o companyId: $companyId');
            return;
          }
        } else {
          print('Campo "createdBy" não encontrado no documento do usuário.');
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
          print('Usuário é uma "empresa". Documento da empresa: ${empresaDoc.data()}');
          companyId = user.uid;
        } else {
          print('Usuário não é "user" nem "empresa". Documento não encontrado.');
          return;
        }
      }

      // Verifica se os campos BMs e contasAnuncio existem
      print('Verificando se os campos BMs e contasAnuncio existem...');
      if (!empresaDoc.data()!.containsKey('BMs') || !empresaDoc.data()!.containsKey('contasAnuncio')) {
        print('Campos BMs ou contasAnuncio não existem no documento da empresa.');
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
        contaAnuncioIds = contaAnuncioIds.expand((e) => e is List ? e : [e]).toList();
      }

      // Converte os itens das listas para String, caso ainda não sejam
      bmIds = bmIds.map((e) => e.toString()).toList();
      contaAnuncioIds = contaAnuncioIds.map((e) => e.toString()).toList();

      print('BM IDs após processamento: $bmIds, Conta Anúncio IDs após processamento: $contaAnuncioIds');

      Map<String, dynamic> combinedInsights = {};

      for (var bmId in bmIds) {
        for (var contaAnuncioId in contaAnuncioIds) {
          print('Processando BM ID: $bmId, Conta Anúncio ID: $contaAnuncioId');

          // Acessa o documento "dados_insights" na coleção "insights"
          final dadosInsightsDoc = await FirebaseFirestore.instance
              .collection('dashboard')
              .doc(bmId)
              .collection('contasAnuncio')
              .doc(contaAnuncioId)
              .collection('insights')
              .doc('dados_insights')
              .get();

          if (dadosInsightsDoc.exists) {
            print('Documento de insights encontrado para BM ID $bmId e Conta Anúncio ID $contaAnuncioId');
            List<dynamic>? insightsList = dadosInsightsDoc.data()?['insights'];

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
              print('Nenhum dado de insights encontrado no documento de insights.');
            }
          } else {
            print('Documento de insights não encontrado para BM ID $bmId e Conta Anúncio ID $contaAnuncioId');
          }
        }
      }

      setState(() {
        initialInsightsData = combinedInsights;
      });

      print('Dados de insights combinados: $combinedInsights');
    } catch (e, stacktrace) {
      print('Erro ao buscar insights iniciais: $e');
      print(stacktrace);
    }
  }


  // Método para buscar campanhas
  Future<List<Map<String, dynamic>>> _fetchCampaigns() async {
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
        print('Usuário é um "user"');
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
          print('Usuário é uma "empresa"');
          companyId = user.uid;
        } else {
          print('Usuário não é "user" nem "empresa"');
          return [];
        }
      }

      // Verifica se os campos BMs e contasAnuncio existem
      if (!empresaDoc.data()!.containsKey('BMs') ||
          !empresaDoc.data()!.containsKey('contasAnuncio')) {
        print(
            'Campos BMs ou contasAnuncio não existem no documento da empresa.');
        return [];
      }

      // Obtém as BMs e as contas de anúncio vinculadas à empresa
      var bmIds = empresaDoc['BMs'];
      var contaAnuncioIds = empresaDoc['contasAnuncio'];

      print('BM IDs: $bmIds, Conta Anúncio IDs: $contaAnuncioIds');

      // Garante que bmIds e contaAnuncioIds sejam listas
      if (bmIds is! List) {
        bmIds = [bmIds];
      }
      if (contaAnuncioIds is! List) {
        contaAnuncioIds = [contaAnuncioIds];
      }

      List<Map<String, dynamic>> allCampaigns = [];

      for (var bmId in bmIds) {
        for (var contaAnuncioId in contaAnuncioIds) {
          print('Processando BM ID: $bmId, Conta Anúncio ID: $contaAnuncioId');

          // Busca as campanhas na coleção "dashboard"
          final dashboardDoc =
          FirebaseFirestore.instance.collection('dashboard').doc(bmId);

          final contaAnuncioDoc =
          dashboardDoc.collection('contasAnuncio').doc(contaAnuncioId);

          final campanhasSnapshot =
          await contaAnuncioDoc.collection('campanhas').get();

          print(
              'Número de campanhas encontradas para BM $bmId e Conta $contaAnuncioId: ${campanhasSnapshot.docs.length}');

          allCampaigns.addAll(campanhasSnapshot.docs.map((doc) => {
            'id': doc.id,
            'name': doc['name'],
            'bmId': bmId,
            'contaAnuncioId': contaAnuncioId,
          }));
        }
      }

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
        String contaAnuncioId = campaign['contaAnuncioId'];
        String campaignId = campaign['id'];

        final gruposAnunciosSnapshot = await FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioId)
            .collection('campanhas')
            .doc(campaignId)
            .collection('gruposAnuncios')
            .get();

        allGruposAnuncios.addAll(gruposAnunciosSnapshot.docs.map((doc) => {
          'id': doc.id,
          'name': doc['name'],
          'bmId': bmId,
          'contaAnuncioId': contaAnuncioId,
          'campaignId': campaignId,
        }));
      }

      return allGruposAnuncios;
    } catch (e, stacktrace) {
      print('Erro ao buscar grupos de anúncios: $e');
      print(stacktrace);
      throw 'Erro ao buscar grupos de anúncios: $e';
    }
  }

  // Método para buscar anúncios
  Future<List<Map<String, dynamic>>> _fetchAnuncios() async {
    try {
      List<Map<String, dynamic>> allAnuncios = [];

      for (var grupo in selectedGruposAnuncios) {
        String bmId = grupo['bmId'];
        String contaAnuncioId = grupo['contaAnuncioId'];
        String campaignId = grupo['campaignId'];
        String grupoAnuncioId = grupo['id'];

        final anunciosSnapshot = await FirebaseFirestore.instance
            .collection('dashboard')
            .doc(bmId)
            .collection('contasAnuncio')
            .doc(contaAnuncioId)
            .collection('campanhas')
            .doc(campaignId)
            .collection('gruposAnuncios')
            .doc(grupoAnuncioId)
            .collection('anuncios')
            .get();

        allAnuncios.addAll(anunciosSnapshot.docs.map((doc) => {
          'id': doc.id,
          'name': doc['name'],
          'bmId': bmId,
          'contaAnuncioId': contaAnuncioId,
          'campaignId': campaignId,
          'grupoAnuncioId': grupoAnuncioId,
        }));
      }

      return allAnuncios;
    } catch (e, stacktrace) {
      print('Erro ao buscar anúncios: $e');
      print(stacktrace);
      throw 'Erro ao buscar anúncios: $e';
    }
  }
}