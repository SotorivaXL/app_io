import 'dart:async';
import 'dart:io' show Platform; // <-- Adicionado
import 'package:flutter/foundation.dart' show kIsWeb; // <-- Adicionado
import 'package:flutter/material.dart';

// Definição da classe TutorialStep
class TutorialStep {
  final String title;
  final String image;
  final String? description;
  final double? imageWidth;
  final double? imageHeight;

  TutorialStep({
    required this.title,
    required this.image,
    this.description,
    this.imageWidth,
    this.imageHeight,
  });

  @override
  String toString() {
    return 'TutorialStep(title: $title, image: $image, description: $description, imageWidth: $imageWidth, imageHeight: $imageHeight)';
  }
}

class TutorialPopup extends StatefulWidget {
  final VoidCallback onComplete;

  const TutorialPopup({Key? key, required this.onComplete}) : super(key: key);

  @override
  _TutorialPopupState createState() => _TutorialPopupState();
}

class _TutorialPopupState extends State<TutorialPopup> {
  int currentStep = 0;

  // Tornar tutorialSteps nullable
  List<TutorialStep>? tutorialSteps;

  // Utilize 'isDesktp' para a verificação
  bool get isDesktp {
    try {
      // Quando não estiver rodando na Web, verifique se a plataforma é desktop
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        return true;
      }
    } catch (_) {
      // Caso falhe, retorna falso
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // Não é necessário iniciar o timer aqui
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Inicializa os passos do tutorial com base no tema
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    tutorialSteps = [
      TutorialStep(
        title: "Bem-vindo ao",
        image: isDarkTheme
            ? "assets/images/icons/logoDark.png"
            : "assets/images/icons/logoLight.png",
        description: "Explore os recursos incríveis da nossa plataforma!",
        imageWidth: 220,
        imageHeight: 80,
      ),
      TutorialStep(
        title: "Filtrando Leads por Campanha!",
        image: "assets/images/tutorial/Filtros.jpg",
        imageWidth: 500,
        imageHeight: 200,
      ),
      TutorialStep(
        title: "Filtrando Leads por Status!",
        image: "assets/images/tutorial/Filtros.jpg",
        imageWidth: 500,
        imageHeight: 200,
      ),
      TutorialStep(
        title: "Atualize o Status do Lead com praticidade e rapidez!",
        image: "assets/images/tutorial/Status.jpg",
        imageWidth: 500,
        imageHeight: 200,
      ),
      TutorialStep(
        title: "Veja Todas as Informações do Lead!",
        image: "assets/images/tutorial/Detalhes.jpg",
        imageWidth: 500,
        imageHeight: 200,
      ),
      TutorialStep(
        title: "Converse com Seus Leads no WhatsApp!",
        image: "assets/images/tutorial/WhatsApp.jpg",
        imageWidth: 500,
        imageHeight: 200,
      ),
    ];

    // Depuração
    print('Tutorial Steps: $tutorialSteps');
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
      return const Center(child: CircularProgressIndicator());
    }

    // Garantir que currentStep está dentro dos limites da lista
    if (currentStep >= tutorialSteps!.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onComplete();
      });
      return const SizedBox.shrink();
    }

    final step = tutorialSteps![currentStep];
    print('Current Step: $step');

    // AUMENTANDO O TAMANHO DAS IMAGENS
    // Caso queira aumentar também no Web, inclua kIsWeb no if
    final bool isDesktopOrWeb = isDesktp || kIsWeb;
    final double increaseFactor = 1.3; // Ajuste conforme desejar

    final double? finalImageWidth = step.imageWidth != null
        ? (isDesktopOrWeb ? step.imageWidth! * increaseFactor : step.imageWidth!)
        : null;

    final double? finalImageHeight = step.imageHeight != null
        ? (isDesktopOrWeb ? step.imageHeight! * increaseFactor : step.imageHeight!)
        : null;

    return Dialog(
      // Se for web, definimos um padding horizontal maior (como no seu código)
      insetPadding: kIsWeb
          ? const EdgeInsets.symmetric(horizontal: 650, vertical: 24.0)
          : null,
      backgroundColor: Theme.of(context).colorScheme.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Sem constraints
      child: Padding(
        padding: const EdgeInsets.all(35.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho com Título Centralizado
              Center(
                child: Text(
                  step.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Imagem do passo com o tamanho ajustado
              Image.asset(
                step.image,
                width: finalImageWidth,
                height: finalImageHeight,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.error, size: 50, color: Colors.red);
                },
              ),
              const SizedBox(height: 10),
              if (step.description != null)
                Text(
                  step.description!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              if (step.description != null) const SizedBox(height: 25),
              // Botões "Próximo/Concluir" e "Pular Tutorial"
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _skipTutorial,
                    child: Text(
                      'Pular Tutorial',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.outline,
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