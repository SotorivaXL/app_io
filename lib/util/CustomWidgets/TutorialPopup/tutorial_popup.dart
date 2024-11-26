import 'dart:async';
import 'package:flutter/material.dart';

class TutorialPopup extends StatefulWidget {
  final VoidCallback onComplete;

  const TutorialPopup({Key? key, required this.onComplete}) : super(key: key);

  @override
  _TutorialPopupState createState() => _TutorialPopupState();
}

class _TutorialPopupState extends State<TutorialPopup> {
  int currentStep = 0;
  bool canProceed = false;
  late Timer timer;

  late List<Map<String, String>> tutorialSteps;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Inicializa os passos do tutorial com base no tema
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    tutorialSteps = [
      {
        "title": "Bem-vindo ao IO Connect",
        "image": isDarkTheme
            ? "assets/images/icons/logoDark.png"
            : "assets/images/icons/logoLight.png",
        "description": "Explore seus resultados de campanhas de tráfego e acompanhe seus leads em um só lugar. 🚀\n\nVamos guiá-lo para aproveitar ao máximo seu novo painel. Clique em “Próximo” para começar o tutorial!"
      },
      {
        "title": "Filtrando Leads por Campanha",
        "image": "assets/images/tutotial/Filtros.jpg",
        "description": "Clique no ícone de megafone 📣 localizado no canto esquerdo da tela para organizar seus leads de acordo com a campanha de origem. Encontre rapidamente os resultados das ações que mais importam para você!"
      },
      {
        "title": "Filtrando Leads por Status",
        "image": "assets/images/tutotial/Filtros.jpg",
        "description": "Clique no ícone de funil 🔽 localizado no canto direito da tela para filtrar seus leads pelo status. Isso facilita o acompanhamento e gestão dos contatos em diferentes etapas do funil de vendas!"
      },
      {
        "title": "Atualize o Status do Lead com Facilidade",
        "image": "assets/images/tutotial/Status.jpg",
        "description": "Clique na etiqueta de status do lead para abrir um popup. Nele, você poderá selecionar um novo status e acompanhar o progresso de cada lead de forma personalizada. Simples, rápido e eficiente!"
      },
      {
        "title": "Veja Todas as Informações do Lead",
        "image": "assets/images/tutotial/Detalhes.jpg",
        "description": "Ao clicar no lead, um popup será aberto exibindo todas as informações preenchidas no formulário. Além disso, você encontrará a etiqueta de status, que pode ser clicada para abrir um novo popup e atualizar o status do lead rapidamente. Tudo em um só lugar, prático e eficiente!"
      },
      {
        "title": "Converse com Seus Leads no WhatsApp",
        "image": "assets/images/tutotial/WhatsApp.jpg",
        "description": "Clique no ícone do WhatsApp 📲 ou diretamente no número de telefone exibido no lead para abrir o aplicativo e iniciar uma conversa com seu cliente. Conecte-se de forma instantânea e pratique a comunicação eficiente!"
      },
    ];
  }

  void _startTimer() {
    canProceed = false;
    timer = Timer(const Duration(seconds: 10), () {
      setState(() {
        canProceed = true;
      });
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  void _nextStep() {
    if (currentStep < tutorialSteps.length - 1) {
      setState(() {
        currentStep++;
        _startTimer();
      });
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = tutorialSteps[currentStep];
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                step['title']!,
                style: TextStyle(
                  fontFamily: 'Branding SF',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSecondary
                ),
              ),
              const SizedBox(height: 20),
              Image.asset(
                step['image']!,
                scale: 2,
              ),
              const SizedBox(height: 40),
              Text(
                step['description']!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary
                ),
              ),
              const SizedBox(height: 16),
              if (canProceed)
                ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    Theme.of(context).colorScheme.primary,
                    foregroundColor:
                    Theme.of(context).colorScheme.outline,
                  ),
                  child: Text(currentStep < tutorialSteps.length - 1
                      ? "Próximo"
                      : "Concluir",
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}