import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/CustomTabBar/custom_tabBar.dart';
import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as appAuthProvider;
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? userName;
  bool hasLeadsAccess = false;
  bool hasDashboardAccess = false;

  @override
  void initState() {
    super.initState();
    _getUserData();
  }

  Future<void> _getUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        // Tenta buscar o documento do usuário na coleção 'users'
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          // Se encontrado na coleção 'users', armazena e exibe o nome do usuário
          final data = userDoc.data();
          if (data != null) {
            String userName = data['name'] ?? '';
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString('userName', userName);

            setState(() {
              this.userName = userName;
            });
          }
        } else {
          // Se não encontrado na coleção 'users', tenta buscar na coleção 'empresas'
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();

          if (empresaDoc.exists) {
            final data = empresaDoc.data();
            if (data != null) {
              String userName = data['NomeEmpresa'] ?? '';
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString('userName', userName);

              setState(() {
                this.userName = userName;
              });
            }
          } else {
            // Se não encontrado em nenhuma das coleções, exibe mensagem de erro
            showErrorDialog(context,
                'Documento do usuário não encontrado, aguarde e tente novamente mais tarde!.', 'Atenção');
          }
        }
      } catch (e) {
        showErrorDialog(context, 'Erro ao carregar os dados: $e', 'Erro');
      }
    } else {
      showErrorDialog(context, 'Você não está autenticado.', 'Atenção');
    }
  }

  void _navigateTo(BuildContext context, String routeName) {
    final isAdminPanel = routeName == '/admin';

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            _getPageByRouteName(routeName),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (isAdminPanel) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          } else {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;

            var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);

            return SlideTransition(
              position: offsetAnimation,
              child: child,
            );
          }
        },
      ),
    );
  }

  Widget _getPageByRouteName(String routeName) {
    switch (routeName) {
      case '/dashboard':
        return DashboardPage();
      case '/leads':
        return LeadsPage();
      case '/admin':
        return AdminPanelPage();
      default:
        return CustomTabBarPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<appAuthProvider.AuthProvider>(context);

    return ConnectivityBanner(
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Overview Cards
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatCard('Resultado', '350,809', Icons.trending_up_outlined,
                          Theme.of(context).colorScheme.primary),
                      _buildStatCard('Alcance', '186,072', Icons.bar_chart,
                          Theme.of(context).colorScheme.primary),
                      _buildStatCard('Total Gasto', '120,043', Icons.monetization_on,
                          Theme.of(context).colorScheme.primary),
                      _buildStatCard('Engajamento', '48.07%', Icons.show_chart,
                          Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                // Audience Age & Gender - Bar Chart
                Text(
                  'Exemplo de Gráfico 1',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Center(
                  child: AspectRatio(
                    aspectRatio: 1.7,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: 100,
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                const style = TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                );
                                switch (value.toInt()) {
                                  case 0:
                                    return Text('15-24', style: style);
                                  case 1:
                                    return Text('25-34', style: style);
                                  case 2:
                                    return Text('35-44', style: style);
                                  case 3:
                                    return Text('45-54', style: style);
                                  case 4:
                                    return Text('55-64', style: style);
                                  case 5:
                                    return Text('65+', style: style);
                                  default:
                                    return Text('', style: style);
                                }
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: false,
                        ),
                        barGroups: [
                          for (int i = 0; i < 6; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: (i + 1) * 10.0,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                // Follower Interest Radar Chart
                Text(
                  'Exemplo de Gráfico 2',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Center(
                  child: Container(
                    height: 300,
                    child: RadarChart(
                      RadarChartData(
                        dataSets: [
                          RadarDataSet(
                            dataEntries: [
                              RadarEntry(value: 5),
                              RadarEntry(value: 3),
                              RadarEntry(value: 7),
                              RadarEntry(value: 2),
                              RadarEntry(value: 6),
                            ],
                            fillColor: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                          ),
                          RadarDataSet(
                            dataEntries: [
                              RadarEntry(value: 4),
                              RadarEntry(value: 5),
                              RadarEntry(value: 2),
                              RadarEntry(value: 8),
                              RadarEntry(value: 3),
                            ],
                            fillColor: Theme.of(context).colorScheme.onBackground.withOpacity(0.4),
                          ),
                        ],
                        radarBorderData: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                // Syncfusion Pie Chart
                Text(
                  'Exemplo de Gráfico 3 - Syncfusion Pie Chart',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Center(
                  child: Container(
                    height: 300,
                    child: SfCircularChart(
                      legend: Legend(isVisible: true),
                      series: <CircularSeries>[
                        PieSeries<ChartData, String>(
                          dataSource: [
                            ChartData('A', 35),
                            ChartData('B', 28),
                            ChartData('C', 34),
                            ChartData('D', 52),
                          ],
                          xValueMapper: (ChartData data, _) => data.x,
                          yValueMapper: (ChartData data, _) => data.y,
                          dataLabelSettings: DataLabelSettings(isVisible: true),
                        )
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                // Syncfusion Line Chart
                Text(
                  'Exemplo de Gráfico 4 - Syncfusion Line Chart',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Center(
                  child: Container(
                    height: 300,
                    child: SfCartesianChart(
                      primaryXAxis: CategoryAxis(),
                      series: <CartesianSeries<dynamic, dynamic>>[
                        LineSeries<ChartData, String>(
                          dataSource: [
                            ChartData('Jan', 35),
                            ChartData('Feb', 28),
                            ChartData('Mar', 34),
                            ChartData('Apr', 52),
                            ChartData('Mai', 56),
                            ChartData('Jun', 23),
                            ChartData('Jul', 78),
                            ChartData('Aug', 20),
                            ChartData('Sep', 90),
                            ChartData('Oct', 13),
                            ChartData('Nov', 87),
                            ChartData('Dec', 44),
                          ],
                          xValueMapper: (ChartData data, _) => data.x,
                          yValueMapper: (ChartData data, _) => data.y,
                          dataLabelSettings: DataLabelSettings(isVisible: true),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String count, IconData icon, Color color) {
    return Card(
      color: Theme.of(context).colorScheme.secondary,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                SizedBox(width: 10),
                Text(
                  count,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Theme.of(context).colorScheme.onSecondary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartData {
  ChartData(this.x, this.y);
  final String x;
  final double y;
}
