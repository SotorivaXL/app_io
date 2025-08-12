import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_io/features/screens/configurations/configurations.dart';
import 'package:app_io/features/screens/reports/reports_page.dart';
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
import 'package:app_io/features/screens/crm/whatsapp_chats.dart';
import 'package:app_io/features/screens/indicators/dash_principal_reports.dart';

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

// ====== MÓDULOS NA TABBAR (visibilidade das páginas) ======
  bool canChats       = true;   // acesso ao módulo "Chats"
  bool canIndicators  = true;   // acesso ao módulo "Indicadores"
  bool canAdminPanel  = false;  // acesso ao módulo "Painel"
  bool canConfig      = true;   // acesso à "Config." (recomendado manter true)
  bool canReports     = false;  // (opcional) módulo "Relatórios"

// ====== Permissões granulares DENTRO do Painel (mantidas) ======
  bool canGerenciarParceiros      = false;
  bool canGerenciarColaboradores  = false;
  bool canConfigurarDash          = false;
  bool canCriarForm               = false;
  bool canCriarCampanha           = false;

  // Controle para expandir/recolher a barra lateral no desktop
  bool _isSidebarExpanded = true;

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

  int getPageIndexByType(Type pageType) {
    return _pages.indexWhere((page) => page.runtimeType == pageType);
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
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    debugPrint('Dados do usuário (perms): $data');

    // 1) Lê permissões de MÓDULOS (defaults pensados p/ não quebrar nada)
    final bool newCanChats      = (data['modChats'] ?? true) as bool;
    final bool newCanIndicators = (data['modIndicadores'] ?? true) as bool;
    final bool newCanAdminPanel = (data['modPainel'] ?? false) as bool;
    final bool newCanConfig     = (data['modConfig'] ?? true) as bool;
    final bool newCanReports    = (data['modRelatorios'] ?? false) as bool; // opcional

    // 2) Lê permissões granulares do Painel (já existiam)
    final bool newParceiros     = (data['gerenciarParceiros'] ?? false) as bool;
    final bool newColabs        = (data['gerenciarColaboradores'] ?? false) as bool;
    final bool newConfigDash    = (data['configurarDash'] ?? false) as bool;
    final bool newCriarForm     = (data['criarForm'] ?? false) as bool;
    final bool newCriarCamp     = (data['criarCampanha'] ?? false) as bool;

    // 3) Se nada mudou, não refaz UI
    final nothingChanged =
        canChats == newCanChats &&
            canIndicators == newCanIndicators &&
            canAdminPanel == newCanAdminPanel &&
            canConfig == newCanConfig &&
            canReports == newCanReports &&
            canGerenciarParceiros == newParceiros &&
            canGerenciarColaboradores == newColabs &&
            canConfigurarDash == newConfigDash &&
            canCriarForm == newCriarForm &&
            canCriarCampanha == newCriarCamp;

    if (nothingChanged) return;

    // 4) Monta as páginas NA ORDEM padronizada
    final pages = <Widget>[];
    if (newCanChats)      pages.add(const WhatsAppChats());
    if (newCanIndicators) pages.add(const IndicatorsPage());
    if (newCanAdminPanel) pages.add(AdminPanelPage());
    if (newCanReports)    pages.add(ReportsPage()); // opcional
    if (newCanConfig)     pages.add(SettingsPage());

    setState(() {
      canChats      = newCanChats;
      canIndicators = newCanIndicators;
      canAdminPanel = newCanAdminPanel;
      canConfig     = newCanConfig;
      canReports    = newCanReports;

      canGerenciarParceiros     = newParceiros;
      canGerenciarColaboradores = newColabs;
      canConfigurarDash         = newConfigDash;
      canCriarForm              = newCriarForm;
      canCriarCampanha          = newCriarCamp;

      _pages = pages;

      if (_pages.isEmpty) {
        // Evita PageView sem páginas
        _pages = [SettingsPage()];
      }

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
    if (_currentIndex >= _pages.length) return 'IO Connect';
    final p = _pages[_currentIndex];
    if (p is WhatsAppChats)   return 'Chat';
    if (p is IndicatorsPage)  return 'Indicadores';
    if (p is AdminPanelPage)  return 'Painel Administrativo';
    if (p is ReportsPage)     return 'Relatórios';
    if (p is SettingsPage)    return 'Configurações';
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
    final bool isDesktop = MediaQuery.of(context).size.width > 1024;

    // 1) Monte os itens UMA vez
    final bottomItems = _buildBottomNavyBarItems();
    final bool showBottomBar = !isDesktop && bottomItems.length >= 2 && bottomItems.length <= 5;

    return ConnectivityBanner(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: isDesktop
            ? null // Remove o AppBar no desktop
            : PreferredSize(
          preferredSize: Size.fromHeight(
              (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0)),
          child: Opacity(
            opacity: (1.0 - (_scrollOffset / 40)).clamp(0.0, 1.0),
            child: AppBar(
              toolbarHeight:
              (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0),
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
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondary,
                        ),
                      ),
                      Text(
                        _getTitle(),
                        key: ValueKey<String>(_getTitle()),
                        style: TextStyle(
                          fontFamily: 'BrandingSF',
                          fontWeight: FontWeight.w700,
                          fontSize: 30,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              centerTitle: false,
              automaticallyImplyLeading: false,
              backgroundColor:
              Theme.of(context).colorScheme.secondary,
              foregroundColor:
              Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        body: Row(
          children: [
            if (isDesktop) _buildDesktopSidebar(),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) => false,
                child: _pages.isEmpty
                // 2) Evita PageView sem páginas antes das permissões chegarem
                    ? const Center(child: CircularProgressIndicator())
                    : PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    if (mounted) setState(() => _currentIndex = index);
                  },
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: _pages,
                ),
              ),
            ),
          ],
        ),

        // 3) Só mostra a bottom bar se houver 2–5 itens
        bottomNavigationBar: showBottomBar
            ? SafeArea(
          child: Opacity(
            opacity: (1.0 - (_scrollOffset / 40)).clamp(0.0, 1.0),
            child: BottomNavyBar(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              showInactiveTitle: false,
              selectedIndex: _currentIndex.clamp(0, bottomItems.length - 1),
              showElevation: true,
              itemCornerRadius: 24,
              iconSize: 25,
              curve: Curves.easeIn,
              onItemSelected: (index) {
                if (!mounted) return;
                setState(() => _currentIndex = index);
                _pageController.jumpToPage(index);
              },
              items: bottomItems, // <- usa a lista já calculada
            ),
          ),
        )
            : null,
      ),
    );
  }

  // Barra lateral para desktop
  Widget _buildDesktopSidebar() {
    return Container(
      padding: _isSidebarExpanded
          ? EdgeInsets.only(left: 15)
          : EdgeInsets.zero, // Padding condicional
      width: _isSidebarExpanded ? 300 : 80, // Largura da barra lateral
      color: Theme.of(context).colorScheme.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // Garante que os itens ocupem toda a largura
        children: [
          // Botão para expandir/recolher a barra lateral
          IconButton(
            icon: Icon(
              _isSidebarExpanded ? Icons.chevron_left : Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
            onPressed: () {
              setState(() {
                _isSidebarExpanded = !_isSidebarExpanded;
              });
            },
          ),
          // Espaçamento entre o botão e os ícones
          SizedBox(height: 20),
          // Ícones e nomes das páginas
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // Garante que os itens ocupem toda a largura
              children: _buildDesktopSidebarItems(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDesktopSidebarItems() {
    List<Widget> items = [];

    Widget buildSidebarItem(IconData icon, String title, Type pageType) {
      final bool isSelected =
          _pages.isNotEmpty && _pages[_currentIndex].runtimeType == pageType;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Tooltip(
          message: title,
          child: InkWell(
            onTap: () {
              final pageIndex = getPageIndexByType(pageType);
              if (pageIndex != -1) {
                setState(() {
                  _currentIndex = pageIndex;
                  _pageController.jumpToPage(pageIndex);
                });
              } else {
                debugPrint('Página do tipo $pageType não encontrada.');
              }
            },
            child: Container(
              decoration: isSelected
                  ? BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              )
                  : null,
              padding: _isSidebarExpanded
                  ? const EdgeInsets.symmetric(horizontal: 15, vertical: 20)
                  : const EdgeInsets.symmetric(horizontal: 0,  vertical: 20),
              margin: _isSidebarExpanded
                  ? const EdgeInsets.only(right: 16)
                  : const EdgeInsets.only(right: 8, left: 8),
              child: Row(
                mainAxisAlignment:
                _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSecondary,
                    size: 32,
                  ),
                  if (_isSidebarExpanded)
                    Padding(
                      padding: const EdgeInsets.only(left: 15),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSecondary,
                          fontSize: 17,
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

    // Gera itens na MESMA ordem de _pages
    for (final page in _pages) {
      if (page is WhatsAppChats) {
        items.add(buildSidebarItem(Icons.chat, 'Chat', WhatsAppChats));
      } else if (page is IndicatorsPage) {
        items.add(buildSidebarItem(Icons.bar_chart, 'Indicadores', IndicatorsPage));
      } else if (page is AdminPanelPage) {
        items.add(buildSidebarItem(Icons.admin_panel_settings, 'Painel Adm', AdminPanelPage));
      } else if (page is ReportsPage) {
        items.add(buildSidebarItem(Icons.edit_document, 'Relatórios', ReportsPage));
      } else if (page is SettingsPage) {
        items.add(buildSidebarItem(Icons.settings, 'Configurações', SettingsPage));
      }
    }

    return items;
  }

  List<BottomNavyBarItem> _buildBottomNavyBarItems() {
    final cs = Theme.of(context).colorScheme;

    BottomNavyBarItem makeItem(IconData icon, String label) => BottomNavyBarItem(
      icon         : Icon(icon),
      title        : Text(label),
      inactiveColor: cs.onSecondary,
      activeColor  : cs.tertiary,
    );

    final items = <BottomNavyBarItem>[];

    // Mesma ordem de _pages
    for (final page in _pages) {
      if (page is WhatsAppChats) {
        items.add(makeItem(Icons.chat, 'Chat'));
      } else if (page is IndicatorsPage) {
        items.add(makeItem(Icons.bar_chart, 'Indicadores'));
      } else if (page is AdminPanelPage) {
        items.add(makeItem(Icons.admin_panel_settings, 'Painel Adm'));
      } else if (page is ReportsPage) {
        items.add(makeItem(Icons.edit_document, 'Relatórios'));
      } else if (page is SettingsPage) {
        items.add(makeItem(Icons.settings, 'Config.'));
      }
    }
    return items;
  }
}