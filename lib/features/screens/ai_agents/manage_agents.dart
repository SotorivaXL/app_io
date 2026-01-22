// lib/features/screens/chatbot/manage_ai_agents.dart
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_io/auth/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import './agent_settings_page.dart';

class ManageAgenteIAPage extends StatefulWidget {
  const ManageAgenteIAPage({super.key});

  @override
  State<ManageAgenteIAPage> createState() => _ManageAgenteIAPageState();
}

class _ManageAgenteIAPageState extends State<ManageAgenteIAPage> {
  String? _empresaId;
  String? _selectedPhoneId;
  bool _resolving = true;
  String? _resolveError;

  // Para AppBar no estilo da tela de colaboradores
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  // Cache da lista de agentes
  Future<List<Map<String, dynamic>>>? _agentsFuture;

  // Cache dos créditos do workspace
  Future<Map<String, dynamic>>? _creditsFuture;

  @override
  void initState() {
    super.initState();
    _resolveEmpresaId();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveEmpresaId() async {
    setState(() {
      _resolving = true;
      _resolveError = null;
    });

    try {
      final authProvider =
          mounted ? Provider.of<AuthProvider>(context, listen: false) : null;
      final User? user =
          authProvider?.user ?? FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() {
          _resolveError = 'Usuário não autenticado.';
          _resolving = false;
        });
        return;
      }

      final uid = user.uid;

      // 1) Tenta "empresas/{uid}"
      final empDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(uid)
          .get();

      if (empDoc.exists) {
        setState(() {
          _empresaId = uid;
          _resolving = false;
        });
        _refreshAgentsList();
        _refreshCredits();
        return;
      }

      // 2) Tenta "users/{uid}" e pega createdBy
      final usrDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (usrDoc.exists) {
        final data =
            (usrDoc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final createdBy = data['createdBy']?.toString();
        if (createdBy == null || createdBy.isEmpty) {
          setState(() {
            _resolveError =
                'Documento do usuário encontrado, mas sem "createdBy".';
            _resolving = false;
          });
          return;
        }
        setState(() {
          _empresaId = createdBy;
          _resolving = false;
        });
        _refreshAgentsList();
        _refreshCredits();
        return;
      }

      setState(() {
        _resolveError =
            'Documento não encontrado em "empresas" nem em "users".';
        _resolving = false;
      });
    } catch (e) {
      setState(() {
        _resolveError = 'Falha ao resolver empresaId: $e';
        _resolving = false;
      });
    }
  }

  // --- API DO GPT MAKER (CLOUD FUNCTIONS) ---

  void _refreshAgentsList() {
    setState(() {
      _agentsFuture = _fetchGptAgents();
    });
  }

