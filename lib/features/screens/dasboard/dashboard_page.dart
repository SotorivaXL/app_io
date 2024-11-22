import 'dart:async';
import 'package:app_io/auth/providers/auth_provider.dart' as appProvider;
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? selectedCampaign;
  List<Map<String, dynamic>> selectedCampaigns = [];
  List<Map<String, dynamic>> campaignsList = [];

  List<Map<String, dynamic>> selectedGruposAnuncios = [];
  List<Map<String, dynamic>> gruposAnunciosList = [];

  List<Map<String, dynamic>> selectedAnuncios = [];
  List<Map<String, dynamic>> anunciosList = [];

  // Variável para armazenar os dados iniciais dos insights
  Map<String, dynamic> initialInsightsData = {};

  @override
  void initState() {
    super.initState();
    _fetchInitialInsights(); // Busca os dados iniciais ao criar o widget
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        body: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(10, 20, 10, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filtros
                _buildFilters(),
                const SizedBox(height: 20),
                // Cards com métricas principais
                _buildMetricCards(),
                const SizedBox(height: 20),
                // Gráfico de Alcance e Impressões
                _buildReachAndImpressionsChart(),
                const SizedBox(height: 20),
                // Gráfico de Custo por Resultado
                _buildCostPerResultChart(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    const double dropdownWidth = 200.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filtros',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
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

              return Column(
                children: [
                  // Dropdown de Campanhas
                  DropdownButtonFormField2<String>(
                    items: campaignsList.map((campaign) {
                      return DropdownMenuItem<String>(
                        value: campaign['id'] as String,
                        child: Text(
                          campaign['name'],
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          if (!selectedCampaigns
                              .any((campaign) => campaign['id'] == value)) {
                            selectedCampaigns.add(
                              campaignsList
                                  .firstWhere((campaign) => campaign['id'] == value),
                            );
                          }
                          // Limpa as seleções abaixo quando uma nova campanha é selecionada
                          selectedGruposAnuncios.clear();
                          gruposAnunciosList.clear();
                          selectedAnuncios.clear();
                          anunciosList.clear();
                        });
                      }
                    },
                    decoration: InputDecoration(
                      isDense: true, // Reduz o espaçamento interno vertical
                      contentPadding: EdgeInsets.fromLTRB(16.0, 0, 16.0, 10.0),
                      hintText: 'Selecione as campanhas',
                      hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(7.0),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.tertiary, width: 2),
                        borderRadius: BorderRadius.circular(7.0),
                      ),
                      errorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error, width: 2),
                        borderRadius: BorderRadius.circular(7.0),
                      ),
                      focusedErrorBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error, width: 2),
                        borderRadius: BorderRadius.circular(7.0),
                      ),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      maxHeight: 200.0,
                      width: dropdownWidth,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.background,
                      ),
                    ),
                    menuItemStyleData: const MenuItemStyleData(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                    ),
                    iconStyleData: IconStyleData(
                      icon: Icon(
                        Icons.keyboard_double_arrow_down_sharp,
                        color: Theme.of(context).colorScheme.onSecondary,
                        size: 20,
                      ),
                    ),
                    buttonStyleData: ButtonStyleData(
                      height: 50, // Ajuste a altura conforme necessário
                      padding:
                      EdgeInsets.zero, // Remove o padding horizontal padrão
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Chips de Campanhas Selecionadas
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: selectedCampaigns
                        .map<Widget>(
                          (campaign) => Chip(
                        backgroundColor:
                        Theme.of(context).colorScheme.tertiary,
                        side: BorderSide.none,
                        label: Text(campaign['name']),
                        onDeleted: () {
                          setState(() {
                            selectedCampaigns.remove(campaign);
                            // Limpa as seleções abaixo quando uma campanha é removida
                            selectedGruposAnuncios.clear();
                            gruposAnunciosList.clear();
                            selectedAnuncios.clear();
                            anunciosList.clear();
                          });
                        },
                      ),
                    )
                        .toList(),
                  ),
                  // Se campanhas foram selecionadas, exibe o dropdown de grupos de anúncios
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
                        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Text('Nenhum grupo de anúncios encontrado.');
                        } else {
                          gruposAnunciosList = snapshot.data!;

                          return Column(
                            children: [
                              // Dropdown de Grupos de Anúncios
                              DropdownButtonFormField2<String>(
                                items: gruposAnunciosList.map((grupo) {
                                  return DropdownMenuItem<String>(
                                    value: grupo['id'] as String,
                                    child: Text(
                                      grupo['name'],
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      if (!selectedGruposAnuncios.any(
                                              (grupo) => grupo['id'] == value)) {
                                        selectedGruposAnuncios.add(
                                          gruposAnunciosList.firstWhere(
                                                  (grupo) => grupo['id'] == value),
                                        );
                                      }
                                      // Limpa as seleções abaixo quando um novo grupo é selecionado
                                      selectedAnuncios.clear();
                                      anunciosList.clear();
                                    });
                                  }
                                },
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                  EdgeInsets.fromLTRB(16.0, 0, 16.0, 10.0),
                                  hintText: 'Selecione os grupos de anúncios',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .tertiary,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                  errorBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color:
                                        Theme.of(context).colorScheme.error,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                  focusedErrorBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color:
                                        Theme.of(context).colorScheme.error,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                ),
                                dropdownStyleData: DropdownStyleData(
                                  maxHeight: 200.0,
                                  width: dropdownWidth,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .background,
                                  ),
                                ),
                                menuItemStyleData: const MenuItemStyleData(
                                  padding:
                                  EdgeInsets.symmetric(horizontal: 16.0),
                                ),
                                iconStyleData: IconStyleData(
                                  icon: Icon(
                                    Icons.keyboard_double_arrow_down_sharp,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                    size: 20,
                                  ),
                                ),
                                buttonStyleData: ButtonStyleData(
                                  height: 50, // Ajuste a altura conforme necessário
                                  padding: EdgeInsets
                                      .zero, // Remove o padding horizontal padrão
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Chips de Grupos de Anúncios Selecionados
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                children: selectedGruposAnuncios
                                    .map<Widget>(
                                      (grupo) => Chip(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .tertiary,
                                    side: BorderSide.none,
                                    label: Text(grupo['name']),
                                    onDeleted: () {
                                      setState(() {
                                        selectedGruposAnuncios
                                            .remove(grupo);
                                        // Limpa as seleções abaixo quando um grupo é removido
                                        selectedAnuncios.clear();
                                        anunciosList.clear();
                                      });
                                    },
                                  ),
                                )
                                    .toList(),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                  ],
                  // Se grupos de anúncios foram selecionados, exibe o dropdown de anúncios
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
                        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Text('Nenhum anúncio encontrado.');
                        } else {
                          anunciosList = snapshot.data!;

                          return Column(
                            children: [
                              // Dropdown de Anúncios
                              DropdownButtonFormField2<String>(
                                items: anunciosList.map((anuncio) {
                                  return DropdownMenuItem<String>(
                                    value: anuncio['id'] as String,
                                    child: Text(
                                      anuncio['name'],
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      if (!selectedAnuncios.any(
                                              (anuncio) => anuncio['id'] == value)) {
                                        selectedAnuncios.add(
                                          anunciosList.firstWhere(
                                                  (anuncio) => anuncio['id'] == value),
                                        );
                                      }
                                    });
                                  }
                                },
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                  EdgeInsets.fromLTRB(16.0, 0, 16.0, 10.0),
                                  hintText: 'Selecione os anúncios',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                  ),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .tertiary,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                  errorBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color:
                                        Theme.of(context).colorScheme.error,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                  focusedErrorBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color:
                                        Theme.of(context).colorScheme.error,
                                        width: 2),
                                    borderRadius: BorderRadius.circular(7.0),
                                  ),
                                ),
                                dropdownStyleData: DropdownStyleData(
                                  maxHeight: 200.0,
                                  width: dropdownWidth,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .background,
                                  ),
                                ),
                                menuItemStyleData: const MenuItemStyleData(
                                  padding:
                                  EdgeInsets.symmetric(horizontal: 16.0),
                                ),
                                iconStyleData: IconStyleData(
                                  icon: Icon(
                                    Icons.keyboard_double_arrow_down_sharp,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                    size: 20,
                                  ),
                                ),
                                buttonStyleData: ButtonStyleData(
                                  height: 50, // Ajuste a altura conforme necessário
                                  padding: EdgeInsets
                                      .zero, // Remove o padding horizontal padrão
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Chips de Anúncios Selecionados
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                children: selectedAnuncios
                                    .map<Widget>(
                                      (anuncio) => Chip(
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .tertiary,
                                    side: BorderSide.none,
                                    label: Text(anuncio['name']),
                                    onDeleted: () {
                                      setState(() {
                                        selectedAnuncios.remove(anuncio);
                                      });
                                    },
                                  ),
                                )
                                    .toList(),
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
              color: Theme.of(context).colorScheme.primary,
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

  Widget _buildReachAndImpressionsChart() {
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
              'Alcance e Impressões',
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
                    alignment: BarChartAlignment.spaceAround,
                    barGroups: [
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: 8,
                            color: Theme.of(context).colorScheme.primary,
                            width: 15,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: 10,
                            color: Theme.of(context).colorScheme.primary,
                            width: 15,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                      BarChartGroupData(
                        x: 2,
                        barRods: [
                          BarChartRodData(
                            toY: 14,
                            color: Theme.of(context).colorScheme.primary,
                            width: 15,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: true),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: true),
                      ),
                    ),
                    gridData: FlGridData(show: true),
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

  Widget _buildCostPerResultChart() {
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
              'Custo por Resultado',
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
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(show: true),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: true),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: true),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 5,
                        belowBarData: BarAreaData(
                          show: true,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        ),
                        spots: [
                          FlSpot(0, 1),
                          FlSpot(1, 3),
                          FlSpot(2, 1.5),
                          FlSpot(3, 2.2),
                          FlSpot(4, 3.1),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
