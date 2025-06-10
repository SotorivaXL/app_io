import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_io/features/screens/crm/chat_detail.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';


class WhatsAppChats extends StatefulWidget {
  const WhatsAppChats({Key? key}) : super(key: key);

  @override
  State<WhatsAppChats> createState() => _WhatsAppChatsState();
}

/// Só duas abas agora
enum ChatTab { novos, atendendo }

class _WhatsAppChatsState extends State<WhatsAppChats> {
  ChatTab _currentTab = ChatTab.novos;
  String _searchTerm = '';
  final TextEditingController _phoneController = TextEditingController();
  String _countryCode = '+55';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ITEM DE LISTA
  // ---------------------------------------------------------------------------
  Widget _buildChatItem(
      BuildContext context, {
        required String chatId,
        required String name,
        required String lastMessage,
        required String lastMessageTime,
        required int unreadCount,
        required String contactPhoto,
      }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () async {
        // marca como aberto / zera contador
        await FirebaseFirestore.instance
            .collection('whatsappChats')
            .doc(chatId)
            .set(
          {'opened': true, 'unreadCount': 0},
          SetOptions(merge: true),
        );

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetail(
              chatId: chatId,
              chatName: name,
              contactPhoto: contactPhoto,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // avatar + ícone
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.inverseSurface,
                  backgroundImage:
                  contactPhoto.isNotEmpty ? NetworkImage(contactPhoto) : null,
                  child: contactPhoto.isEmpty
                      ? Text(
                    name
                        .trim()
                        .split(' ')
                        .map((e) => e[0])
                        .take(2)
                        .join()
                        .toUpperCase(),
                    style: TextStyle(
                        color: theme.colorScheme.outline, fontSize: 14),
                  )
                      : null,
                ),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: FaIcon(FontAwesomeIcons.whatsapp,
                          size: 10, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // nome + última mensagem
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSecondary.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            // hora + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lastMessageTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSecondary.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 6),
                if (_currentTab != ChatTab.novos && unreadCount > 0)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$unreadCount',
                      style: TextStyle(
                        color: theme.colorScheme.onBackground,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ------------ LINHA DE ABAS ------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: StreamBuilder<QuerySnapshot>(
                // agora sem filtro – recebemos todos
                stream: FirebaseFirestore.instance
                    .collection('whatsappChats')
                    .snapshots(),
                builder: (context, snap) {
                  int novosCount = 0;

                  if (snap.hasData) {
                    // conta chats cujo 'opened' NÃO é true (false ou inexistente)
                    novosCount = snap.data!.docs.where((d) {
                      final map = d.data() as Map<String, dynamic>;
                      return (map['opened'] as bool?) != true;
                    }).length;
                  }

                  return Row(
                    children: [
                      _buildTab('Novos', ChatTab.novos, badge: novosCount),
                      const SizedBox(width: 8),
                      _buildTab('Atendendo', ChatTab.atendendo),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: Theme.of(context).colorScheme.onSecondary,
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        color: Theme.of(context).colorScheme.onSecondary,
                        onPressed: () {},
                      ),
                    ],
                  );
                },
              ),
            ),

            // ------------ CAMPO DE BUSCA ------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Icon(Icons.search,
                              color:
                              theme.colorScheme.onBackground.withOpacity(0.5)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (v) =>
                                  setState(() => _searchTerm = v.trim().toLowerCase()),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: 'Buscar atendimento',
                                hintStyle: TextStyle(
                                  color: theme.colorScheme.onBackground
                                      .withOpacity(0.5),
                                ),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.filter_alt_outlined),
                    color: theme.colorScheme.onSecondary,
                    splashRadius: 22,
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.swap_vert),
                    color: theme.colorScheme.onSecondary,
                    splashRadius: 22,
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    color: theme.colorScheme.onSecondary,
                    splashRadius: 22,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ------------ LISTA ------------
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('whatsappChats')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  List<QueryDocumentSnapshot> docs = snap.data!.docs;

