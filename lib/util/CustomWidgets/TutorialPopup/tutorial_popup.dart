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

  // Tornar tutorialSteps nullable
  List<Map<String, String>>? tutorialSteps;

  @override
  void initState() {
    super.initState();
    // Não é necessário iniciar o timer aqui, pois estamos removendo o temporizador
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Inicializa os passos do tutorial com base no tema
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    tutorialSteps = [
      {
        "title": "Bem-vindo ao",
        "image": isDarkTheme
            ? "assets/images/icons/logoDark.png"
            : "assets/images/icons/logoLight.png",
      },
      {
        "title": "Filtrando Leads por Campanha",
        "image": "assets/images/tutotial/Filtros.jpg",
      },
      {
        "title": "Filtrando Leads por Status",
        "image": "assets/images/tutotial/Filtros.jpg",
      },
      {
        "title": "Atualize o Status do Lead com Facilidade",
        "image": "assets/images/tutotial/Status.jpg",
      },
      {
        "title": "Veja Todas as Informações do Lead",
        "image": "assets/images/tutotial/Detalhes.jpg",
      },
      {
        "title": "Converse com Seus Leads no WhatsApp",
        "image": "assets/images/tutotial/WhatsApp.jpg",
      },
    ];
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _nextStep() {
    if (currentStep < (tutorialSteps?.length ?? 0) - 1) {
      setState(() {
        currentStep++;
      });
    } else {
      widget.onComplete();
    }
  }

  void _skipTutorial() {
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    // Verificar se tutorialSteps está inicializado
    if (tutorialSteps == null) {
      // Pode mostrar um indicador de carregamento ou retornar um Container vazio
      return const Center(child: CircularProgressIndicator());
    }

    // Garantir que currentStep está dentro dos limites da lista
    if (currentStep >= tutorialSteps!.length) {
      // Se estiver fora dos limites, finalizar o tutorial
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onComplete();
      });
      return const SizedBox.shrink();
    }

    final step = tutorialSteps![currentStep];

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho com Título e Botão "Pular Tutorial"
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      step['title']!,
                      style: TextStyle(
                        fontFamily: 'Branding SF',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Image.asset(
                step['image']!,
                scale: 2,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.error, size: 50, color: Colors.red);
                },
              ),
              const SizedBox(height: 40),
              Text(
                step['description']!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              const SizedBox(height: 16),
              // Botões "Próximo/Concluir" e "Pular Tutorial"
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Botão para pular o tutorial
                  TextButton(
                    onPressed: _skipTutorial,
                    child: Text(
                      'Pular Tutorial',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  // Botão "Próximo" ou "Concluir"
                  ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: Text(
                      currentStep < tutorialSteps!.length - 1
                          ? "Próximo"
                          : "Concluir",
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
