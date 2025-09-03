import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:responsive_navigation_bar/responsive_navigation_bar.dart';

class TabSpec {
  final String label;
  final IconData icon;
  final Widget page;
  final Type pageType;

  const TabSpec({
    required this.label,
    required this.icon,
    required this.page,
    required this.pageType,
  });
}

enum NavStyle { navy, flutterBricks }

class CustomTabBarPage extends StatefulWidget {
  @override
  _CustomTabBarPageState createState() => _CustomTabBarPageState();
}

class _CustomTabBarPageState extends State<CustomTabBarPage>
    with TickerProviderStateMixin {
  late PageController _pageController;
  double _scrollOffset = 0.0;
  static const _kTabDur = Duration(milliseconds: 800);
  static const _kTabCurve = Curves.easeOutExpo;

  /// Agora usamos _tabs como fonte única de verdade para páginas/labels/ícones
  List<TabSpec> _tabs = [];
  int _currentIndex = 0;

  // ====== MÓDULOS NA TABBAR (visibilidade das páginas) ======
  bool canChats = true;
  bool canIndicators = true;
  bool canAdminPanel = false;
  bool canConfig = true;
  bool canReports = false;

  // ====== Permissões granulares DENTRO do Painel ======
  bool canGerenciarParceiros = false;
  bool canGerenciarColaboradores = false;
  bool canConfigurarDash = false;
  bool canCriarForm = false;
  bool canCriarCampanha = false;

  // Controle para expandir/recolher a barra lateral no desktop
  bool _isSidebarExpanded = true;

  // Estilo de navegação atual (trocaremos para flutterBricks quando você enviar o exemplo)
  NavStyle _navStyle = NavStyle.flutterBricks;

  bool _initialPageSet = false; // garante que só setamos o inicial uma vez

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _checkBirthday();
    _listenToPermissionsChanges();
    _showTutorialIfFirstTime();
  }

  void _ensureInitialOnChat(List<TabSpec> tabs) {
    if (_initialPageSet) return;

    final chatIdx = tabs.indexWhere((t) => t.pageType == WhatsAppChats);
    final targetIndex = chatIdx >= 0 ? chatIdx : 0;

    // recria o controller já na página desejada
    _pageController.dispose();
    _pageController = PageController(initialPage: targetIndex);

    _currentIndex = targetIndex;
    _initialPageSet = true;
  }

  Future<void> _showTutorialIfFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    final tutorialShown = prefs.getBool('tutorial_shown') ?? false;

    if (!tutorialShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return TutorialPopup(
              onComplete: () async {
                await prefs.setBool('tutorial_shown', true);
                if (mounted) Navigator.of(context).pop();
              },
            );
          },
        );
      });
    }
  }

  void _listenToPermissionsChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('Usuário não está autenticado');
      return;
    }
    final userUid = user.uid;

    FirebaseFirestore.instance
        .collection('users')
        .doc(userUid)
        .snapshots()
        .listen((userDoc) {
      if (userDoc.exists) {
        _updatePermissions(userDoc);
      } else {
        FirebaseFirestore.instance
            .collection('empresas')
            .doc(userUid)
            .snapshots()
            .listen((empresaDoc) {
          if (empresaDoc.exists) {
            _updatePermissions(empresaDoc);
          } else {
            debugPrint('Documento não encontrado em users nem em empresas');
          }
        });
      }
    });
  }

  void _updatePermissions(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    debugPrint('Dados do usuário (perms): $data');

    final bool newCanChats = (data['modChats'] ?? true) as bool;
    final bool newCanIndicators = (data['modIndicadores'] ?? true) as bool;
    final bool newCanAdminPanel = (data['modPainel'] ?? false) as bool;
    final bool newCanConfig = (data['modConfig'] ?? true) as bool;
    final bool newCanReports = (data['modRelatorios'] ?? false) as bool;

    final bool newParceiros = (data['gerenciarParceiros'] ?? false) as bool;
    final bool newColabs = (data['gerenciarColaboradores'] ?? false) as bool;
    final bool newConfigDash = (data['configurarDash'] ?? false) as bool;
    final bool newCriarForm = (data['criarForm'] ?? false) as bool;
    final bool newCriarCamp = (data['criarCampanha'] ?? false) as bool;

    final nothingChanged = canChats == newCanChats &&
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

// Monta as abas posicionando "Chats" no MEIO e trocando ícone para casa
    final List<TabSpec> tabs = [];

    // 1) HOME/CHAT — sempre primeiro à esquerda
    if ((data['modChats'] ?? true) as bool) {
      tabs.add(const TabSpec(
        label: 'Chat',
        icon: Icons.home,
        page: WhatsAppChats(),
        pageType: WhatsAppChats,
      ));
    }

    // 2) DEMAIS MÓDULOS (no meio)
    if ((data['modIndicadores'] ?? true) as bool) {
      tabs.add(const TabSpec(
        label: 'Indicadores',
        icon: Icons.bar_chart,
        page: IndicatorsPage(),
        pageType: IndicatorsPage,
      ));
    }
    if ((data['modRelatorios'] ?? false) as bool) {
      tabs.add(const TabSpec(
        label: 'Relatórios',
        icon: Icons.edit_document,
        page: ReportsPage(),
        pageType: ReportsPage,
      ));
    }

    // 3) CONFIGURAÇÕES — sempre por último
    if ((data['modPainel'] ?? false) as bool) {
      tabs.add(TabSpec(
        label: 'Configurações',
        icon: Icons.settings,
        page: AdminPanelPage(),
        pageType: AdminPanelPage,
      ));
    }

    setState(() {
      canChats = newCanChats;
      canIndicators = newCanIndicators;
      canAdminPanel = newCanAdminPanel;
      canConfig = newCanConfig;
      canReports = newCanReports;

      canGerenciarParceiros = newParceiros;
      canGerenciarColaboradores = newColabs;
      canConfigurarDash = newConfigDash;
      canCriarForm = newCriarForm;
      canCriarCampanha = newCriarCamp;

      _tabs = tabs.isEmpty
          ? [
        TabSpec(
          label: 'Configurações',
          icon: Icons.settings,
          page: AdminPanelPage(),
          pageType: AdminPanelPage,
        )
      ]
          : tabs;

      // GARANTE que a PRIMEIRA tela após login é o Chat (agora em index 0)
      _ensureInitialOnChat(_tabs);

      // Proteção se o índice atual saiu do range após mudança de permissões
      if (_currentIndex >= _tabs.length) {
        _currentIndex = _tabs.length - 1;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getTitle() {
    if (_currentIndex >= _tabs.length) return 'IO Connect';
    return _tabs[_currentIndex].label;
  }

  String _getPrefix() {
    if (_currentIndex < _tabs.length &&
        _tabs[_currentIndex].pageType == AdminPanelPage) {
      return "Bem-vindo(a) às";
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
      final parts = birthday.split('-');
      if (parts.length == 3) {
        final birthDay = int.parse(parts[0]);
        final birthMonth = int.parse(parts[1]);

        if (birthDay == today.day && birthMonth == today.month) {
          final prefs = await SharedPreferences.getInstance();
          final key =
              'birthday_shown_${uid}_${today.year}-${today.month}-${today.day}';
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
    final bool showBottomBar =
        !isDesktop && _tabs.length >= 2 && _tabs.length <= 5;

    return ConnectivityBanner(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        appBar: isDesktop
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(
                    (100.0 - (_scrollOffset / 2)).clamp(56.0, 100.0)),
                child: Opacity(
                  opacity: (1.0 - (_scrollOffset / 40)).clamp(0.0, 1.0),
                  child: AppBar(
                    toolbarHeight:
                        (100.0 - (_scrollOffset / 2)).clamp(56.0, 100.0),
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
                                color:
                                    Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: Text(
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
                ),
              ),
        body: Row(
          children: [
            if (isDesktop) _buildDesktopSidebar(),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Opcional: anime o AppBar se a página atual tiver scroll primário
                    if (notification.metrics.axis == Axis.vertical) {
                      setState(() {
                        _scrollOffset = notification.metrics.pixels;
                      });
                    }
                    return false;
                  },
                  child: _tabs.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : PageView(
                          controller: _pageController,
                          onPageChanged: (index) {
                            if (!mounted) return;
                            setState(() => _currentIndex = index);
                          },
                          children: _tabs.map((t) => t.page).toList(),
                        )),
            ),
          ],
        ),
        bottomNavigationBar: showBottomBar
            ? SafeArea(
                child: _buildBottomBar(),
              )
            : null,
      ),
    );
  }

  /// Sidebar desktop usando a mesma fonte de dados (_tabs)
  Widget _buildDesktopSidebar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: _isSidebarExpanded
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.zero,
      width: _isSidebarExpanded ? 300 : 80,
      color: cs.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconButton(
            icon: Icon(
              _isSidebarExpanded ? Icons.chevron_left : Icons.chevron_right,
              color: cs.onSecondary,
            ),
            onPressed: () =>
                setState(() => _isSidebarExpanded = !_isSidebarExpanded),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final bool isSelected = i == _currentIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Tooltip(
                    message: tab.label,
                    child: InkWell(
                      onTap: () {
                        setState(() => _currentIndex = i);
                        _pageController.jumpToPage(i);
                      },
                      child: Container(
                        decoration: isSelected
                            ? BoxDecoration(
                                color: cs.primary,
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(8)),
                              )
                            : null,
                        padding: _isSidebarExpanded
                            ? const EdgeInsets.symmetric(
                                horizontal: 15, vertical: 20)
                            : const EdgeInsets.symmetric(
                                horizontal: 0, vertical: 20),
                        margin: _isSidebarExpanded
                            ? const EdgeInsets.only(right: 16)
                            : const EdgeInsets.only(right: 8, left: 8),
                        child: Row(
                          mainAxisAlignment: _isSidebarExpanded
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          children: [
                            Icon(
                              tab.icon,
                              color: isSelected ? Colors.white : cs.onSecondary,
                              size: 32,
                            ),
                            if (_isSidebarExpanded)
                              Padding(
                                padding: const EdgeInsets.only(left: 15),
                                child: Text(
                                  tab.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : cs.onSecondary,
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
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói a bottom bar de acordo com o estilo escolhido
  Widget _buildBottomBar() {
    switch (_navStyle) {
      case NavStyle.navy:
        return _buildNavyBar();
      case NavStyle.flutterBricks:
        return _buildFlutterBricksBar(); // iremos trocar o miolo após você enviar o exemplo
    }
  }

  /// Mantém seu BottomNavyBar atual (cores puxadas do Theme)
  Widget _buildNavyBar() {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: (1.0 - (_scrollOffset / 40)).clamp(0.0, 1.0),
      child: BottomNavyBar(
        backgroundColor: cs.secondary,
        showInactiveTitle: false,
        selectedIndex: _currentIndex.clamp(0, _tabs.length - 1),
        showElevation: true,
        itemCornerRadius: 24,
        iconSize: 25,
        curve: Curves.easeIn,
        onItemSelected: (index) {
          if (!mounted) return;
          setState(() => _currentIndex = index);
          _pageController.jumpToPage(index);
        },
        items: _tabs
            .map((t) => BottomNavyBarItem(
                  icon: Icon(t.icon),
                  title: Text(t.label),
                  inactiveColor: cs.onSecondary,
                  activeColor: cs.tertiary,
                ))
            .toList(),
      ),
    );
  }

  Widget _buildFlutterBricksBar() {
    final cs = Theme.of(context).colorScheme;

    final pillGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [cs.primary, cs.tertiary],
    );

    final buttons = _tabs.map((t) => NavigationBarButton(
      icon: t.icon,
      text: t.label,
      backgroundGradient: pillGradient,
    )).toList();

    return SafeArea(
      top: false,
      child: Material(
        color: Colors.transparent,
        child: IconTheme(
          data: const IconThemeData(size: 28),
          child: ResponsiveNavigationBar(
            backgroundColor: cs.secondary,
            backgroundOpacity: 1.0,
            selectedIndex: _currentIndex.clamp(0, _tabs.length - 1),
            onTabChange: (i) {
              _pageController.animateToPage(
                i,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutExpo,
              );
            },
            showActiveButtonText: false,
            inactiveIconColor: cs.onSecondary.withOpacity(.45),
            navigationBarButtons: buttons,
          ),
        ),
      ),
    );
  }
}

class _FBIconButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onPressed;

  const _FBIconButton({
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            size: 25,
            color: selected ? selectedColor : unselectedColor,
          ),
          splashRadius: 24,
        ),
      ],
    );
  }
}

class _FBCenterButton extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onPressed;
  final double radius;

  const _FBCenterButton({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onPressed,
    this.radius = 24, // ~48px de diâmetro, combina com height 56
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 25, color: fg),
        splashRadius: radius,
      ),
    );
  }
}