                  bool _isOpened(QueryDocumentSnapshot d) {
                    final map = d.data() as Map<String, dynamic>;
                    return (map['opened'] as bool?) ?? false;   // se não existir ⇒ false
                  }

                  // filtragem por aba
                  if (_currentTab == ChatTab.novos) {
                    docs = docs.where((d) => !_isOpened(d)).toList();
                  } else {
                    docs = docs.where(_isOpened).toList(); // Atendendo
                  }

                  // filtro por texto
                  docs = docs.where((d) {
                    final name =
                    (d['name'] as String? ?? '').toLowerCase();
                    return name.contains(_searchTerm);
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'Não há novos atendimentos',
                        style: TextStyle(
                            color: theme.colorScheme.onSecondary, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      final data = docs[i].data() as Map<String, dynamic>;

                      final chatId = data['chatId'] as String? ?? '';
                      final name = data['name'] as String? ?? chatId;
                      final lastMessage = data['lastMessage'] as String? ?? '';
                      final unread = data['unreadCount'] as int? ?? 0;
                      final contactPhoto = data['contactPhoto'] as String? ?? '';

                      // formata horário
                      String lastMsgTime = '';
                      final ts = data['timestamp'];
                      if (ts is Timestamp) {
                        final date = ts.toDate();
                        final now  = DateTime.now();

                        final bool sameDay =
                            date.year == now.year && date.month == now.month && date.day == now.day;

                        if (sameDay) {
                          // Ex.: 14:05
                          lastMsgTime = '${date.hour.toString().padLeft(2, '0')}:'
                              '${date.minute.toString().padLeft(2, '0')}';
                        } else {
                          // Ex.: 09/06
                          lastMsgTime = '${date.day.toString().padLeft(2, '0')}/'
                              '${date.month.toString().padLeft(2, '0')}';
                        }
                      }

                      return _buildChatItem(
                        context,
                        chatId: chatId,
                        name: name,
                        lastMessage: lastMessage,
                        lastMessageTime: lastMsgTime,
                        unreadCount: unread,
                        contactPhoto: contactPhoto,
                      );
                    },
                  );
                },
              ),
            ),

            // ==================== RODAPÉ – TELEFONE + BOTÃO CONVERSAR ====================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // ---------- Dropdown do país ----------
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary,                      // fundo próprio
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _countryCode,
                        alignment: Alignment.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSecondary,
                        ),
                        icon: Icon(Icons.arrow_drop_down,
                            color: theme.colorScheme.onBackground.withOpacity(0.5)),
                        items: const [
                          DropdownMenuItem(value: '+55', child: Center(child: Text('+55'))),
                          DropdownMenuItem(value: '+1', child: Center(child: Text('+1'))),
                        ],
                        onChanged: (v) => setState(() => _countryCode = v ?? '+55'),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ---------- Campo de telefone ----------
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: theme.colorScheme.onSecondary),
                        decoration: InputDecoration(
                          hintText: '(00) 0000-0000',
                          hintStyle: TextStyle(
                              color: theme.colorScheme.onBackground.withOpacity(0.5)),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ---------- Botão "Conversar" ----------
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,                         // texto branco
                      padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text(
                      'Conversar',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // ========================= TAB WIDGET =========================
  Widget _buildTab(String label, ChatTab tab, {int badge = 0}) {
    final theme    = Theme.of(context);
    final selected = _currentTab == tab;

    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary
              : theme.colorScheme.secondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,           // <= não ocupar espaço extra
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onBackground,
              ),
            ),

            // ───── badge ─────
            if (badge > 0) ...[
              const SizedBox(width: 8),             // espaço maior
              Container(
                width: 20,                          // largura fixa
                height: 20,                         // altura igual → círculo perfeito
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,           // deixa redondo
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    height: 1,                      // centraliza verticalmente
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}