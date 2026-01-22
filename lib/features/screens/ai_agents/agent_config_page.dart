import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AgentConfigPage extends StatefulWidget {
  final String empresaId;
  final String phoneId;
  final String agentId;
  final Map<String, dynamic> initialData;

  const AgentConfigPage({
    super.key,
    required this.empresaId,
    required this.phoneId,
    required this.agentId,
    required this.initialData,
  });

  @override
  State<AgentConfigPage> createState() => _AgentConfigPageState();
}

class _AgentConfigPageState extends State<AgentConfigPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _behaviorController = TextEditingController();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _siteController = TextEditingController();
  final TextEditingController _productDescController = TextEditingController();

  // Estados Visuais
  String _commStyle = 'Normal'; 
  String _workPurpose = 'Vendas';

  // Settings Toggles
  bool _transferHuman = false;
  bool _useEmojis = true;
  bool _signName = false;
  bool _restrictTopics = false;
  bool _splitResponse = false;
  bool _allowReminders = true;
  bool _smartSearch = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Dados iniciais parciais
    _nameController.text = widget.initialData['name'] ?? '';
    _productDescController.text = widget.initialData['description'] ?? '';

    _fetchFullDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _behaviorController.dispose();
    _productNameController.dispose();
    _siteController.dispose();
    _productDescController.dispose();
    super.dispose();
  }

  Future<void> _fetchFullDetails() async {
    setState(() => _isLoading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro: Usuário não está logado no App.')),
        );
      }
      return;
    }

    try {
      final functions = FirebaseFunctions.instance;
      final result = await functions
          .httpsCallable('getGptAgentDetails')
          .call({
            'empresaId': widget.empresaId,
            'phoneId': widget.phoneId,
            'agentId': widget.agentId,
          });

      final data = Map<String, dynamic>.from(result.data);
      final agent = data['agent'] != null ? Map<String, dynamic>.from(data['agent']) : {};
      final settings = data['settings'] != null ? Map<String, dynamic>.from(data['settings']) : {};

      if (mounted) {
        setState(() {
          // Aba Perfil
          _nameController.text = agent['name'] ?? _nameController.text;
          
          // O Prompt geralmente vem com tudo. 
          // DICA: Se quiser, você pode fazer uma lógica aqui para tentar separar
          // o que é comportamento do que é "Contexto do produto", mas é complexo.
          _behaviorController.text = agent['prompt'] ?? agent['behavior'] ?? '';
          
          if (agent['description'] != null) {
             _productDescController.text = agent['description']; 
          }

          // Aba Settings
          _transferHuman = settings['transfer_to_human'] ?? false;
          _useEmojis = settings['use_emojis'] ?? true;
          _signName = settings['sign_name'] ?? false;
          _restrictTopics = settings['restrict_topics'] ?? false;
          _splitResponse = settings['split_messages'] ?? settings['split_response'] ?? false;
          _allowReminders = settings['register_reminders'] ?? true;
          // _smartSearch = settings['smart_search'] ?? false;

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro fetch: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar: $e')),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nome é obrigatório.')));
      return;
    }

    setState(() => _isSaving = true);

    // Preparando o payload
    final payload = {
        'empresaId': widget.empresaId,
        'phoneId': widget.phoneId,
        'agentId': widget.agentId,
        
        'data': {
          'name': _nameController.text,
          'behavior': _behaviorController.text,
          'jobDescription': _productDescController.text,
          // Enviamos estes campos. A Cloud Function vai concatená-los no prompt
          'jobName': _productNameController.text,
          'jobSite': _siteController.text,
        },
        
        'settings': {
          'transferToHuman': _transferHuman,
          'useEmojis': _useEmojis,
          'signName': _signName,
          'restrictTopics': _restrictTopics,
          'splitMessages': _splitResponse,
          'registerReminders': _allowReminders,
          'smartSearch': _smartSearch,
        }
      };

    try {
      await FirebaseFunctions.instance.httpsCallable('updateGptAgent').call(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salvo com sucesso!')),
        );
        Navigator.pop(context, true); // Retorna true para atualizar a lista
      }
    } catch (e) {
      debugPrint("Erro save: $e");
      // Tenta extrair mensagem de erro mais limpa do FirebaseFunctionsException
      String msg = e.toString();
      if (e is FirebaseFunctionsException) {
        msg = e.message ?? e.details.toString();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $msg'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text("Configurar ${_nameController.text}"),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
             Tab(text: "Perfil"),
             Tab(text: "Trabalho"),
             Tab(text: "Configurações"),
          ],
        ),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  child: const Text("Salvar", style: TextStyle(fontWeight: FontWeight.bold)),
                )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildProfileTab(cs),
                _buildWorkTab(cs),
                _buildSettingsTab(cs),
              ],
            ),
    );
  }

  // --- ABA 1: PERFIL ---
  Widget _buildProfileTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Informações pessoais",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: "Nome do agente",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        const Text("Comunicação"),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildSelectableChip("Formal", "Formal", cs),
            const SizedBox(width: 8),
            _buildSelectableChip("Normal", "Normal", cs),
            const SizedBox(width: 8),
            _buildSelectableChip("Descontraída", "Descontraída", cs),
          ],
        ),
        const SizedBox(height: 24),
        const Text("Comportamento:"),
        const SizedBox(height: 4),
        const Text(
            "Descreva um pouco sobre como o agente deve se comportar. (System Prompt)",
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _behaviorController,
          maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "Você é OPI, o suporte e vendedor oficial...",
          ),
        ),
      ],
    );
  }

  Widget _buildSelectableChip(String label, String value, ColorScheme cs) {
    final isSelected = _commStyle == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _commStyle = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? cs.primary : Colors.transparent,
            border: Border.all(
                color: isSelected ? cs.primary : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
                color: isSelected ? cs.onPrimary : Colors.grey.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
        ),
      ),
    );
  }

  // --- ABA 2: TRABALHO ---
  Widget _buildWorkTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Informações sobre trabalho",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 16),
        const Text("Finalidade:"),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPurposeCard("Suporte", Icons.support_agent, "Suporte", cs),
              const SizedBox(width: 8),
              _buildPurposeCard(
                  "Vendas", Icons.shopping_cart_outlined, "Vendas", cs),
              const SizedBox(width: 8),
              _buildPurposeCard(
                  "Uso pessoal", Icons.person_outline, "Pessoal", cs),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _productNameController,
                decoration: const InputDecoration(
                  labelText: "Vende o produto:",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _siteController,
                decoration: const InputDecoration(
                  labelText: "Site oficial: (opcional)",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text("Descreva um pouco sobre ${_productNameController.text}:"),
        const SizedBox(height: 8),
        TextFormField(
          controller: _productDescController,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "Sistema de gestão criado especialmente para...",
          ),
        ),
      ],
    );
  }

  Widget _buildPurposeCard(
      String label, IconData icon, String value, ColorScheme cs) {
    final isSelected = _workPurpose == value;
    final activeColor = const Color(0xFF9747FF); // Roxo visual

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _workPurpose = value),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  size: 28),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold),
              ),
              if (!isSelected)
                Text("Opção para $label",
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  // --- ABA 3: CONFIGURAÇÕES ---
  Widget _buildSettingsTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _buildSwitchTile(
            "Transferir para humano",
            "Habilite para permitir transbordo.",
            _transferHuman,
            (v) => setState(() => _transferHuman = v),
            Icons.swap_horiz),
        const Divider(),
        _buildSwitchTile(
            "Usar Emojis Nas Respostas",
            "Define se o agente pode utilizar emojis.",
            _useEmojis,
            (v) => setState(() => _useEmojis = v),
            Icons.emoji_emotions_outlined),
        const Divider(),
        _buildSwitchTile(
            "Assinar nome do agente",
            "Adiciona assinatura automática.",
            _signName,
            (v) => setState(() => _signName = v),
            Icons.draw_outlined),
        const Divider(),
        _buildSwitchTile(
            "Restringir Temas Permitidos",
            "Agente não fala sobre outros assuntos.",
            _restrictTopics,
            (v) => setState(() => _restrictTopics = v),
            Icons.chat_bubble_outline),
        const Divider(),
        _buildSwitchTile(
            "Dividir resposta em partes",
            "Separa mensagens longas.",
            _splitResponse,
            (v) => setState(() => _splitResponse = v),
            Icons.view_stream_outlined),
        const Divider(),
        _buildSwitchTile(
            "Permitir registrar lembretes",
            "Capacidade de criar lembretes.",
            _allowReminders,
            (v) => setState(() => _allowReminders = v),
            Icons.note_add_outlined),
        const Divider(),
        _buildSwitchTile(
            "Busca inteligente (Beta)",
            "Consulta base de treinamentos.",
            _smartSearch,
            (v) => setState(() => _smartSearch = v),
            Icons.psychology_outlined),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text("Timezone do agente"),
          subtitle: const Text("Escolha o fuso horário"),
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: "GMT-03:00",
              items: const [
                DropdownMenuItem(
                    value: "GMT-03:00", child: Text("(GMT-03:00) Sao Paulo")),
              ],
              onChanged: (v) {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged, IconData icon) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.purple),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      activeColor: const Color(0xFF9747FF),
      onChanged: onChanged,
    );
  }
}