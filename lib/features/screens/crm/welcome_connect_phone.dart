import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:fl_country_code_picker/fl_country_code_picker.dart';

class _PhoneCodeDialog extends StatefulWidget {
  const _PhoneCodeDialog();

  @override
  State<_PhoneCodeDialog> createState() => _PhoneCodeDialogState();
}

class _PhoneCodeDialogState extends State<_PhoneCodeDialog> {
  /* -------------------- estado -------------------- */
  final _ctrl = TextEditingController();
  final _mask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {'#': RegExp(r'\d')});

  CountryCode _country = const CountryCode(
    name: 'Brazil',
    code: 'BR',
    dialCode: '+55',
  );

  String? _code; // código gerado pela API
  Timer? _poll; // timer para verificar conexão
  late final FlCountryCodePicker _picker;
  bool _pickerReady = false;

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pickerReady) return; // garante 1ª execução

    final cs = Theme.of(context).colorScheme;

    _picker = FlCountryCodePicker(
      // ───────── visual dos itens ─────────
      localize: false,
      showDialCode: true,
      countryTextStyle: TextStyle(
        color: cs.onBackground,
        fontSize: 14,
      ),
      dialCodeTextStyle: TextStyle(
        color: cs.onSecondary,
        fontWeight: FontWeight.w600,
      ),

      // ───────── título do modal ─────────
      title: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 16, 12),
        child: Text(
          'Selecione o país',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: cs.onSecondary,
          ),
        ),
      ),

      // ───────── barra de pesquisa ─────────
      showSearchBar: true,
      searchBarDecoration: InputDecoration(
        hintText: 'Buscar…',
        hintStyle: TextStyle(color: cs.onSecondary),
        // ← cor do hint
        filled: true,
        fillColor: cs.secondary,
        // ← cor de fundo
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        prefixIcon: Icon(Icons.search, color: cs.onSecondary),
      ),

      favoritesIcon: Icon(Icons.star, color: cs.primary),
    );

    _pickerReady = true;
  }

  /* -------------------- API -------------------- */
  Future<void> _requestCode() async {
    final ddiDigits = _country.dialCode.replaceAll(RegExp(r'\D'), '');
    final phoneDigits = _mask.getUnmaskedText(); // ex.: 11987654321

    if (phoneDigits.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Número inválido')),
      );
      return;
    }

    final full = ddiDigits + phoneDigits; // 5511987654321
    final res = await FirebaseFunctions.instance
        .httpsCallable('getPhoneCode')
        .call({'phone': full});

    setState(() => _code = res.data['code'] as String?);

    // polling para saber quando conectar
    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      final s = await FirebaseFunctions.instance
          .httpsCallable('getConnectionStatus')
          .call();

      if (s.data['connected'] == true) {
        _poll?.cancel();
        if (mounted) Navigator.pop(context); // fecha o diálogo
      }
    });
  }

  /* -------------------- picker de DDI -------------------- */
  Future<void> _pickCountry() async {
    final cs = Theme.of(context).colorScheme;

    final picked = await _picker.showPicker(
      context: context,
      backgroundColor: cs.background, // fundo correto
      pickerMaxHeight: 450,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );

    if (picked != null) setState(() => _country = picked);
  }

  String _isoToEmoji(String isoCode) {
    const base = 0x1F1E6; // 🇦
    final int first = isoCode.codeUnitAt(0) - 0x41 + base;
    final int second = isoCode.codeUnitAt(1) - 0x41 + base;
    return String.fromCharCodes([first, second]);
  }

  /* -------------------- UI -------------------- */
  @override
  Widget build(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;

    final ButtonStyle btn = ElevatedButton.styleFrom(
      backgroundColor: cs.primary, // fundo primary
      foregroundColor: cs.onSurface, // texto/ícones onSurface
      minimumSize: const Size(80, 40),
    );

    final ButtonStyle btnfechar = ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent, // fundo primary
      foregroundColor: cs.onSurface,
      minimumSize: const Size(80, 40),
    );

    return AlertDialog(
      backgroundColor: cs.background,
      title: const Text(
        'Conectar usando telefone',
        textAlign: TextAlign.center,
      ),
      content: _code == null
          /* —— 1. primeira etapa: preenchimento —— */
          ? SizedBox(
              width: 500, // ↔ um pouco mais largo
              height: 70,
              child: Row(
                children: [
                  // seletor de DDI + bandeira
                  InkWell(
                    onTap: _pickCountry,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_isoToEmoji(_country.code),
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 2),
                          Text(_country.dialCode,
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // campo de telefone com máscara
                  Expanded(
                    child: Container(
                      height: 48, // ⬅︎ mesma altura do seletor
                      decoration: BoxDecoration(
                        color: cs.secondary, // ⬅︎ fundo secondary
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _ctrl,
                        inputFormatters: [_mask],
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: cs.onBackground),
                        decoration: const InputDecoration(
                          hintText: 'DDD + Número de telefone',
                          border: InputBorder.none, // sem borda branca
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          /* —— 2. segunda etapa: exibe o código —— */
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Código gerado:', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                SelectableText(_code!,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                const Text(
                  'Abra o WhatsApp → Aparelhos conectados → '
                  'Conectar com número de telefone e digite o código acima',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          style: btnfechar,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
        ElevatedButton(
          style: btn,
          onPressed: _requestCode,
          child: const Text('Gerar código'),
        ),
      ],
    );
  }
}

class _QrConnectDialog extends StatefulWidget {
  const _QrConnectDialog();

  @override
  _QrConnectDialogState createState() => _QrConnectDialogState();
}

class _QrConnectDialogState extends State<_QrConnectDialog> {
  String? _base64;
  Timer? _pollQr;
  Timer? _pollStatus;

  @override
  void initState() {
    super.initState();
    _getQr();
    _startPolling();
  }

  Future<void> _getQr() async {
    final r = await FirebaseFunctions.instance
        .httpsCallable('getQr')
        .call(); // corpo vazio, backend usa o user
    setState(() => _base64 = (r.data['image'] as String?)?.split(',').last);
  }

  void _startPolling() {
    // renova QR a cada 15 s
    _pollQr = Timer.periodic(const Duration(seconds: 15), (_) => _getQr());
    // consulta status a cada 5 s
    _pollStatus = Timer.periodic(const Duration(seconds: 5), (_) async {
      final s = await FirebaseFunctions.instance
          .httpsCallable('getConnectionStatus')
          .call();
      if (s.data['connected'] == true) {
        _pollQr?.cancel();
        _pollStatus?.cancel();
        if (mounted) Navigator.pop(context); // fecha o diálogo
      }
    });
  }

  @override
  void dispose() {
    _pollQr?.cancel();
    _pollStatus?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    return AlertDialog(
      title: const Text('Leia o QR-Code'),
      content: SizedBox(
        width: 240,
        height: 240,
        child: _base64 == null
            ? const Center(child: CircularProgressIndicator())
            : Image.memory(base64Decode(_base64!), fit: BoxFit.contain),
      ),
      actions: [
        TextButton(
            child: const Text('Cancelar'),
            onPressed: () {
              Navigator.pop(ctx);
            })
      ],
    );
  }
}

class WelcomeConnectPhone extends StatelessWidget {
  const WelcomeConnectPhone();

  @override
  Widget build(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined, size: 96, color: Colors.grey),
              const SizedBox(height: 24),
              Text('Boas-vindas!',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onBackground)),
              const SizedBox(height: 8),
              Text(
                'Para começar a receber e responder as mensagens dos seus leads diretamente pelo app, conecte um novo número de telefone do WhatsApp.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSecondary, fontSize: 15),
              ),
              const SizedBox(height: 32),

              // ─── Botões ───
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Conectar via QR-Code'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: cs.primary,
                  foregroundColor:
                      cs.onSurface, // ← texto + ícone na cor onSurface
                ),
                onPressed: () => _openQrDialog(ctx),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.phone_android),
                label: const Text('Conectar com número'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onSurface,
                    side: BorderSide(width: 0)),
                onPressed: () => _openPhoneDialog(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ------------------- diálogos ------------------- */
  void _openQrDialog(BuildContext ctx) {
    showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => const _QrConnectDialog());
  }

  void _openPhoneDialog(BuildContext ctx) {
    showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => const _PhoneCodeDialog());
  }
}
