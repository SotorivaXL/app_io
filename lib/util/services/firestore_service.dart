import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> createForm(String empresaId, String campanhaId, Map<String, dynamic> formData) async {
    try {
      await _db
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .doc(campanhaId)
          .collection('forms')
          .add(formData);
    } catch (e) {
      throw e;
    }
  }

  Future<List<Map<String, dynamic>>> getEmpresas() async {
    try {
      QuerySnapshot snapshot = await _db.collection('empresas').get();
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        'NomeEmpresa': doc['NomeEmpresa']
      }).toList();
    } catch (e) {
      print('Erro ao carregar empresas: $e');
      throw e;
    }
  }

  Future<List<Map<String, dynamic>>> getCampanhas(String empresaId) async {
    try {
      QuerySnapshot snapshot = await _db
          .collection('empresas')
          .doc(empresaId)
          .collection('campanhas')
          .get();

      return snapshot.docs.map((doc) => {
        'id': doc.id,
        'nome_campanha': doc['nome_campanha']
      }).toList();
    } catch (e) {
      print('Erro ao carregar campanhas: $e');
      throw e;
    }
  }

  Future<void> addData(String collection, Map<String, dynamic> data) {
    return _db.collection(collection).add(data);
  }

  Future<void> updateData(String collection, String docId, Map<String, dynamic> data) {
    return _db.collection(collection).doc(docId).update(data);
  }

  Future<void> deleteData(String collection, String docId) {
    return _db.collection(collection).doc(docId).delete();
  }

  Stream<QuerySnapshot> getDataStream(String collection) {
    return _db.collection(collection).snapshots();
  }

  Future<QuerySnapshot> getData(String collection) {
    return _db.collection(collection).get();
  }

  Future<void> saveFormHtml(String campanhaId, String formHtml) async {
    try {
      await _db.collection('campanhas').doc(campanhaId).update({
        'formHtml': formHtml,
      });
    } catch (e) {
      throw Exception('Erro ao salvar HTML do formulário: $e');
    }
  }
}
