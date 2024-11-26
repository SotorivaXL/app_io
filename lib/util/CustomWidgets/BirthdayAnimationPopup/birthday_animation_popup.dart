import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';

class BirthdayAnimationPopup extends StatefulWidget {
  final VoidCallback onDismiss;

  const BirthdayAnimationPopup({Key? key, required this.onDismiss})
      : super(key: key);

  @override
  _BirthdayAnimationPopupState createState() => _BirthdayAnimationPopupState();
}

class _BirthdayAnimationPopupState extends State<BirthdayAnimationPopup> {
  String? _userName;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    String? userName;

    try {
      // Busca na coleção `users`
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        userName = userDoc.data()?['name'];
      } else {
        // Busca na coleção `empresas` caso não esteja em `users`
        final empresaDoc = await FirebaseFirestore.instance
            .collection('empresas')
            .doc(uid)
            .get();
        if (empresaDoc.exists) {
          userName = empresaDoc.data()?['NomeEmpresa'];
        }
      }

      // Atualiza o estado com o nome do usuário
      if (userName != null) {
        setState(() {
          _userName = userName;
        });
      } else {
        setState(() {
          _userName = 'Usuário';
        });
      }
    } catch (e) {
      print('Erro ao buscar nome do usuário: $e');
      setState(() {
        _userName = 'Usuário';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Fundo com confetti cobrindo toda a tela
        Positioned.fill(
          child: Lottie.asset(
            'assets/animations/confetti.json',
            fit: BoxFit.cover,
            repeat: true,
          ),
        ),
        // Fundo com balloons cobrindo toda a tela
        Positioned.fill(
          child: Lottie.asset(
            'assets/animations/balloons.json',
            fit: BoxFit.cover,
            repeat: true,
          ),
        ),
        // Popup de aniversário com gradiente
        Center(
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Theme.of(context).colorScheme.background,
                    Theme.of(context).colorScheme.background,
                  ],
                  stops: [0.1, 0.75, 1.0], // Preto ocupa apenas 5% da altura
                ),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Animação principal como GIF
                      SizedBox(
                        height: 150,
                        child: Image.asset(
                          'assets/animations/congratulations.gif',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Nome do usuário como título
                      Text(
                        '🎉 Parabéns pelo seu grande dia $_userName! 🎂',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Hoje é um dia especial, e queremos celebrá-lo com você! 🎉 Que seu aniversário seja repleto de alegrias e conquistas.\n\n🎈 A equipe IO Marketing Digital deseja um ano incrível, cheio de sorrisos e realizações. Obrigado por estar conosco! 🥳\n\nAproveite cada momento do seu dia especial! 🎁✨',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: widget.onDismiss,
                        child: Text(
                          'Obrigado!',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Confetti sobre o popup
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true, // Evita interferência na interação do popup
            child: Lottie.asset(
              'assets/animations/confetti.json', // Animação de confetti
              fit: BoxFit.cover,
              repeat: true,
            ),
          ),
        ),
        // Balloons sobre o popup
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true, // Evita interferência na interação do popup
            child: Lottie.asset(
              'assets/animations/balloons.json', // Animação de balloons
              fit: BoxFit.cover,
              repeat: true,
            ),
          ),
        ),
      ],
    );
  }
}