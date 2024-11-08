import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:app_io/auth/providers/auth_provider.dart' as authProviderApp;
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/home/home_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:provider/provider.dart';

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
      pages.insert(1, DashboardPage());
      tabs.insert(
          1,
          Tab(
            icon: Icon(Icons.dashboard),
            text: 'Dashboard',
          ));
    }

    if (hasLeadsAccess) {
      pages.add(LeadsPage());
      tabs.add(Tab(
        icon: Icon(Icons.supervisor_account),
        text: 'Leads',
      ));
    }

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
        return 'Dashboard';
      case 2:
        return 'Leads';
      default:
        return 'IO Connect';
    }
  }

  void _showLogoutConfirmationDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme
              .of(context)
              .primaryColor,
          width: 2,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
      ),
      backgroundColor: Theme
          .of(context)
          .colorScheme
          .background,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirmar Logout',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Theme
                      .of(context)
                      .colorScheme
                      .onSecondary,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Tem certeza que deseja sair?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme
                      .of(context)
                      .colorScheme
                      .onSecondary,
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Theme
                            .of(context)
                            .colorScheme
                            .onSecondary,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () async {
                      final authProvider =
                      Provider.of<authProviderApp.AuthProvider>(context,
                          listen: false);
                      await authProvider.signOut();
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    child: Text(
                      'Sair',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Theme
                            .of(context)
                            .colorScheme
                            .outline,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme
                          .of(context)
                          .colorScheme
                          .primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _getPrefix() {
    switch (_currentIndex) {
      case 1:
        return "Bem-vindo(a) às"; // Página de Campanhas
      case 2:
        return "Bem-vindo(a) aos"; // Página de Leads
      default:
        return "Bem-vindo(a) ao"; // Padrão para outras páginas
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .background,
        appBar: AppBar(
          toolbarHeight: 100,
          // Aumenta a altura da AppBar
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getPrefix(), // Utiliza o prefixo com base na página
                    style: TextStyle(
                      fontFamily: 'BrandingSF',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Theme
                          .of(context)
                          .colorScheme
                          .onSecondary,
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
                        color: Theme
                            .of(context)
                            .colorScheme
                            .onSurface,
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
                    color: Theme
                        .of(context)
                        .colorScheme
                        .onSurface,
                    onPressed: () async {},
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: Colors.purple,
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
          backgroundColor: Theme
              .of(context)
              .colorScheme
              .secondary,
          foregroundColor: Theme
              .of(context)
              .colorScheme
              .outline,
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
          labelColor: Theme
              .of(context)
              .colorScheme
              .primary,
          unselectedLabelColor: Theme
              .of(context)
              .colorScheme
              .onSecondary,
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