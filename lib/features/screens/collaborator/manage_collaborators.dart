import 'package:app_io/util/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:app_io/features/screens/collaborator/add_collaborators.dart';
import 'package:app_io/features/screens/collaborator/edit_collaborators.dart';
import 'package:app_io/util/services/firestore_service.dart';

class ManageCollaborators extends StatefulWidget {
  @override
  _ManageCollaboratorsState createState() => _ManageCollaboratorsState();
}

class _ManageCollaboratorsState extends State<ManageCollaborators> {
  final FirestoreService _firestoreService = FirestoreService();

  Stream<List<Map<String, dynamic>>> _getUserCollaborators(String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .where('createdBy', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['uid'] = doc.id; // Adiciona o ID do documento (UID) ao map
      return data;
    }).toList());
  }

  @override
  void initState() {
    super.initState();
  }

  void _navigateWithBottomToTopTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0); // Começa de baixo para cima
          const end = Offset.zero;
          const curve = Curves.easeInOut; // Usando easeInOut para uma animação suave

          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          final offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300), // Define a duração da animação
      ),
    );
  }

  Future<void> _deleteCollaborator(String uid) async {
    try {
      // Deleta o colaborador do Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // Deleta o colaborador do Firebase Authentication usando uma Cloud Function
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('deleteUser');
      await callable.call(<String, dynamic>{
        'uid': uid,
      });

      // Notifica o sucesso
      showErrorDialog(context, "Colaborador excluído com sucesso!", "Sucesso");
    } catch (e) {
      showErrorDialog(context, "Falha ao excluir colaborador", "Atenção");
    }
  }

  void _showDeleteConfirmationDialog(String uid) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: Theme.of(context).primaryColor
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'Excluir Colaborador',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
              SizedBox(height: 16.0),
              Text(
                'Você tem certeza que deseja excluir este colaborador? "ESTA AÇÃO NÃO PODE SER DESFEITA!"',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Fechar o BottomSheet
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Fechar o BottomSheet
                      _deleteCollaborator(uid); // Excluir o colaborador
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                    ),
                    child: Text(
                      'Excluir',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String userId = FirebaseAuth.instance.currentUser?.uid ?? ''; // Obtém o UID do usuário logado

    return GestureDetector(
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            _navigateWithBottomToTopTransition(context, AddCollaborators());
          },
          child: Icon(
            Icons.add,
            color: Theme.of(context).colorScheme.outline,
            size: 24,
          ),
          backgroundColor: Theme.of(context).primaryColor,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50), // Define o botão como totalmente arredondado
          ),
        ),
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Theme.of(context).primaryColor,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: Theme.of(context).colorScheme.outline,
              size: 24,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: Text(
            'Colaboradores',
            style: TextStyle(
              fontFamily: 'BrandingSF',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          elevation: 0,
        ),
        body: SafeArea(
          top: true,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _getUserCollaborators(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro ao carregar colaboradores: ${snapshot.error}')); // Mostra o erro completo
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(child: Text('Nenhum colaborador encontrado'));
              }

              final collaborators = snapshot.data!;

              return ListView.builder(
                itemCount: collaborators.length,
                itemBuilder: (context, index) {
                  final collaborator = collaborators[index];
                  return Card(
                    color: Theme.of(context).cardColor,
                    shadowColor: Theme.of(context).shadowColor,
                    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: ListTile(
                      title: Text(
                        collaborator['name'] ?? 'Nome não disponível',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                      subtitle: Text(
                        collaborator['role'] ?? 'Cargo não disponível',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSecondary,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.onSecondary),
                            onPressed: () {
                              _navigateWithBottomToTopTransition(
                                context,
                                EditCollaborators(
                                  collaboratorId: collaborator['uid'] ?? '',
                                  name: collaborator['name'] ?? 'Nome não disponível',
                                  email: collaborator['email'] ?? 'Email não disponível',
                                  role: collaborator['role'] ?? 'Cargo não disponível',
                                  dashboard: collaborator['dashboard'] ?? false,
                                  leads: collaborator['leads'] ?? false,
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              _showDeleteConfirmationDialog(collaborator['uid'] ?? '');
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
