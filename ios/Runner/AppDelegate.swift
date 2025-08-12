import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleMaps // Importa o GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Inicializa o Firebase
    FirebaseApp.configure()
    print("Firebase configurado com sucesso.")

    // Inicializa o Google Maps com sua chave de API
    GMSServices.provideAPIKey("AIzaSyDMrSrMu5iWV3FmkJg7oMGqZQHI4EDJd0U") // Substitua pela sua chave

    // Configura o delegado para receber notificações
    UNUserNotificationCenter.current().delegate = self

    // Solicita permissão para notificações push
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        if let error = error {
            print("Erro ao solicitar permissão de notificação: \(error)")
        }
    }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)

    // Configuração do canal Flutter para o WhatsApp
    if let controller = window?.rootViewController as? FlutterViewController {
        let whatsappChannel = FlutterMethodChannel(name: "com.iomarketing.whatsapp",
                                                   binaryMessenger: controller.binaryMessenger)

        whatsappChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else { return }
            if call.method == "openWhatsApp" {
                if let args = call.arguments as? [String: Any],
                   let phoneNumber = args["phone"] as? String {
                    self.openWhatsApp(phoneNumber: phoneNumber)
                    result(nil)
                } else {
                    result(FlutterError(code: "ERROR", message: "Número de telefone não fornecido", details: nil))
                }
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Método para obter o token APNs e configurar o Firebase Messaging
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
      print("APNs token recebido: \(deviceToken)")
      Messaging.messaging().apnsToken = deviceToken
  }

  // Método para lidar com erro de registro de notificações remotas
  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
      print("Falha ao registrar para notificações remotas: \(error)")
  }

  // Função para abrir o WhatsApp com um número específico
  private func openWhatsApp(phoneNumber: String) {
    let urlWhats = "https://wa.me/\(phoneNumber)"
    if let urlString = urlWhats.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let url = URL(string: urlString) {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            print("WhatsApp não está instalado.")
        }
    }
  }
}