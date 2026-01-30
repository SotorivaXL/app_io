import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // Identidade
  final _nameCtrl = TextEditingController();
  final _behaviorCtrl = TextEditingController();
  String _communicationType = 'NORMAL'; // FORMAL | NORMAL | RELAXED

  // Negócio
  String _agentType = 'SUPPORT'; // SUPPORT | SALE | PERSONAL
  final _jobNameCtrl = TextEditingController();
  final _jobSiteCtrl = TextEditingController();
  final _jobDescCtrl = TextEditingController();

  // Atendimento (API GPT Maker)
  bool _enabledEmoji = true;
  bool _limitSubjects = false;
  String? _prefferModel; // enum

  // Configuração do SEU sistema (debounce)
  double _debounceSeconds = 10;

  // Atendimento (Leads / Vendas)
  bool _leadsActive = true;
  final _openingMessageCtrl = TextEditingController();
  bool _sendOpeningAuto = true;

  final _q1Ctrl = TextEditingController();
  final _q2Ctrl = TextEditingController();
  final _q3Ctrl = TextEditingController();
  final _q4Ctrl = TextEditingController();
  bool _askBudget = false;

  final _fitHighCtrl = TextEditingController();
  final _fitMediumCtrl = TextEditingController();

  final Map<String, bool> _painSignals = {
    'Quer escalar vendas': false,
    'Quer profissionalizar marketing': false,
    'Reclama de agência anterior': false,
    'Leads/vendas caíram': false,
    'Quer previsibilidade': false,
  };

  final Map<String, bool> _minInterests = {
    'Tráfego pago': false,
    'Gestão completa': false,
    'Conteúdo / social': false,
    'Site / landing page': false,
    'Analytics / tracking': false,
  };

  bool _callHumanOnFitHigh = true;
  bool _callHumanOnPricing = true;
  bool _callHumanOnProposal = true;
  bool _callHumanOnMeeting = true;
  bool _callHumanOnLongAudio = true;
  bool _callHumanOnAskSomeone = true;
  bool _callHumanOnReferral = true;
  int _longAudioSeconds = 60;
  final _transferMessageCtrl = TextEditingController();

  bool _scheduleEnabled = true;
  final _scheduleInviteCtrl = TextEditingController();
  List<String> _scheduleSlots = [
    'Hoje 14:00',
    'Hoje 16:00',
    'Amanhã 09:30',
    'Amanhã 15:00',
  ];
  String _scheduleOwner = 'Márcio';
  final _scheduleOwnerOtherCtrl = TextEditingController();

  bool _followupEnabled = true;
  String _followup1 = '24h';
  String _followup2 = '48h';
  String _followup3 = '7 dias';
  final _followupMsg1Ctrl = TextEditingController();
  final _followupMsg2Ctrl = TextEditingController();
  final _followupMsg3Ctrl = TextEditingController();

  static const List<String> _googleCalendarScopes = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events',
    'openid',
    'email',
    'profile',
  ];
  static const String _webGoogleClientId =
      '148670195922-ufe65jbf3ic7h8a6vmnh8sup4pshthpr.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _calendarLoading = false;
  bool _calendarConnected = false;
  String? _calendarEmail;
  String? _calendarDisplayName;
  String? _calendarPhotoUrl;

  bool _googleReady = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _calendarDocSub;
  Timer? _leadsSaveTimer;

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

  static const List<String> _scheduleOwners = [
    'Márcio',
    'Samuel',
    'Outro',
  ];

  static const List<int> _longAudioOptions = [30, 45, 60, 90];
  static const List<String> _followup1Options = ['24h'];
  static const List<String> _followup2Options = ['48h', '72h'];
  static const List<String> _followup3Options = ['7 dias'];

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
    _initGoogleSignIn();
    _listenCalendarDoc();
    _loadAll();
  }

  void _onCountersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initGoogleSignIn() async {
    try {
      await _googleSignIn.initialize(
        clientId: kIsWeb ? _webGoogleClientId : null,
        serverClientId: kIsWeb ? null : _webGoogleClientId,
      );
      if (!mounted) return;
      setState(() => _googleReady = true);
      _googleAuthSub = _googleSignIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _handleWebSignIn(event.user);
        }
      });
    } catch (_) {
      // Falha silenciosa: integração é opcional na UI.
    }
  }

  Future<void> _ensureGoogleInit() async {
    if (_googleReady) return;
    try {
      await _googleSignIn.initialize(
        clientId: kIsWeb ? _webGoogleClientId : null,
        serverClientId: kIsWeb ? null : _webGoogleClientId,
      );
      if (mounted) setState(() => _googleReady = true);
    } catch (_) {}
  }

  Future<void> _handleWebSignIn(GoogleSignInAccount account) async {
    if (!kIsWeb) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      final ref = FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('integrations')
          .doc('google_calendar');

      await ref.set({
        'connected': true,
        'email': account.email,
        'displayName': account.displayName ?? '',
        'photoUrl': account.photoUrl ?? '',
        'provider': 'google',
        'updatedBy': user?.uid,
        'connectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _calendarConnected = true;
        _calendarEmail = account.email;
        _calendarDisplayName = account.displayName;
        _calendarPhotoUrl = account.photoUrl;
      });
    } catch (_) {
      // ignora: a UI vai manter o estado atual
    }
  }

  Future<void> _startGoogleCalendarWebFlow() async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getGoogleCalendarOAuthUrl')
          .call({'empresaId': widget.empresaId});
      final data = (res.data as Map?) ?? {};
      final url = data['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('URL de autorização inválida');
      }
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao iniciar OAuth: $e')),
      );
    }
  }

  void _listenCalendarDoc() {
    _calendarDocSub?.cancel();
    _calendarDocSub = FirebaseFirestore.instance
        .collection('empresas')
        .doc(widget.empresaId)
        .collection('integrations')
        .doc('google_calendar')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data() ?? <String, dynamic>{};
      final connected = data['connected'] == true;
      setState(() {
        _calendarConnected = connected;
        _calendarEmail = connected ? data['email']?.toString() : null;
        _calendarDisplayName =
            connected ? data['displayName']?.toString() : null;
        _calendarPhotoUrl = connected ? data['photoUrl']?.toString() : null;
      });
    });
  }

  @override
  void dispose() {
    _behaviorCtrl.removeListener(_onCountersChanged);
    _jobDescCtrl.removeListener(_onCountersChanged);
    _jobNameCtrl.removeListener(_onCountersChanged);

    _leadsSaveTimer?.cancel();
    _googleAuthSub?.cancel();
    _calendarDocSub?.cancel();
    _nameCtrl.dispose();
    _behaviorCtrl.dispose();
    _jobNameCtrl.dispose();
    _jobSiteCtrl.dispose();
    _jobDescCtrl.dispose();
    _openingMessageCtrl.dispose();
    _q1Ctrl.dispose();
    _q2Ctrl.dispose();
    _q3Ctrl.dispose();
    _q4Ctrl.dispose();
    _fitHighCtrl.dispose();
    _fitMediumCtrl.dispose();
    _transferMessageCtrl.dispose();
    _scheduleInviteCtrl.dispose();
    _scheduleOwnerOtherCtrl.dispose();
    _followupMsg1Ctrl.dispose();
    _followupMsg2Ctrl.dispose();
    _followupMsg3Ctrl.dispose();
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

      final leadsSnap = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('phones')
          .doc(widget.phoneId)
          .collection('ai_agent_leads')
          .doc(widget.agentId)
          .get();

      final calendarSnap = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('integrations')
          .doc('google_calendar')
          .get();

      final phoneData = phoneSnap.data() ?? <String, dynamic>{};
      final aiAgent = (phoneData['ai_agent'] as Map?) ?? {};
      final ds = aiAgent['debounceSeconds'];

      _debounceSeconds = (ds is num) ? ds.toDouble().clamp(0, 30) : 10.0;

      _agent = Map<String, dynamic>.from(agentRes.data as Map);
      _settings = Map<String, dynamic>.from(settingsRes.data as Map);

      final leadsData = leadsSnap.data() ?? <String, dynamic>{};
      final calendarData = calendarSnap.data() ?? <String, dynamic>{};

      // --- Popular Identidade ---
      _nameCtrl.text = (_agent?['name'] ?? widget.agentName).toString();
      _behaviorCtrl.text = (_agent?['behavior'] ?? '').toString();
      _communicationType =
          (_agent?['communicationType'] ?? 'NORMAL').toString();

      // --- Popular Negócio ---
      _agentType = (_agent?['type'] ?? 'SUPPORT').toString();
      _jobNameCtrl.text = (_agent?['jobName'] ?? '').toString();
      _jobSiteCtrl.text = (_agent?['jobSite'] ?? '').toString();
      _jobDescCtrl.text = (_agent?['jobDescription'] ?? '').toString();

      // --- Popular Atendimento (API) ---
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

      // --- Popular Atendimento (Leads / Vendas) ---
      _leadsActive =
          leadsData['active'] is bool ? leadsData['active'] as bool : true;
      _openingMessageCtrl.text = (leadsData['openingMessage'] ??
              'Oi! Aqui é a IA da IO Marketing Digital 🚀\n'
                  'Me conta rapidinho: qual é o momento da sua empresa e o que você está buscando no marketing?')
          .toString();
      _sendOpeningAuto = leadsData['sendOpeningAuto'] is bool
          ? leadsData['sendOpeningAuto'] as bool
          : true;

      final q = (leadsData['qualification'] as Map?) ?? {};
      _q1Ctrl.text =
          (q['q1'] ?? 'Qual é o faturamento mensal aproximado?').toString();
      _q2Ctrl.text = (q['q2'] ??
              'Qual serviço você tem interesse? (tráfego, gestão completa, conteúdo...)')
          .toString();
      _q3Ctrl.text = (q['q3'] ?? 'Qual seu maior desafio hoje?').toString();
      _askBudget = q['askBudget'] is bool ? q['askBudget'] as bool : false;
      _q4Ctrl.text = (q['q4'] ??
              'Tem uma faixa de investimento mensal prevista pra marketing?')
          .toString();

      final fit = (leadsData['fit'] as Map?) ?? {};
      _fitHighCtrl.text = (fit['high'] ?? 200000).toString();
      _fitMediumCtrl.text = (fit['medium'] ?? 50000).toString();

      final pain =
          (fit['painSignals'] as List?)?.map((e) => e.toString()).toSet() ?? {};
      for (final key in _painSignals.keys) {
        _painSignals[key] = pain.contains(key);
      }

      final interests =
          (fit['minInterests'] as List?)?.map((e) => e.toString()).toSet() ?? {};
      for (final key in _minInterests.keys) {
        _minInterests[key] = interests.contains(key);
      }

      final transfer = (leadsData['transfer'] as Map?) ?? {};
      _callHumanOnFitHigh =
          transfer['onFitHigh'] is bool ? transfer['onFitHigh'] as bool : true;
      _callHumanOnPricing =
          transfer['onPricing'] is bool ? transfer['onPricing'] as bool : true;
      _callHumanOnProposal =
          transfer['onProposal'] is bool ? transfer['onProposal'] as bool : true;
      _callHumanOnMeeting =
          transfer['onMeeting'] is bool ? transfer['onMeeting'] as bool : true;
      _callHumanOnLongAudio =
          transfer['onLongAudio'] is bool ? transfer['onLongAudio'] as bool : true;
      _callHumanOnAskSomeone =
          transfer['onAskSomeone'] is bool ? transfer['onAskSomeone'] as bool : true;
      _callHumanOnReferral =
          transfer['onReferral'] is bool ? transfer['onReferral'] as bool : true;
      _longAudioSeconds = transfer['longAudioSeconds'] is int
          ? transfer['longAudioSeconds'] as int
          : 60;
      if (!_longAudioOptions.contains(_longAudioSeconds)) {
        _longAudioSeconds = 60;
      }
      _transferMessageCtrl.text = (transfer['message'] ??
              'Perfeito — vou chamar alguém do nosso time pra te atender e já te direcionar certinho. Só um instante 🙂')
          .toString();

      final schedule = (leadsData['schedule'] as Map?) ?? {};
      _scheduleEnabled =
          schedule['enabled'] is bool ? schedule['enabled'] as bool : true;
      _scheduleInviteCtrl.text = (schedule['inviteText'] ??
              'Posso te agendar ainda essa semana. Qual horário funciona melhor?')
          .toString();
      final slots =
          (schedule['slots'] as List?)?.map((e) => e.toString()).toList();
      if (slots != null && slots.isNotEmpty) {
        _scheduleSlots = slots;
      }
      final owner = (schedule['owner'] ?? 'Márcio').toString();
      if (_scheduleOwners.contains(owner)) {
        _scheduleOwner = owner;
        _scheduleOwnerOtherCtrl.text =
            (schedule['ownerOther'] ?? '').toString();
      } else {
        _scheduleOwner = 'Outro';
        _scheduleOwnerOtherCtrl.text = owner;
      }

      final followup = (leadsData['followup'] as Map?) ?? {};
      _followupEnabled =
          followup['enabled'] is bool ? followup['enabled'] as bool : true;
      final f1 = (followup['f1'] ?? '24h').toString();
      final f2 = (followup['f2'] ?? '48h').toString();
      final f3 = (followup['f3'] ?? '7 dias').toString();
      _followup1 = _followup1Options.contains(f1) ? f1 : '24h';
      _followup2 = _followup2Options.contains(f2) ? f2 : '48h';
      _followup3 = _followup3Options.contains(f3) ? f3 : '7 dias';
      _followupMsg1Ctrl.text = (followup['msg1'] ??
              'Oi! Só passando pra ver se você conseguiu responder minhas perguntas — aí já te direciono certinho 🙂')
          .toString();
      _followupMsg2Ctrl.text = (followup['msg2'] ??
              'Se fizer sentido, posso te agendar uma conversa rápida pra entender seu cenário e sugerir o melhor caminho.')
          .toString();
      _followupMsg3Ctrl.text = (followup['msg3'] ??
              'Último toque por aqui: se quiser, me diga seu objetivo e eu te mando um plano de ação inicial.')
          .toString();

      _calendarConnected = calendarData['connected'] == true;
      _calendarEmail =
          _calendarConnected ? calendarData['email']?.toString() : null;
      _calendarDisplayName =
          _calendarConnected ? calendarData['displayName']?.toString() : null;
      _calendarPhotoUrl =
          _calendarConnected ? calendarData['photoUrl']?.toString() : null;

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
        const SnackBar(content: Text('Identidade salva com sucesso')),
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
        const SnackBar(content: Text('Negócio salvo com sucesso')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar trabalho: $e')),
      );
    }
  }

  /// Salva settings do GPT Maker (só o que está liberado por enquanto)
  Future<void> _saveSettings({bool showSnackBar = true}) async {
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

      if (!mounted || !showSnackBar) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso')),
      );
    } catch (e) {
      if (!mounted || !showSnackBar) return;
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

  void _scheduleLeadsSave({bool immediate = false}) {
    _leadsSaveTimer?.cancel();
    if (immediate) {
      _saveLeadsSettings(showSnackBar: false);
      return;
    }
    _leadsSaveTimer = Timer(
      const Duration(milliseconds: 700),
      () => _saveLeadsSettings(showSnackBar: false),
    );
  }

  Future<void> _saveLeadsSettings({bool showSnackBar = false}) async {
    try {
      final leadsRef = FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresaId)
          .collection('phones')
          .doc(widget.phoneId)
          .collection('ai_agent_leads')
          .doc(widget.agentId);

      final fitHigh = int.tryParse(_fitHighCtrl.text.trim());
      final fitMedium = int.tryParse(_fitMediumCtrl.text.trim());

      final ownerValue = _scheduleOwner == 'Outro'
          ? _scheduleOwnerOtherCtrl.text.trim()
          : _scheduleOwner;

      await leadsRef.set({
        'active': _leadsActive,
        'openingMessage': _openingMessageCtrl.text.trim(),
        'sendOpeningAuto': _sendOpeningAuto,
        'qualification': {
          'q1': _q1Ctrl.text.trim(),
          'q2': _q2Ctrl.text.trim(),
          'q3': _q3Ctrl.text.trim(),
          'askBudget': _askBudget,
          'q4': _q4Ctrl.text.trim(),
        },
        'fit': {
          if (fitHigh != null) 'high': fitHigh,
          if (fitMedium != null) 'medium': fitMedium,
          'painSignals': _painSignals.entries
              .where((e) => e.value)
              .map((e) => e.key)
              .toList(),
          'minInterests': _minInterests.entries
              .where((e) => e.value)
              .map((e) => e.key)
              .toList(),
        },
        'transfer': {
          'onFitHigh': _callHumanOnFitHigh,
          'onPricing': _callHumanOnPricing,
          'onProposal': _callHumanOnProposal,
          'onMeeting': _callHumanOnMeeting,
          'onLongAudio': _callHumanOnLongAudio,
          'onAskSomeone': _callHumanOnAskSomeone,
          'onReferral': _callHumanOnReferral,
          'longAudioSeconds': _longAudioSeconds,
          'message': _transferMessageCtrl.text.trim(),
        },
        'schedule': {
          'enabled': _scheduleEnabled,
          'inviteText': _scheduleInviteCtrl.text.trim(),
          'slots': _scheduleSlots
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          'owner': ownerValue.isEmpty ? 'Outro' : ownerValue,
          'ownerOther': _scheduleOwnerOtherCtrl.text.trim(),
        },
        'followup': {
          'enabled': _followupEnabled,
          'f1': _followup1,
          'f2': _followup2,
          'f3': _followup3,
          'msg1': _followupMsg1Ctrl.text.trim(),
          'msg2': _followupMsg2Ctrl.text.trim(),
          'msg3': _followupMsg3Ctrl.text.trim(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted || !showSnackBar) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações de atendimento salvas.')),
      );
    } catch (e) {
      if (!mounted || !showSnackBar) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar atendimento: $e')),
      );
    }
  }

  Future<void> _openDebounceDialog() async {
    double temp = _debounceSeconds;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tempo de espera (debounce)'),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${temp.toInt()}s'),
                  Slider(
                    min: 0,
                    max: 30,
                    divisions: 30,
                    value: temp.clamp(0, 30),
                    label: '${temp.toInt()}s',
                    onChanged: (v) => setStateDialog(() => temp = v),
                  ),
                  Text(
                    'Define quantos segundos o bot espera você parar de digitar antes de responder.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              );
            },
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
    setState(() => _debounceSeconds = temp);
    await _saveDebounce();
  }

  Future<void> _addScheduleSlot() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Adicionar horário'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Horário',
              hintText: 'Ex: Hoje 18:00',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final value = ctrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _scheduleSlots.add(value);
    });
    _scheduleLeadsSave();
  }

  Future<void> _connectGoogleCalendar() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Use o botão do Google para conectar no navegador.')),
      );
      return;
    }
    await _ensureGoogleInit();
    if (_calendarLoading) return;
    setState(() => _calendarLoading = true);

    try {
      final account =
          await _googleSignIn.authenticate(scopeHint: _googleCalendarScopes);

      final serverAuth = await account.authorizationClient
          .authorizeServer(_googleCalendarScopes);
      if (serverAuth == null || serverAuth.serverAuthCode.isEmpty) {
        setState(() => _calendarLoading = false);
        throw Exception('Não foi possível obter autorização do Google.');
      }

      final res = await FirebaseFunctions.instance
          .httpsCallable('connectGoogleCalendar')
          .call({
        'empresaId': widget.empresaId,
        'authCode': serverAuth.serverAuthCode,
        'redirectUri': 'postmessage',
      });

      final data = (res.data as Map?) ?? {};
      setState(() {
        _calendarConnected = true;
        _calendarEmail = data['email']?.toString() ?? account.email;
        _calendarDisplayName =
            data['displayName']?.toString() ?? account.displayName;
        _calendarPhotoUrl = account.photoUrl;
        _calendarLoading = false;
      });
    } catch (e) {
      setState(() => _calendarLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao conectar Google Agenda: $e')),
      );
    }
  }

  Future<void> _disconnectGoogleCalendar() async {
    if (_calendarLoading) return;
    setState(() => _calendarLoading = true);

    try {
      await _googleSignIn.disconnect();
      await FirebaseFunctions.instance
          .httpsCallable('disconnectGoogleCalendar')
          .call({'empresaId': widget.empresaId});

      setState(() {
        _calendarConnected = false;
        _calendarEmail = null;
        _calendarDisplayName = null;
        _calendarPhotoUrl = null;
        _calendarLoading = false;
      });
    } catch (e) {
      setState(() => _calendarLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao desconectar Google Agenda: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Agent Settings: ${widget.agentName}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Agent Settings: ${widget.agentName}')),
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
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Agent Settings: ${widget.agentName}'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Identidade'),
              Tab(text: 'Negócio'),
              Tab(text: 'Atendimento (Leads/Vendas)'),
              Tab(text: 'Treinamento'),
              Tab(text: 'Integrações'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // IDENTIDADE
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
                    labelText: 'Comportamento / diretrizes',
                    border: const OutlineInputBorder(),
                    hintText: 'Ex: Seja objetivo, use bullets, não invente, etc.',
                    helperText: '${_behaviorLen.toString()}/$_maxBehavior',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar identidade'),
                ),
              ],
            ),

            // NEGÓCIO
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
                    labelText: 'Empresa ou produto',
                    border: const OutlineInputBorder(),
                    helperText: '${_jobNameLen.toString()}/$_maxJobName',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _jobSiteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Site oficial',
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
                    labelText: 'Descrição do negócio',
                    border: const OutlineInputBorder(),
                    helperText: '${_jobDescLen.toString()}/$_maxJobDesc',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saveWork,
                  icon: const Icon(Icons.save),
                  label: const Text('Salvar negócio'),
                ),
              ],
            ),

            // ATENDIMENTO (LEADS / VENDAS)
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status do atendente',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text('Atendente de IA (Leads)'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Ativo'),
                            const SizedBox(width: 8),
                            Switch(
                              value: _leadsActive,
                              onChanged: (v) {
                                setState(() => _leadsActive = v);
                                _scheduleLeadsSave(immediate: true);
                              },
                            ),
                            const SizedBox(width: 8),
                            const Text('Pausado'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Quando pausado, o bot não responde novos leads.',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Tempo de espera (debounce): ${_debounceSeconds.toInt()}s',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            TextButton(
                              onPressed: _openDebounceDialog,
                              child: const Text('Ajustar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Primeira mensagem (boas-vindas)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _openingMessageCtrl,
                          minLines: 3,
                          maxLines: 8,
                          maxLength: 1000,
                          onChanged: (_) => _scheduleLeadsSave(),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText:
                                'Oi! Aqui é a IA da IO Marketing Digital'
                                'Me conta rapidinho: qual é o momento da sua empresa e o que você está buscando no marketing?',
                          ),
                        ),
                        SwitchListTile(
                          value: _sendOpeningAuto,
                          onChanged: (v) {
                            setState(() => _sendOpeningAuto = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text(
                              'Enviar automaticamente na primeira mensagem'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Perguntas obrigatórias (Qualificação)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Essas perguntas definem se o lead é quente e aceleram a call.',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _q1Ctrl,
                          onChanged: (_) => _scheduleLeadsSave(),
                          decoration: const InputDecoration(
                            labelText: 'Pergunta 1',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _q2Ctrl,
                          onChanged: (_) => _scheduleLeadsSave(),
                          decoration: const InputDecoration(
                            labelText: 'Pergunta 2',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _q3Ctrl,
                          onChanged: (_) => _scheduleLeadsSave(),
                          decoration: const InputDecoration(
                            labelText: 'Pergunta 3',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 6),
                        CheckboxListTile(
                          value: _askBudget,
                          onChanged: (v) {
                            setState(() => _askBudget = v ?? false);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Perguntar orçamento disponível'),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_askBudget) ...[
                          const SizedBox(height: 6),
                          TextField(
                            controller: _q4Ctrl,
                            onChanged: (_) => _scheduleLeadsSave(),
                            decoration: const InputDecoration(
                              labelText: 'Pergunta 4',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Regras de fit (quente / médio / frio)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _fitHighCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => _scheduleLeadsSave(),
                          decoration: const InputDecoration(
                            labelText: 'FIT ALTO a partir de:',
                            helperText:
                                'Se o lead estiver acima disso, vira prioridade.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _fitMediumCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => _scheduleLeadsSave(),
                          decoration: const InputDecoration(
                            labelText: 'FIT MÉDIO a partir de:',
                            helperText:
                                'Abaixo disso, tende a cair como Lead Frio / Nutrição.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Sinais de dor clara',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _painSignals.keys.map((label) {
                            return FilterChip(
                              label: Text(label),
                              selected: _painSignals[label] == true,
                              onSelected: (v) {
                                setState(() => _painSignals[label] = v);
                                _scheduleLeadsSave();
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Interesse mínimo aceitável',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _minInterests.keys.map((label) {
                            return FilterChip(
                              label: Text(label),
                              selected: _minInterests[label] == true,
                              onSelected: (v) {
                                setState(() => _minInterests[label] = v);
                                _scheduleLeadsSave();
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Transferência para humano (alertar comercial)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text('Chamar humano quando:'),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          value: _callHumanOnFitHigh,
                          onChanged: (v) {
                            setState(() => _callHumanOnFitHigh = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Lead é FIT ALTO'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _callHumanOnPricing,
                          onChanged: (v) {
                            setState(() => _callHumanOnPricing = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Pediu valores'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _callHumanOnProposal,
                          onChanged: (v) {
                            setState(() => _callHumanOnProposal = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Pediu proposta'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _callHumanOnMeeting,
                          onChanged: (v) {
                            setState(() => _callHumanOnMeeting = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Pediu reunião / call'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _callHumanOnLongAudio,
                          onChanged: (v) {
                            setState(() => _callHumanOnLongAudio = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Mandou áudio longo'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _callHumanOnAskSomeone,
                          onChanged: (v) {
                            setState(() => _callHumanOnAskSomeone = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Quero falar com alguém?'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _callHumanOnReferral,
                          onChanged: (v) {
                            setState(() => _callHumanOnReferral = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Indicação / já conhece a empresa'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          value: _longAudioSeconds,
                          items: _longAudioOptions
                              .map((v) => DropdownMenuItem(
                                    value: v,
                                    child: Text('${v}s'),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _longAudioSeconds = v ?? 60);
                            _scheduleLeadsSave();
                          },
                          decoration: const InputDecoration(
                            labelText: 'O que é áudio longo?',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _transferMessageCtrl,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (_) => _scheduleLeadsSave(),
                          decoration: const InputDecoration(
                            labelText: 'Mensagem ao transferir',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Agendamento autom?tico',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          value: _scheduleEnabled,
                          onChanged: (v) {
                            setState(() => _scheduleEnabled = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Ativar agendamento'),
                          subtitle: const Text(
                            'Quando ativo, o agente pode sugerir hor?rios e agendar automaticamente na agenda conectada.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Follow-up automático',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          value: _followupEnabled,
                          onChanged: (v) {
                            setState(() => _followupEnabled = v);
                            _scheduleLeadsSave();
                          },
                          title: const Text('Ativar follow-ups'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_followupEnabled) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _followup1,
                            items: _followup1Options
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              setState(() => _followup1 = v ?? '24h');
                              _scheduleLeadsSave();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Follow-up 1',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: _followup2,
                            items: _followup2Options
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              setState(() => _followup2 = v ?? '48h');
                              _scheduleLeadsSave();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Follow-up 2',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: _followup3,
                            items: _followup3Options
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              setState(() => _followup3 = v ?? '7 dias');
                              _scheduleLeadsSave();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Recuperação',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _followupMsg1Ctrl,
                            minLines: 2,
                            maxLines: 4,
                            onChanged: (_) => _scheduleLeadsSave(),
                            decoration: const InputDecoration(
                              labelText: 'Texto 1',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _followupMsg2Ctrl,
                            minLines: 2,
                            maxLines: 4,
                            onChanged: (_) => _scheduleLeadsSave(),
                            decoration: const InputDecoration(
                              labelText: 'Texto 2',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _followupMsg3Ctrl,
                            minLines: 2,
                            maxLines: 4,
                            onChanged: (_) => _scheduleLeadsSave(),
                            decoration: const InputDecoration(
                              labelText: 'Texto 3',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Configurações técnicas (GPT Maker)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: false,
                          onChanged: null,
                          title: const Text('Permitir transbordo humano'),
                          subtitle: const Text('Em breve'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _enabledEmoji,
                          onChanged: (v) {
                            setState(() => _enabledEmoji = v);
                            _saveSettings(showSnackBar: false);
                          },
                          title: const Text('Usar emojis'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: false,
                          onChanged: null,
                          title: const Text('Dividir respostas longas'),
                          subtitle: const Text('Em breve'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _limitSubjects,
                          onChanged: (v) {
                            setState(() => _limitSubjects = v);
                            _saveSettings(showSnackBar: false);
                          },
                          title: const Text('Restringir temas'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: (_prefferModel != null &&
                                  _models.contains(_prefferModel))
                              ? _prefferModel
                              : null,
                          items: _models.map((m) {
                            return DropdownMenuItem(
                              value: m,
                              child: Text(_modelLabel(m)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            setState(() => _prefferModel = v);
                            _saveSettings(showSnackBar: false);
                          },
                          decoration: const InputDecoration(
                            labelText: 'Modelo preferido (com custo)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _saveSettings,
                          icon: const Icon(Icons.save),
                          label: const Text('Salvar configurações (GPT Maker)'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // TREINAMENTO (somente texto)
            _TrainingTab(
              empresaId: widget.empresaId,
              phoneId: widget.phoneId,
              agentId: widget.agentId,
            ),

            // INTEGRA??ES
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Integra??es',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Google Agenda',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Conecte a agenda da empresa para permitir agendamentos autom?ticos.',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        if (_calendarConnected) ...[
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.grey.shade200,
                                child: (_calendarPhotoUrl != null &&
                                        _calendarPhotoUrl!.isNotEmpty)
                                    ? ClipOval(
                                        child: Image.network(
                                          _calendarPhotoUrl!,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) {
                                            return const Icon(
                                                Icons.calendar_today);
                                          },
                                        ),
                                      )
                                    : const Icon(Icons.calendar_today),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _calendarDisplayName?.isNotEmpty == true
                                          ? _calendarDisplayName!
                                          : 'Conta conectada',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    if (_calendarEmail?.isNotEmpty == true)
                                      Text(
                                        _calendarEmail!,
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Conectado',
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _calendarLoading
                                      ? null
                                      : _disconnectGoogleCalendar,
                                  child: const Text('Desconectar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _calendarLoading
                                      ? null
                                      : _connectGoogleCalendar,
                                  child: const Text('Trocar conta'),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          if (kIsWeb)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _calendarLoading
                                    ? null
                                    : _startGoogleCalendarWebFlow,
                                icon: const Icon(Icons.login),
                                label: const Text('Conectar com Google'),
                              ),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _calendarLoading
                                    ? null
                                    : _connectGoogleCalendar,
                                icon: const Icon(Icons.login),
                                label: const Text('Conectar com Google'),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
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
