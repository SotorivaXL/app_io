import 'dart:io';
import 'package:app_io/features/screens/configurations/configurations.dart';
import 'package:app_io/features/screens/dasboard/dashboard_page.dart';
import 'package:app_io/features/screens/leads/leads_page.dart';
import 'package:app_io/features/screens/panel/painel_adm.dart';
import 'package:app_io/util/CustomWidgets/BirthdayAnimationPopup/birthday_animation_popup.dart';
import 'package:app_io/util/CustomWidgets/ConnectivityBanner/connectivity_banner.dart';
import 'package:app_io/util/CustomWidgets/TutorialPopup/tutorial_popup.dart';
import 'package:bottom_navy_bar/bottom_navy_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomTabBarPage extends StatefulWidget {
  @override
  _CustomTabBarPageState createState() => _CustomTabBarPageState();
}

class _CustomTabBarPageState extends State<CustomTabBarPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  double _scrollOffset = 0.0;

  List<Widget> _pages = [];
  int _currentIndex = 0;

  bool hasLeadsAccess = false;
  bool hasDashboardAccess = false;
  bool hasGerenciarParceirosAccess = false;
  bool hasGerenciarColaboradoresAccess = false;
  bool hasConfigurarDashAccess = false;
  bool hasCriarFormAccess = false;
  bool hasCriarCampanhaAccess = false;
  bool hasAdmPanelAccess = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _checkBirthday();
    _listenToPermissionsChanges();
    _showTutorialIfFirstTime();
  }

  Future<void> _showTutorialIfFirstTime() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool tutorialShown = prefs.getBool('tutorial_shown') ?? false;

    if (!tutorialShown) {
      WidgetsBinding.instance.addPostFrameCallback(
            (_) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return TutorialPopup(
                onComplete: () async {
                  await prefs.setBool('tutorial_shown', true);
                  Navigator.of(context).pop();
                },
              );
            },
          );
        },
      );
    }
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

  void updateAdmPanelAccess() {
    hasAdmPanelAccess = hasGerenciarParceirosAccess ||
        hasGerenciarColaboradoresAccess ||
        hasConfigurarDashAccess ||
        hasCriarFormAccess ||
        hasCriarCampanhaAccess;
  }

  void _updatePermissions(DocumentSnapshot doc) {
    var userData = doc.data() as Map<String, dynamic>;
    print('Dados do usuário: $userData');

    bool newHasLeadsAccess = userData['leads'] ?? false;
    bool newHasDashboardAccess = userData['dashboard'] ?? false;
    bool newHasConfigurarDashAccess = userData['configurarDash'] ?? false;
    bool newHasCriarCampanhaAccess = userData['criarCampanha'] ?? false;
    bool newHasCriarFormAccess = userData['criarForm'] ?? false;
    bool newHasGerenciarColaboradoresAccess =
        userData['gerenciarColaboradores'] ?? false;
    bool newHasGerenciarParceirosAccess =
        userData['gerenciarParceiros'] ?? false;

    bool newHasAdmPanelAccess = newHasGerenciarParceirosAccess ||
        newHasGerenciarColaboradoresAccess ||
        newHasConfigurarDashAccess ||
        newHasCriarFormAccess ||
        newHasCriarCampanhaAccess;

    List<Widget> newPages = [];

    if (newHasDashboardAccess) {
      newPages.add(DashboardPage());
    }

    if (newHasLeadsAccess) {
      newPages.add(LeadsPage());
    }

    if (newHasAdmPanelAccess) {
      newPages.add(AdminPanelPage());
    }

    newPages.add(SettingsPage());

    setState(() {
      hasLeadsAccess = newHasLeadsAccess;
      hasDashboardAccess = newHasDashboardAccess;
      hasConfigurarDashAccess = newHasConfigurarDashAccess;
      hasCriarCampanhaAccess = newHasCriarCampanhaAccess;
      hasCriarFormAccess = newHasCriarFormAccess;
      hasGerenciarColaboradoresAccess = newHasGerenciarColaboradoresAccess;
      hasGerenciarParceirosAccess = newHasGerenciarParceirosAccess;
      hasAdmPanelAccess = newHasAdmPanelAccess;

      _pages = newPages;

      if (_currentIndex >= _pages.length) {
        _currentIndex = _pages.length - 1;
        _pageController.jumpToPage(_currentIndex);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getTitle() {
    if (_currentIndex < _pages.length) {
      if (_pages[_currentIndex] is AdminPanelPage) {
        return 'Painel Administrativo';
      } else if (_pages[_currentIndex] is DashboardPage) {
        return 'Início';
      } else if (_pages[_currentIndex] is LeadsPage) {
        return 'Leads';
      } else if (_pages[_currentIndex] is SettingsPage) {
        return 'Configurações';
      }
    }
    return 'IO Connect';
  }

  String _getPrefix() {
    if (_currentIndex < _pages.length) {
      if (_pages[_currentIndex] is SettingsPage) {
        return "Bem-vindo(a) às";
      } else {
        return "Bem-vindo(a) ao";
      }
    }
    return "Bem-vindo(a) ao";
  }

  void _showNotificationsSidebar(BuildContext context) {
    // Notificações omitidas por brevidade
  }

  Future<void> _checkBirthday() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    String? birthday;

    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (userDoc.exists) {
      birthday = userDoc.data()?['birth'];
    } else {
      final empresaDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(uid)
          .get();
      if (empresaDoc.exists) {
        birthday = empresaDoc.data()?['founded'];
      }
    }

    if (birthday != null) {
      final today = DateTime.now();
      final birthdayParts = birthday.split('-');
      if (birthdayParts.length == 3) {
        final birthDay = int.parse(birthdayParts[0]);
        final birthMonth = int.parse(birthdayParts[1]);

        if (birthDay == today.day && birthMonth == today.month) {
          final prefs = await SharedPreferences.getInstance();
          final key =
              'birthday_shown_$uid${today.toIso8601String()}';

          final shownToday = prefs.getBool(key) ?? false;

          if (!shownToday) {
            _showBirthdayPopup();
            await prefs.setBool(key, true);
          }
        }
      }
    }
  }

  void _showBirthdayPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return BirthdayAnimationPopup(
          onDismiss: () => Navigator.of(context).pop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double tabBarHeight = Platform.isIOS
        ? (111 - (_scrollOffset / 2)).clamp(0.0, 111).ceilToDouble()
        : (79 - (_scrollOffset / 2)).clamp(0.0, 79).ceilToDouble();
    double opacity = (1.0 - (_scrollOffset / 40)).clamp(0.0, 1.0);

    final pageViewPhysics = (appBarHeight > 0 && tabBarHeight > 0)
        ? AlwaysScrollableScrollPhysics()
        : NeverScrollableScrollPhysics();

    return ConnectivityBanner(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(appBarHeight),
          child: Opacity(
            opacity: opacity,
            child: AppBar(
              toolbarHeight: appBarHeight,
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
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                      Text(
                        _getTitle(),
                        key: ValueKey<String>(_getTitle()),
                        style: TextStyle(
                          fontFamily: 'BrandingSF',
                          fontWeight: FontWeight.w700,
                          fontSize: 30,
                          color: Theme.of(context).colorScheme.surfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  // Ícone de notificações omitido
                ],
              ),
              centerTitle: false,
              automaticallyImplyLeading: false,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            // Removendo completamente o setState ou postFrameCallback aqui
            // para não chamar setState durante o layout.
            // Assim, o erro será evitado e o PageView continuará navegável por arraste.
            return false; // Apenas retornamos false para não interromper a notificação
          },
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              if (mounted) {
                setState(() {
                  _currentIndex = index;
                });
              }
            },
            physics: pageViewPhysics,
            children: _pages,
          ),
        ),
        bottomNavigationBar: SizedBox(
          height: tabBarHeight,
          child: Opacity(
            opacity: opacity,
            child: BottomNavyBar(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              showInactiveTitle: false,
              selectedIndex: _currentIndex,
              showElevation: true,
              itemCornerRadius: 24,
              iconSize: 25,
              curve: Curves.easeIn,
              onItemSelected: (index) {
                if (mounted) {
                  setState(() {
                    _currentIndex = index;
                  });
                  _pageController.jumpToPage(index);
                }
              },
              items: _buildBottomNavyBarItems(),
            ),
          ),
        ),
      ),
    );
  }

  List<BottomNavyBarItem> _buildBottomNavyBarItems() {
    List<BottomNavyBarItem> items = [];

    if (hasDashboardAccess) {
      items.add(
        BottomNavyBarItem(
          icon: Icon(Icons.dashboard),
          title: Text('Início'),
          inactiveColor: Theme.of(context).colorScheme.onSecondary,
          activeColor: Theme.of(context).colorScheme.tertiary,
          textAlign: TextAlign.center,
        ),
      );
    }

    if (hasLeadsAccess) {
      items.add(
        BottomNavyBarItem(
          icon: Icon(Icons.people),
          title: Text('Leads'),
          inactiveColor: Theme.of(context).colorScheme.onSecondary,
          activeColor: Theme.of(context).colorScheme.tertiary,
          textAlign: TextAlign.center,
        ),
      );
    }

    if (hasAdmPanelAccess) {
      items.add(
        BottomNavyBarItem(
          icon: Icon(Icons.admin_panel_settings),
          title: Text('Painel Adm'),
          inactiveColor: Theme.of(context).colorScheme.onSecondary,
          activeColor: Theme.of(context).colorScheme.tertiary,
          textAlign: TextAlign.center,
        ),
      );
    }

    items.add(
      BottomNavyBarItem(
        icon: Icon(Icons.settings),
        title: Text('Config.'),
        inactiveColor: Theme.of(context).colorScheme.onSecondary,
        activeColor: Theme.of(context).colorScheme.tertiary,
        textAlign: TextAlign.center,
      ),
    );

    return items;
  }
}
