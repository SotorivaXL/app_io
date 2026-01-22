import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AgentSettingsPage extends StatefulWidget {
  const AgentSettingsPage({
    super.key,
    required this.empresaId,
    required this.phoneId,
    required this.agentId,
    required this.agentName,
  });

  final String empresaId;
  final String phoneId;
  final String agentId;
  final String agentName;

  @override
  State<AgentSettingsPage> createState() => _AgentSettingsPageState();
}

class _AgentSettingsPageState extends State<AgentSettingsPage> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _agent; // dados do agente (PUT /agent)
  Map<String, dynamic>? _settings; // settings (PUT /agent/{id}/settings)

  // Perfil
  final _nameCtrl = TextEditingController();
  final _behaviorCtrl = TextEditingController();
  String _communicationType = 'NORMAL'; // FORMAL | NORMAL | RELAXED

  // Trabalho
  String _agentType = 'SUPPORT'; // SUPPORT | SALE | PERSONAL
  final _jobNameCtrl = TextEditingController();
  final _jobSiteCtrl = TextEditingController();
  final _jobDescCtrl = TextEditingController();

  // Configurações (API GPT Maker)
  bool _enabledEmoji = true;
  bool _limitSubjects = false;
  String? _prefferModel; // enum

  // Configuração do SEU sistema (debounce)
  double _debounceSeconds = 10;

  static const List<String> _models = [
    'GPT_5',
    'GPT_5_MINI',
    'GPT_5_1',
    'GPT_5_2',
    'GPT_5_MINI_V2',
    'GPT_4_TURBO',
    'GPT_4_1',
    'GPT_4_1_MINI',
    'GPT_4_O_MINI',
    'GPT_4_O',
    'CLAUDE_4_5_SONNET',
    'CLAUDE_3_7_SONNET',
    'CLAUDE_3_5_HAIKU',
    'DEEPINFRA_LLAMA3_3',
    'QWEN_2_5_MAX',
    'DEEPSEEK_CHAT',
    'SABIA_3',
    'SABIA_3_1',
  ];

  /// CUSTO MANUAL (edite como quiser)
  /// Se algum modelo não estiver aqui, mostra só o nome (sem custo).
  static const Map<String, int> _modelCreditsCost = {
    'GPT_5': 4,
    'GPT_5_MINI': 1,
    'GPT_5_1': 4,
    'GPT_5_2': 5,
    'GPT_5_MINI_V2': 1,
    'GPT_4_TURBO': 20,
    'GPT_4_1': 4,
    'GPT_4_1_MINI': 1,
    'GPT_4_O_MINI': 1,
    'GPT_4_O': 5,
    'CLAUDE_4_5_SONNET': 10,
    'CLAUDE_3_7_SONNET': 10,
    'CLAUDE_3_5_HAIKU': 2,
    'DEEPINFRA_LLAMA3_3': 1,
    'QWEN_2_5_MAX': 3,
    'DEEPSEEK_CHAT': 1,
    'SABIA_3': 3,
    'SABIA_3_1': 3,
  };

  static const int _maxBehavior = 3000;
  static const int _maxJobDesc = 500;
  static const int _maxJobName = 50;

  int get _behaviorLen => _behaviorCtrl.text.characters.length;
  int get _jobDescLen => _jobDescCtrl.text.characters.length;
  int get _jobNameLen => _jobNameCtrl.text.characters.length;

  String _modelLabel(String model) {
    final cost = _modelCreditsCost[model];
    if (cost == null) return model;
    if (cost <= 0) return model;
    return '$model ($cost créditos)';
  }

  @override
  void initState() {
    super.initState();
    _behaviorCtrl.addListener(_onCountersChanged);
    _jobDescCtrl.addListener(_onCountersChanged);
    _jobNameCtrl.addListener(_onCountersChanged);
    _loadAll();
  }

  void _onCountersChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _behaviorCtrl.removeListener(_onCountersChanged);
    _jobDescCtrl.removeListener(_onCountersChanged);
    _jobNameCtrl.removeListener(_onCountersChanged);

    _nameCtrl.dispose();
    _behaviorCtrl.dispose();
    _jobNameCtrl.dispose();
    _jobSiteCtrl.dispose();
    _jobDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fns = FirebaseFunctions.instance;

      final agentRes = await fns.httpsCallable('getGptAgentById').call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
      });

      final settingsRes = await fns.httpsCallable('getGptAgentSettings').call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
      });

      final phoneSnap = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('phones')
          .doc(widget.phoneId)
          .get();

      final phoneData = phoneSnap.data() ?? <String, dynamic>{};
      final aiAgent = (phoneData['ai_agent'] as Map?) ?? {};
      final ds = aiAgent['debounceSeconds'];

      _debounceSeconds = (ds is num) ? ds.toDouble().clamp(0, 30) : 10.0;

      _agent = Map<String, dynamic>.from(agentRes.data as Map);
      _settings = Map<String, dynamic>.from(settingsRes.data as Map);

      // --- Popular Perfil ---
      _nameCtrl.text = (_agent?['name'] ?? widget.agentName).toString();
      _behaviorCtrl.text = (_agent?['behavior'] ?? '').toString();
      _communicationType =
          (_agent?['communicationType'] ?? 'NORMAL').toString();

      // --- Popular Trabalho ---
      _agentType = (_agent?['type'] ?? 'SUPPORT').toString();
      _jobNameCtrl.text = (_agent?['jobName'] ?? '').toString();
      _jobSiteCtrl.text = (_agent?['jobSite'] ?? '').toString();
      _jobDescCtrl.text = (_agent?['jobDescription'] ?? '').toString();

      // --- Popular Configs (API) ---
      _enabledEmoji = _settings?['enabledEmoji'] == true;
      _limitSubjects = _settings?['limitSubjects'] == true;

      final m = _settings?['prefferModel']?.toString();
      _prefferModel = (m != null && _models.contains(m)) ? m : null;

      // garante que não estoure limite caso venha grande do backend
      if (_behaviorLen > _maxBehavior) {
        _behaviorCtrl.text =
            _behaviorCtrl.text.characters.take(_maxBehavior).toString();
      }
      if (_jobDescLen > _maxJobDesc) {
        _jobDescCtrl.text =
            _jobDescCtrl.text.characters.take(_maxJobDesc).toString();
      }
      if (_jobNameLen > _maxJobName) {
        _jobNameCtrl.text =
            _jobNameCtrl.text.characters.take(_maxJobName).toString();
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    try {
      final fns = FirebaseFunctions.instance;

      await fns.httpsCallable('updateGptAgent').call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
        'patch': {
          'name': _nameCtrl.text.trim(),
          'communicationType': _communicationType,
          'behavior': _behaviorCtrl.text.trim(),
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo com sucesso')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar perfil: $e')),
      );
    }
  }

  Future<void> _saveWork() async {
    try {
      final fns = FirebaseFunctions.instance;

      await fns.httpsCallable('updateGptAgent').call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
        'patch': {
          'type': _agentType,
          'jobName': _jobNameCtrl.text.trim(),
          'jobSite': _jobSiteCtrl.text.trim(),
          'jobDescription': _jobDescCtrl.text.trim(),
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trabalho salvo com sucesso')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar trabalho: $e')),
      );
    }
  }

  /// Salva settings do GPT Maker (só o que está liberado por enquanto)
  Future<void> _saveSettings() async {
    try {
      final fns = FirebaseFunctions.instance;

      final payload = <String, dynamic>{
        'enabledEmoji': _enabledEmoji,
        'limitSubjects': _limitSubjects,
        if (_prefferModel != null && _prefferModel!.isNotEmpty)
          'prefferModel': _prefferModel,
      };

      await fns.httpsCallable('updateGptAgentSettings').call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
        'settings': payload,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar configurações: $e')),
      );
    }
  }

  /// Salva debounce no Firestore (controle do seu Cloud Tasks debounce)
  Future<void> _saveDebounce() async {
    try {
      final phoneRef = FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('phones')
          .doc(widget.phoneId);

      await phoneRef.set({
        'ai_agent': {
          'debounceSeconds': _debounceSeconds.toInt(),
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tempo de espera salvo!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar tempo de espera: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Configurar: ${widget.agentName}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Configurar: ${widget.agentName}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadAll,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Configurar: ${widget.agentName}'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Perfil'),
              Tab(text: 'Trabalho'),
              Tab(text: 'Configurações'),
              Tab(text: 'Treinamento'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // PERFIL
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do agente',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _communicationType,
                  items: const [
                    DropdownMenuItem(value: 'FORMAL', child: Text('Formal')),
                    DropdownMenuItem(value: 'NORMAL', child: Text('Normal')),
                    DropdownMenuItem(value: 'RELAXED', child: Text('Descontraída')),
                  ],
                  onChanged: (v) =>
                      setState(() => _communicationType = v ?? 'NORMAL'),
                  decoration: const InputDecoration(
                    labelText: 'Forma de comunicação',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _behaviorCtrl,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: _maxBehavior,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(_maxBehavior),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Comportamento (instruções do agente)',
                    border: const OutlineInputBorder(),
                    hintText: 'Ex: Seja objetivo, use bullets, não invente, etc.',
                    helperText: '${_behaviorLen.toString()}/$_maxBehavior',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar perfil'),
                ),
              ],
            ),

            // TRABALHO
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: _agentType,
                  items: const [
                    DropdownMenuItem(value: 'SUPPORT', child: Text('Suporte')),
                    DropdownMenuItem(value: 'SALE', child: Text('Vendas')),
                    DropdownMenuItem(value: 'PERSONAL', child: Text('Uso pessoal')),
                  ],
                  onChanged: (v) =>
                      setState(() => _agentType = v ?? 'SUPPORT'),
                  decoration: const InputDecoration(
                    labelText: 'Finalidade',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _jobNameCtrl,
                  maxLength: _maxJobName,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(_maxJobName),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Produto/Empresa (jobName)',
                    border: const OutlineInputBorder(),
                    helperText: '${_jobNameLen.toString()}/$_maxJobName',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _jobSiteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Site oficial (jobSite)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _jobDescCtrl,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: _maxJobDesc,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(_maxJobDesc),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Descrição (jobDescription)',
                    border: const OutlineInputBorder(),
                    helperText: '${_jobDescLen.toString()}/$_maxJobDesc',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saveWork,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar trabalho'),
                ),
              ],
            ),

            // CONFIGURAÇÕES
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  value: false,
                  onChanged: null,
                  title: const Text('Permitir transbordo humano'),
                  subtitle: const Text('Em breve'),
                ),
                SwitchListTile(
                  value: _enabledEmoji,
                  onChanged: (v) => setState(() => _enabledEmoji = v),
                  title: const Text('Usar emojis'),
                ),
                SwitchListTile(
                  value: false,
                  onChanged: null,
                  title: const Text('Dividir respostas longas'),
                  subtitle: const Text('Em breve'),
                ),
                SwitchListTile(
                  value: _limitSubjects,
                  onChanged: (v) => setState(() => _limitSubjects = v),
                  title: const Text('Restringir temas'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: (_prefferModel != null && _models.contains(_prefferModel))
                      ? _prefferModel
                      : null,
                  items: _models.map((m) {
                    return DropdownMenuItem(
                      value: m,
                      child: Text(_modelLabel(m)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _prefferModel = v),
                  decoration: const InputDecoration(
                    labelText: 'Modelo preferido (prefferModel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tempo de espera para agrupar mensagens (debounce)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_debounceSeconds.toInt()}s',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          min: 0,
                          max: 30,
                          divisions: 30,
                          value: _debounceSeconds.clamp(0, 30),
                          label: '${_debounceSeconds.toInt()}s',
                          onChanged: (v) => setState(() => _debounceSeconds = v),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Define quantos segundos o bot espera você parar de digitar antes de responder.',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _saveDebounce,
                          icon: const Icon(Icons.save),
                          label: const Text('Salvar tempo de espera'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar configurações (GPT Maker)'),
                ),
              ],
            ),

            // TREINAMENTO (somente texto)
            _TrainingTab(
              empresaId: widget.empresaId,
              phoneId: widget.phoneId,
              agentId: widget.agentId,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ABA: TREINAMENTO (somente texto)
// =============================================================================
class _TrainingTab extends StatefulWidget {
  const _TrainingTab({
    required this.empresaId,
    required this.phoneId,
    required this.agentId,
  });

  final String empresaId;
  final String phoneId;
  final String agentId;

  @override
  State<_TrainingTab> createState() => _TrainingTabState();
}

class _TrainingTabState extends State<_TrainingTab> {
  static const int _pageSize = 10;
  static const int _maxLen = 1000;

  final _textCtrl = TextEditingController();

  bool _loading = true;
  bool _creating = false;
  String? _error;

  int _page = 1;
  int? _total; // pode ser null se a API não retornar
  List<Map<String, dynamic>> _items = [];

  int get _len => _textCtrl.text.characters.length;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => mounted ? setState(() {}) : null);
    _loadPage(1);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPage(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res =
          await FirebaseFunctions.instance.httpsCallable('listGptTrainings').call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
        'page': page,
        'pageSize': _pageSize,
      });

      final data = Map<String, dynamic>.from(res.data as Map);

      final rawItems = (data['items'] as List?) ?? [];
      final items =
          rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      setState(() {
        _items = items;
        _page = (data['page'] ?? page) as int;
        _total = data['total'] is int ? data['total'] as int : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createTraining() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    if (text.length > _maxLen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Texto excede 1000 caracteres.')),
      );
      return;
    }

    setState(() => _creating = true);

    try {
      await FirebaseFunctions.instance
          .httpsCallable('createGptTrainingText')
          .call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
        'text': text,
      });

      _textCtrl.clear();
      await _loadPage(1);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treinamento cadastrado!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cadastrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteTraining(String trainingId) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteGptTraining').call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'trainingId': trainingId,
      });

      await _loadPage(_page);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treinamento removido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover: $e')),
      );
    }
  }

  Future<void> _editTraining({
    required String trainingId,
    required String currentText,
  }) async {
    final ctrl = TextEditingController(text: currentText);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Editar treinamento'),
          content: TextField(
            controller: ctrl,
            minLines: 3,
            maxLines: 8,
            maxLength: _maxLen,
            inputFormatters: [LengthLimitingTextInputFormatter(_maxLen)],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Digite o texto do treinamento...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final newText = ctrl.text.trim();
    if (newText.isEmpty) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('updateGptTrainingText')
          .call({
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'trainingId': trainingId,
        'text': newText,
      });

      await _loadPage(_page);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Treinamento atualizado!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar: $e')),
      );
    }
  }

  String _extractId(Map<String, dynamic> item) {
    return (item['id'] ?? item['_id'] ?? item['trainingId'] ?? '').toString();
  }

  String _extractText(Map<String, dynamic> item) {
    return (item['text'] ?? item['content'] ?? item['value'] ?? '').toString();
  }

  String _extractStatus(Map<String, dynamic> item) {
    return (item['status'] ?? item['state'] ?? '').toString().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _loadPage(_page),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // BOX: novo treinamento
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Novo treinamento via texto',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _textCtrl,
                  maxLength: _maxLen,
                  inputFormatters: [LengthLimitingTextInputFormatter(_maxLen)],
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: 'Escreva uma afirmação e clique em cadastrar...',
                    border: const OutlineInputBorder(),
                    helperText: '${_len.toString()}/$_maxLen',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _creating ? null : _createTraining,
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cadastrar'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // LISTA
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Nenhum treinamento cadastrado.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          )
        else
          ..._items.map((item) {
            final id = _extractId(item);
            final text = _extractText(item);
            final st = _extractStatus(item);

            final bool training =
                st.contains('TRAIN') || st.contains('PROCESS');

            return Card(
              child: ListTile(
                title: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: training
                            ? cs.primary.withOpacity(0.12)
                            : Colors.green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        training ? 'Treinando' : 'Concluído',
                        style: TextStyle(
                          fontSize: 12,
                          color: training ? cs.primary : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (id.isEmpty) return;
                        if (v == 'edit') {
                          await _editTraining(
                              trainingId: id, currentText: text);
                        } else if (v == 'delete') {
                          await _deleteTraining(id);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'delete', child: Text('Excluir')),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

        const SizedBox(height: 12),

        // PAGINAÇÃO
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _total != null ? 'Página $_page • Total $_total' : 'Página $_page',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: _page > 1 ? () => _loadPage(_page - 1) : null,
                  child: const Text('Anterior'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _items.length == _pageSize
                      ? () => _loadPage(_page + 1)
                      : null,
                  child: const Text('Próxima'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
