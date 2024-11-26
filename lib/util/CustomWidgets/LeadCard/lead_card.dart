import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class LeadCard extends StatefulWidget {
  final Map<String, dynamic> leadData;
  final Function(Map<String, dynamic>) onTap;
  final Function(String newStatus) onStatusChanged;
  final Color statusColor; // Novo parâmetro para cor do status

  const LeadCard({
    Key? key,
    required this.leadData,
    required this.onTap,
    required this.onStatusChanged,
    required this.statusColor, // Inclua o novo parâmetro no construtor
  }) : super(key: key);

  @override
  _LeadCardState createState() => _LeadCardState();
}

class _LeadCardState extends State<LeadCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  late Color _statusColor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _statusColor = widget.statusColor; // Inicialize com o valor recebido do widget pai

    _controller.forward(); // Começa a animação assim que o widget é exibido
  }

  @override
  void didUpdateWidget(covariant LeadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Atualize a cor do status quando o widget pai mudar
    if (oldWidget.statusColor != widget.statusColor) {
      setState(() {
        _statusColor = widget.statusColor;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'aguardando':
        return Colors.grey;
      case 'atendendo':
        return Colors.blue;
      case 'venda':
        return Colors.green;
      case 'recusado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showStatusSelectionDialog(
      BuildContext context,
      String leadId,
      String empresaId,
      String campaignId,
      Function(String) onStatusChanged,
      ) {
    final statusOptions = ['Aguardando', 'Atendendo', 'Venda', 'Recusado'];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          backgroundColor: Theme.of(context).colorScheme.background,
          title: Text(
            'Selecionar Status',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSecondary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: statusOptions.map((status) {
              return ListTile(
                title: Text(
                  status,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(status),
                ),
                onTap: () async {
                  try {
                    await FirebaseFirestore.instance
                        .collection('empresas')
                        .doc(empresaId)
                        .collection('campanhas')
                        .doc(campaignId)
                        .collection('leads')
                        .doc(leadId)
                        .update({'status': status});
                    Navigator.of(context).pop(); // Fecha o popup
                    onStatusChanged(status); // Atualiza o status local
                  } catch (e) {
                    showErrorDialog(context, 'Erro ao alterar o status: $e', 'Erro');
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _openWhatsAppWithMessage(String phoneNumber, String empresaId,
      String campaignId, String leadId) async {
    try {
      // Busca a mensagem padrão da campanha
      final campaignDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campaignId)
          .get();

      if (!campaignDoc.exists) {
        showErrorDialog(context, 'Campanha não encontrada.', 'Erro');
        return;
      }

      // Obtém a mensagem padrão da campanha
      String message = campaignDoc.data()?['mensagem_padrao'] ?? '';

      // Busca o lead pelo ID correto
      print('Buscando lead com ID: $leadId');
      final leadDoc = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campaignId)
          .collection('leads')
          .doc(leadId) // Certifique-se de passar o leadId aqui
          .get();

      if (!leadDoc.exists) {
        showErrorDialog(context, 'Lead não encontrado.', 'Erro');
        return;
      }

      // Processa o nome do cliente (primeiro nome e nome completo)
      String? nomeClienteCompleto = leadDoc.data()?['nome'];
      String? nomeCliente = nomeClienteCompleto?.split(' ')?.first;

      // Dados do usuário logado
      final user = FirebaseAuth.instance.currentUser;
      String? userName;
      String? empresaName;

      if (user != null) {
        // Verifica se o usuário está na coleção 'users'
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          userName = userDoc.data()?['name']?.split(' ')?.first;

          // Busca o nome da empresa associada ao usuário (caso 'createdBy' esteja definido)
          final createdBy = userDoc.data()?['createdBy'];
          if (createdBy != null) {
            final empresaDoc = await FirebaseFirestore.instance
                .collection('empresas')
                .doc(createdBy)
                .get();
            empresaName = empresaDoc.data()?['NomeEmpresa'];
          }
        } else {
          // Caso o usuário esteja na coleção 'empresas'
          final empresaDoc = await FirebaseFirestore.instance
              .collection('empresas')
              .doc(user.uid)
              .get();
          if (empresaDoc.exists) {
            userName = empresaDoc.data()?['NomeEmpresa']?.split(' ')?.first;
            empresaName = empresaDoc.data()?['NomeEmpresa'];
          }
        }
      }

      // Substitui as variáveis na mensagem
      message = message
          .replaceAll('{nome_cliente}', nomeCliente ?? '')
          .replaceAll('{nome_cliente_completo}', nomeClienteCompleto ?? '')
          .replaceAll('{nome_usuario}', userName ?? '')
          .replaceAll('{nome_empresa}', empresaName ?? '');

      // Limpa o número de telefone
      final cleanedPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');

      if (cleanedPhone.length >= 10) {
        // URL para abrir o WhatsApp com a mensagem
        final url = kIsWeb
            ? 'https://wa.me/$cleanedPhone?text=${Uri.encodeComponent(message)}'
            : 'whatsapp://send?phone=$cleanedPhone&text=${Uri.encodeComponent(message)}';

        if (await canLaunch(url)) {
          await launch(url);
        } else {
          showErrorDialog(
            context,
            'Não foi possível abrir o WhatsApp. Verifique se o WhatsApp está instalado ou tente novamente mais tarde!',
            'Atenção',
          );
        }
      } else {
        showErrorDialog(
          context,
          'Número de telefone inválido.',
          'Atenção',
        );
      }
    } catch (e) {
      showErrorDialog(
        context,
        'Erro ao abrir o WhatsApp: $e',
        'Erro',
      );
    }
  }


  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    final dateTime = (timestamp as Timestamp).toDate();
    return 'Entrou em ${DateFormat('dd/MM/yyyy').format(dateTime)} às ${DateFormat('HH:mm').format(dateTime)}';
  }

  @override
  Widget build(BuildContext context) {
    final String formattedDate = _formatTimestamp(widget.leadData['timestamp']);
    final String status = widget.leadData['status'] ?? 'Aguardando';

    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: () => widget.onTap(widget.leadData),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  color: Theme.of(context).colorScheme.shadow,
                  offset: Offset(0, 0),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status do Lead
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 12),
                    child: GestureDetector(
                      onTap: () => _showStatusSelectionDialog(
                        context,
                        widget.leadData['leadId'] ?? '',
                        widget.leadData['empresaId'] ?? '',
                        widget.leadData['campaignId'] ?? '',
                        widget.onStatusChanged,
                      ),
                      child: Chip(
                        label: Text(
                          widget.leadData['status'] ?? 'Aguardando',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        backgroundColor: _statusColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                          side: BorderSide(
                            color: _statusColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Data de Entrada
                  if (formattedDate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 1, horizontal: 12),
                      child: Text(
                        formattedDate,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                    ),
                  // Nome do Lead
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 1, horizontal: 12),
                    child: Text(
                      widget.leadData['nome'] ?? 'Nome não disponível',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ),
                  // Informações do WhatsApp
                  if (widget.leadData.containsKey('whatsapp') &&
                      widget.leadData['whatsapp'] != null)
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Row(
                        children: [
                          IconButton(
                            icon: FaIcon(
                              FontAwesomeIcons.whatsapp,
                              color: Theme.of(context).colorScheme.onBackground,
                              size: 25,
                            ),
                            onPressed: () {
                              final phoneNumber = widget.leadData['whatsapp'] as String?;
                              if (phoneNumber != null) {
                                _openWhatsAppWithMessage(
                                  phoneNumber,
                                  widget.leadData['empresaId'] ?? '',
                                  widget.leadData['campaignId'] ?? '',
                                  widget.leadData['leadId'] ?? '',
                                );
                              } else {
                                showErrorDialog(context, 'Número de telefone inválido.', 'Erro');
                              }
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              final phoneNumber = widget.leadData['whatsapp'] as String?;
                              if (phoneNumber != null) {
                                _openWhatsAppWithMessage(
                                  phoneNumber,
                                  widget.leadData['empresaId'] ?? '',
                                  widget.leadData['campaignId'] ?? '',
                                  widget.leadData['leadId'] ?? '',
                                );
                              } else {
                                showErrorDialog(context, 'Número de telefone inválido.', 'Erro');
                              }
                            },
                            child: Text(
                              widget.leadData['whatsapp'] ?? '',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}