  void _refreshCredits() {
    setState(() {
      _creditsFuture = _fetchWorkspaceCredits();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchGptAgents() async {
    if (_empresaId == null || _selectedPhoneId == null) {
      debugPrint("Aguardando empresa ou telefone...");
      return [];
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getGptAgents')
          .call({
        'empresaId': _empresaId,
        'phoneId': _selectedPhoneId,
      });

      final data = result.data as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Erro ao buscar agentes na API: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchWorkspaceCredits() async {
    if (_empresaId == null || _selectedPhoneId == null) return {};

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getGptWorkspaceCredits')
          .call({
        'empresaId': _empresaId,
        'phoneId': _selectedPhoneId,
      });

      if (result.data is Map) {
        return Map<String, dynamic>.from(result.data as Map);
      }
      return {'raw': result.data};
    } catch (e) {
      debugPrint('Erro ao buscar créditos do workspace: $e');
      return {'error': e.toString()};
    }
  }

  // --- ATIVAÇÃO / DESATIVAÇÃO NO FIRESTORE ---

  Future<void> _activateAgent({
    required String empresaId,
    required String phoneId,
    required String agentId,
    required String agentName,
  }) async {
    final phoneRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(phoneId);

    await phoneRef.set({
      'ai_agent': {
        'enabled': true,
        'agentId': agentId,
        'agentName': agentName,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      }
    }, SetOptions(merge: true));
  }

  Future<void> _deactivateAgent({
    required String empresaId,
    required String phoneId,
  }) async {
    final phoneRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(phoneId);

    await phoneRef.set({
      'ai_agent': {
        'enabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      },
      'ai_agent.agentId': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  // --- HELPERS DE UI ---

  Future<void> _showNotice({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.primaryColor),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (_) {
        return Container(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Ok'),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    double appBarHeight = (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);
    double opacity = (1.0 - (_scrollOffset / 100)).clamp(0.0, 1.0);

    final bool isDesktop = MediaQuery.of(context).size.width > 1024;
    Widget desktopWrap(Widget child) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.only(top: 35),
                child: child,
              ),
            ),
          ),
        );

    if (_resolving) {
      return Scaffold(
        appBar: _buildStyledAppBar(appBarHeight, opacity, cs),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resolveError != null) {
      return Scaffold(
        appBar: _buildStyledAppBar(appBarHeight, opacity, cs),
        body: Center(child: Text(_resolveError!)),
      );
    }

    final empresaId = _empresaId!;

    final content = Column(
      children: [
        _PhonesSelector(
          empresaId: empresaId,
          selectedPhoneId: _selectedPhoneId,
          onChanged: (phoneId) {
            setState(() {
              _selectedPhoneId = phoneId;
            });
            if (phoneId != null) {
              _refreshAgentsList();
              _refreshCredits();
            }
          },
        ),
        const SizedBox(height: 16),
        if (_selectedPhoneId == null)
          const _EmptyHint(
            icon: Icons.phone_android,
            text: 'Selecione um número para ativar a IA.',
          )
        else
          Expanded(
            child: _GptAgentsList(
              empresaId: empresaId,
              phoneId: _selectedPhoneId!,
              fetchAgentsFuture: _agentsFuture,
              creditsFuture: _creditsFuture,
              onRefresh: () {
                _refreshAgentsList();
                _refreshCredits();
              },
              onActivate: (agentId, agentName) async {
                try {
                  await _activateAgent(
                    empresaId: empresaId,
                    phoneId: _selectedPhoneId!,
                    agentId: agentId,
                    agentName: agentName,
                  );
                } catch (e) {
                  _showNotice(title: 'Erro', message: e.toString());
                }
              },
              onDeactivate: () async {
                try {
                  await _deactivateAgent(
                    empresaId: empresaId,
                    phoneId: _selectedPhoneId!,
                  );
                } catch (e) {
                  _showNotice(title: 'Erro', message: e.toString());
                }
              },
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: _buildStyledAppBar(appBarHeight, opacity, cs),
      body: isDesktop
          ? desktopWrap(content)
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: content,
            ),
    );
  }

  PreferredSizeWidget _buildStyledAppBar(
      double appBarHeight, double opacity, ColorScheme cs) {
    return PreferredSize(
      preferredSize: Size.fromHeight(appBarHeight),
      child: Opacity(
        opacity: opacity,
        child: AppBar(
          toolbarHeight: appBarHeight,
          automaticallyImplyLeading: false,
          flexibleSpace: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_back_ios_new,
                                color: cs.onBackground, size: 18),
                            const SizedBox(width: 4),
                            Text('Voltar',
                                style: TextStyle(
                                    fontSize: 14, color: cs.onSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agentes de IA',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: cs.onSecondary),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Atualizar lista de Agentes',
                    onPressed: () {
                      _refreshAgentsList();
                      _refreshCredits();
                    },
                  ),
                ],
              ),
            ),
          ),
          surfaceTintColor: Colors.transparent,
          backgroundColor: cs.secondary,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SELETOR DE TELEFONES
// -----------------------------------------------------------------------------
class _PhonesSelector extends StatelessWidget {
  const _PhonesSelector({
    required this.empresaId,
    required this.selectedPhoneId,
    required this.onChanged,
  });

  final String empresaId;
  final String? selectedPhoneId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('phones')
          .orderBy(FieldPath.documentId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 44, child: Center(child: CircularProgressIndicator()));
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Text('Nenhum número cadastrado no sistema.');
        }

        final items = snap.data!.docs.map((d) {
          final data = d.data();
          final label = (data['label'] ?? data['phoneId'] ?? d.id).toString();
          return DropdownMenuItem<String>(
            value: d.id,
            child: Text(label),
          );
        }).toList();

        final effectiveSelected =
            selectedPhoneId ?? (items.isNotEmpty ? items.first.value : null);

        if (effectiveSelected != selectedPhoneId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onChanged(effectiveSelected);
          });
        }

        return DropdownButton2<String>(
          isExpanded: true,
          value: effectiveSelected,
          items: items,
          onChanged: onChanged,
          buttonStyleData: ButtonStyleData(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          dropdownStyleData: DropdownStyleData(
            offset: const Offset(0, 4),
            decoration: BoxDecoration(
              color: cs.secondary,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          underline: const SizedBox.shrink(),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// LISTA DE AGENTES (API + Firestore + Créditos)
// -----------------------------------------------------------------------------
class _GptAgentsList extends StatelessWidget {
  const _GptAgentsList({
    required this.empresaId,
    required this.phoneId,
    required this.fetchAgentsFuture,
    required this.creditsFuture,
    required this.onActivate,
    required this.onDeactivate,
    required this.onRefresh,
  });

  final String empresaId;
  final String phoneId;
  final Future<List<Map<String, dynamic>>>? fetchAgentsFuture;
  final Future<Map<String, dynamic>>? creditsFuture;
  final Function(String id, String name) onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onRefresh;

  String _extractCreditsText(Map<String, dynamic> data) {
    // tenta alguns nomes comuns (depende do retorno da sua function)
    final candidates = [
      data['credits'],
      data['balance'],
      data['available'],
      data['remaining'],
      (data['data'] is Map) ? (data['data'] as Map)['credits'] : null,
      (data['data'] is Map) ? (data['data'] as Map)['balance'] : null,
    ];

    for (final c in candidates) {
      if (c == null) continue;
      if (c is num) return c.toString();
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }

    if (data.containsKey('error')) return '—';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final phoneDocRef = FirebaseFirestore.instance
        .collection('empresas')
        .doc(empresaId)
        .collection('phones')
        .doc(phoneId);

    return Column(
      children: [
        // Header + Créditos
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cloud_sync,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Sincronizado via API",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (creditsFuture != null)
                FutureBuilder<Map<String, dynamic>>(
                  future: creditsFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Text(
                        'Créditos restantes: ...',
                        style: TextStyle(fontSize: 12, color: Color.fromARGB(255, 255, 255, 255)),
                      );
                    }
                    final data = snap.data ?? {};
                    final credits = _extractCreditsText(data);
                    return Text(
                      'Créditos restantes: $credits',
                      style: const TextStyle(fontSize: 12, color: Color.fromARGB(255, 255, 255, 255)),
                    );
                  },
                ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: phoneDocRef.snapshots(),
            builder: (context, phoneSnap) {
              final phoneData =
                  phoneSnap.data?.data() as Map<String, dynamic>? ?? {};

              final agentCfg = (phoneData['ai_agent'] as Map?) ?? {};
              final bool enabled = agentCfg['enabled'] == true;
              final String? activeAgentId = agentCfg['agentId']?.toString();

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: fetchAgentsFuture,
                builder: (context, apiSnap) {
                  if (apiSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (apiSnap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 40, color: Colors.red),
                            const SizedBox(height: 12),
                            Text(
                              "Erro ao carregar agentes:\n${apiSnap.error}",
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: onRefresh,
                              child: const Text("Tentar Novamente"),
                            )
                          ],
                        ),
                      ),
                    );
                  }

                  final agents = apiSnap.data ?? [];

                  if (agents.isEmpty) {
                    return const _EmptyHint(
                      icon: Icons.smart_toy_outlined,
                      text: "Nenhum agente encontrado no GPT Maker.",
                    );
                  }

                  return ListView.separated(
                    itemCount: agents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final agent = agents[i];
                      final agentId = agent['id'].toString();
                      final agentName = agent['name']?.toString() ?? 'Sem Nome';
                      final description =
                          agent['description']?.toString() ?? '';

                      final isActive = enabled && activeAgentId == agentId;
                      final cs = Theme.of(context).colorScheme;

                      return Card(
                        elevation: isActive ? 4 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isActive
                              ? BorderSide(color: cs.primary, width: 2)
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: isActive
                                ? cs.primary.withOpacity(0.1)
                                : cs.surfaceVariant,
                            child: Icon(
                              Icons.auto_awesome,
                              color: isActive ? cs.primary : Colors.grey,
                            ),
                          ),
                          title: Text(
                            agentName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: description.isNotEmpty
                              ? Text(description,
                                  maxLines: 2, overflow: TextOverflow.ellipsis)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (v) {
                                  if (v == 'settings') {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AgentSettingsPage(
                                          empresaId: empresaId,
                                          phoneId: phoneId,
                                          agentId: agentId,
                                          agentName: agentName,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'settings',
                                    child: Text('Configurar agente'),
                                  ),
                                ],
                              ),
                              Transform.scale(
                                scale: 0.9,
                                child: Switch(
                                  value: isActive,
                                  onChanged: (val) {
                                    if (val) {
                                      onActivate(agentId, agentName);
                                    } else {
                                      if (isActive) onDeactivate();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              text,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
