import 'package:app_io/features/screens/configurations/configurations.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as authProviderApp;
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/home/home_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:provider/provider.dart';
import 'package:modal_side_sheet/modal_side_sheet.dart';

class CustomTabBarPage extends StatefulWidget {
  @override
  _CustomTabBarPageState createState() => _CustomTabBarPageState();
}

class _CustomTabBarPageState extends State<CustomTabBarPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  List<Widget> _pages = [];
  List<Tab> _tabs = [];
  int _currentIndex = 0;

  bool hasLeadsAccess = false;
  bool hasDashboardAccess = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _tabController = TabController(length: 0, vsync: this);

    // Escuta as alterações no Firestore em tempo real
    _listenToPermissionsChanges();
  }

  void _listenToPermissionsChanges() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('Usuário não está autenticado');
      return;
    }
    String userUid = user.uid;

    FirebaseFirestore.instance
        .collection('users')
        .doc(userUid)
        .snapshots()
        .listen((userDoc) {
      if (userDoc.exists) {
        print('Documento encontrado na coleção users');
        _updatePermissions(userDoc);
      } else {
        FirebaseFirestore.instance
            .collection('empresas')
            .doc(userUid)
            .snapshots()
            .listen((empresaDoc) {
          if (empresaDoc.exists) {
            print('Documento encontrado na coleção empresas');
            _updatePermissions(empresaDoc);
          } else {
            print('Documento não encontrado em users nem em empresas');
          }
        });
      }
    });
  }

  void _updatePermissions(DocumentSnapshot doc) {
    var userData = doc.data() as Map<String, dynamic>;
    print('Dados do usuário: $userData');
    setState(() {
      hasLeadsAccess = userData['leads'] ?? false;
      hasDashboardAccess = userData['dashboard'] ?? false;
      _updatePagesAndTabs();
    });
  }

  void _updatePagesAndTabs() {
    List<Widget> pages = [HomePage()];
    List<Tab> tabs = [
      Tab(
        icon: Icon(Icons.home),
        text: 'Home',
      ),
    ];

    if (hasDashboardAccess) {
      pages.add(DashboardPage());
      tabs.add(
        Tab(
          icon: Icon(Icons.dashboard),
          text: 'Dashboard',
        ),
      );
    }

    if (hasLeadsAccess) {
      pages.add(LeadsPage());
      tabs.add(
        Tab(
          icon: Icon(Icons.supervisor_account),
          text: 'Leads',
        ),
      );
    }

    // Adiciona a página de configurações sempre como a última
    pages.add(SettingsPage());
    tabs.add(
      Tab(
        icon: Icon(Icons.settings),
        text: 'Config.',
      ),
    );

    _pages = pages;
    _tabs = tabs;

    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
          _pageController.jumpToPage(_currentIndex);
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String _getTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Início';
      case 1:
        return hasDashboardAccess ? 'Dashboard' : hasLeadsAccess ? 'Leads' : 'Configurações';
      case 2:
        return hasDashboardAccess && hasLeadsAccess ? 'Leads' : 'Configurações';
      case 3:
        return 'Configurações';
      default:
        return 'IO Connect';
    }
  }

  String _getPrefix() {
    switch (_currentIndex) {
      case 1:
        return hasDashboardAccess ? "Bem-vindo(a) ao" : "Bem-vindo(a) aos";
      case 2:
        return hasDashboardAccess && hasLeadsAccess ? "Bem-vindo(a) aos" : "Bem-vindo(a) às";
      case 3:
        return "Bem-vindo(a) às";
      default:
        return "Bem-vindo(a) ao";
    }
  }

  void _showNotificationsSidebar(BuildContext context) {
    List<Map<String, String>> notifications = [
      {'title': 'Exemplo de notificação 1', 'description': 'Descrição da notificação 1'},
      {'title': 'Exemplo de notificação 2', 'description': 'Descrição da notificação 2'},
      // Adicione mais notificações conforme necessário
    ];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54, // Cor do fundo ao abrir o modal
      transitionDuration: Duration(milliseconds: 300), // Duração da animação
      pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Align(
              alignment: Alignment.centerRight, // Alinha o modal à direita da tela
              child: Dismissible(
                key: Key('notificationSidebar'), // Chave única para o Dismissible
                direction: DismissDirection.startToEnd, // Permite deslizar para fechar da direita para esquerda
                onDismissed: (direction) {
                  Navigator.of(context).pop(); // Fecha o modal ao arrastar para o lado
                },
                child: Material(
                  color: Colors.transparent, // Deixa o fundo transparente
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.height,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.background,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(25.0),
                        bottomLeft: Radius.circular(25.0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.shadow,
                          offset: Offset(-4, 0), // Sombra para a esquerda
                          blurRadius: 10.0,
                        ),
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(30, 50, 30, 50),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notificações',
                          style: TextStyle(
                            fontFamily: 'BrandingSF',
                            fontWeight: FontWeight.w700,
                            fontSize: 30,
                            color: Theme.of(context).colorScheme.onBackground,
                          ),
                        ),
                        SizedBox(height: 10),
                        Expanded(
                          child: ListView.builder(
                            itemCount: notifications.length,
                            itemBuilder: (context, index) {
                              final notification = notifications[index];
                              return Dismissible(
                                key: Key(notification['title']!),
                                direction: DismissDirection.startToEnd,
                                background: Container(
                                  child: Icon(
                                    Icons.delete,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  alignment: Alignment.centerLeft,
                                ),
                                onDismissed: (direction) {
                                  setState(() {
                                    notifications.removeAt(index); // Remove a notificação da lista
                                  });
                                },
                                child: ListTile(
                                  contentPadding: EdgeInsets.symmetric(vertical: 2),
                                  tileColor: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  leading: Icon(Icons.notifications, color: Theme.of(context).colorScheme.primary),
                                  title: Text(
                                    notification['title']!,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 16,
                                      color: Theme.of(context).colorScheme.onSecondary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    notification['description']!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSecondary.withOpacity(0.6),
                                    ),
                                  ),
                                  onTap: () {
                                    // Ação ao clicar na notificação
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final offsetAnimation = Tween<Offset>(
          begin: Offset(1.0, 0.0), // Começa fora da tela à direita
          end: Offset.zero,
        ).animate(animation);

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.secondary,
        appBar: AppBar(
          toolbarHeight: 100, // Aumenta a altura da AppBar
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getPrefix(),
                    style: TextStyle(
                      fontFamily: 'BrandingSF',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onBackground,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 300),
                    child: Text(
                      _getTitle(),
                      key: ValueKey<String>(_getTitle()),
                      style: TextStyle(
                        fontFamily: 'BrandingSF',
                        fontWeight: FontWeight.w700,
                        fontSize: 35,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                      ),
                    ),
                    transitionBuilder: (Widget child,
                        Animation<double> animation) {
                      final fadeInAnimation = Tween<double>(
                          begin: 0.0, end: 1.0).animate(animation);
                      final slideAnimation = Tween<Offset>(begin: Offset(1, 0),
                          end: Offset.zero).animate(animation);

                      return SlideTransition(
                        position: slideAnimation,
                        child: FadeTransition(
                          opacity: fadeInAnimation,
                          child: child,
                        ),
                      );
                    },
                  ),
                ],
              ),
              Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications),
                    color: Theme.of(context).colorScheme.onSecondary,
                    iconSize: 30,
                    onPressed: () async {
                      _showNotificationsSidebar(context);
                    },
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                      child: Text(
                        '3',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          centerTitle: false,
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Theme.of(context).colorScheme.outline,
        ),
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
              _tabController.index = index;
            });
          },
          children: _pages,
        ),
        bottomNavigationBar: _tabs.isNotEmpty
            ? TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.tertiary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSecondary,
          indicator: BoxDecoration(),
          onTap: (index) {
            _pageController.animateToPage(
              index,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          tabs: _tabs,
        )
            : null,
      ),
    );
  }
}
