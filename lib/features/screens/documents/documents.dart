import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:printing/printing.dart'; // rasteriza PDF
import 'package:http/http.dart' as http;
import 'dart:ui' as ui; // para ImageFilter.blur

Future<String?> generateAndUploadPdfCover({
  required String pdfUrl,
  required String storageObjectPath, // ex: reports/{companyId}/{docId}_cover.png
}) async {
  try {
    final resp = await http.get(Uri.parse(pdfUrl));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
    final Uint8List pdfBytes = resp.bodyBytes;

    final pages = await Printing.raster(pdfBytes, dpi: 144);
    final first = await pages.first;
    final Uint8List pngBytes = await first.toPng();

    final ref = FirebaseStorage.instance.ref(storageObjectPath);
    await ref.putData(
      pngBytes,
      SettableMetadata(
        contentType: 'image/png',
        cacheControl: 'public,max-age=31536000',
      ),
    );
    return await ref.getDownloadURL();
  } catch (_) {
    return null;
  }
}

class CompanyReportsPage extends StatefulWidget {
  const CompanyReportsPage({Key? key}) : super(key: key);

  @override
  State<CompanyReportsPage> createState() => _CompanyReportsPageState();
}

class _CompanyReportsPageState extends State<CompanyReportsPage> {
  String? _companyId;

  // ======== Catálogo fixo de documentos da “área de membros” ========
  late final List<_DocItem> _memberDocs = [
    _DocItem(title: 'Onboarding', coverAsset: 'assets/images/covers/onboarding.webp', link: 'https://example.com/onboarding'),
    _DocItem(title: 'Central de atendimento', coverAsset: 'assets/images/covers/central-atendimento.webp', link: 'https://example.com/central'),
    _DocItem(title: 'Manual do cliente', coverAsset: 'assets/images/covers/manual-cliente.webp', link: 'https://example.com/manual'),
    _DocItem(title: 'Checklist de lead', coverAsset: 'assets/images/covers/checklist-lead.webp', link: 'https://example.com/checklist'),
    _DocItem(title: 'Manual de criativos', coverAsset: 'assets/images/covers/manual-criativos.webp', link: 'https://example.com/criativos'),
    _DocItem(title: 'Contrato', coverAsset: 'assets/images/covers/contrato.webp', link: 'https://example.com/contrato'),
  ];

  bool get _isDesktop {
    final w = MediaQuery.of(context).size.width;
    return w >= 1024;
  }

  EdgeInsets _sideGutters() {
    final w = MediaQuery.of(context).size.width;
    if (w >= 1440) return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    if (w >= 1024) return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  }

  static const List<String> _ptMonths = [
    'janeiro','fevereiro','março','abril','maio','junho',
    'julho','agosto','setembro','outubro','novembro','dezembro'
  ];

  String _labelFromYm(String ym) {
    final parts = ym.split('-'); // espera "YYYY-MM"
    if (parts.length != 2) return ym;
    final m = int.tryParse(parts[1]) ?? 1;
    final name = _ptMonths[(m - 1).clamp(0, 11)];
    return '${name[0].toUpperCase()}${name.substring(1)} ${parts[0]}';
  }

  List<String> _monthsForYear(int year) =>
      List<String>.generate(12, (i) => '$year-${(i + 1).toString().padLeft(2, '0')}');

  @override
  void initState() {
    super.initState();
    _resolveCompanyId();
  }

  Future<void> _resolveCompanyId() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = userSnap.data() as Map<String, dynamic>?;
    final createdBy = (data?['createdBy'] as String?)?.trim();
    setState(() => _companyId = (createdBy != null && createdBy.isNotEmpty) ? createdBy : uid);
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ======== Fundo liso para cards sem relatório ========
  Widget _solidCover({Color? color, IconData? icon}) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.surfaceVariant.withOpacity(.35);
    return Container(
      decoration: BoxDecoration(
        color: bg,                          // <- mantém cor lisa
        borderRadius: BorderRadius.circular(10),
      ),
      child: icon == null
          ? const SizedBox.expand()
          : Center(
        child: Icon(icon, size: 52, color: Colors.white.withOpacity(.45)),
      ),
    );
  }

  // ======== Etiqueta central inferior (apenas relatórios) ========
  Widget _bottomMonthPill(String text) {
    final cs = Theme.of(context).colorScheme;
    final double fs = _isDesktop ? 12 : 12;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _isDesktop ? 10 : 10,         // ↓ era 12
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(.15)),
          ),
          child: Text(
            text,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fs, letterSpacing: .2),
          ),
        ),
      ),
    );
  }

  // ======== Card base (sem título/subtítulo); clicável; suporta overlay e etiqueta inferior ========
  Widget _coverCard({
    required Widget cover,
    required VoidCallback? onOpen,
    bool disabled = false,
    String? bottomCenterLabel,
    String? overlayMessage,
  }) {
    final cs = Theme.of(context).colorScheme;
    final double radius = _isDesktop ? 10 : 10; // ↓ era 14 no desktop

    Widget body = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: cover),
          if (disabled)
            Positioned.fill(child: Container(color: Colors.black.withOpacity(.25))),
          if (overlayMessage != null && overlayMessage.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  overlayMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.95),
                    fontSize: _isDesktop ? 14 : 14, // ↓ era 15
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Colors.black.withOpacity(.45), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                ),
              ),
            ),
          if (bottomCenterLabel != null && bottomCenterLabel.isNotEmpty)
            _bottomMonthPill(bottomCenterLabel),
        ],
      ),
    );

    body = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: disabled ? null : onOpen,
        child: body,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(.25),
          width: 1,
        ),
      ),
      child: body,
    );
  }

  // ======== Carrossel infinito ========
  // ======== Carrossel (mobile mantém o seu comportamento atual) ========
  Widget _infiniteCarousel({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    double aspectRatio = 1.6,
    double gapBetweenItems = 10,
    double viewportFraction = .80, // usado no mobile
  }) {
    if (itemCount <= 0) return const SizedBox.shrink();
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    // ---------- MOBILE: usa PageView simples com muitos clones ----------
    if (!isDesktop) {
      const int loopSpan = 1000000;
      final int startPage = (loopSpan ~/ 2) - ((loopSpan ~/ 2) % itemCount);
      final controller = PageController(
        viewportFraction: viewportFraction,
        initialPage: startPage,
        keepPage: true,
      );
      return SizedBox(
        height: (MediaQuery.of(context).size.width * viewportFraction) / aspectRatio,
        child: PageView.builder(
          controller: controller,
          itemBuilder: (ctx, i) => Padding(
            padding: EdgeInsets.symmetric(horizontal: gapBetweenItems / 2),
            child: itemBuilder(ctx, i % itemCount),
          ),
        ),
      );
    }

    // ---------- DESKTOP: 3 cards por vez, 1 por clique/scroll, infinito ----------
    return _DesktopInfiniteCarousel(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      gap: 16.0,                 // gap confortável entre os cards
      targetAr: 1.08,            // ↓ mais alto (antes ~1.2–1.6). Quanto menor, mais alto
      minH: 240,                 // ↑ altura mínima maior
      maxH: 320,                 // ↑ altura máxima maior
    );
  }

  // ========================= BUILD =========================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_companyId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // ---------- DOCUMENTOS ----------
    final docsShelf = _infiniteCarousel(
      itemCount: _memberDocs.length,
      itemBuilder: (ctx, i) {
        final d = _memberDocs[i];
        return _coverCard(
          cover: Image.asset(d.coverAsset, fit: BoxFit.cover),
          onOpen: () => _openUrl(d.link),
          disabled: false,
        );
      },
      aspectRatio: 1.6,
      gapBetweenItems: 10,
      viewportFraction: .80,
    );

    // ---------- RELATÓRIOS (sempre 12 meses do ano corrente) ----------
    final int currentYear = DateTime.now().year;
    final List<String> monthsList = _monthsForYear(currentYear); // YYYY-01 .. YYYY-12

    final reportsShelf = StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('empresas')
          .doc(_companyId)
          .collection('relatorios')
          .orderBy('mesReferencia', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final allDocs = snap.data?.docs ?? [];

        // Mapa id -> dados (apenas do ano corrente)
        final Map<String, Map<String, dynamic>> byId = {};
        for (final d in allDocs) {
          final id = d.id; // esperado "YYYY-MM"
          if (id.length == 7 && id.startsWith('$currentYear-')) {
            byId[id] = (d.data() ?? {}) as Map<String, dynamic>;
          }
        }

        return _infiniteCarousel(
          itemCount: monthsList.length,
          itemBuilder: (ctx, i) {
            final ym = monthsList[i];
            final monthLabel = _labelFromYm(ym);

            final data = byId[ym];
            final url = (data?['arquivoUrl'] as String?) ?? '';
            final coverUrl = (data?['coverUrl'] as String?) ?? '';

            if (url.isNotEmpty) {
              final docRef = FirebaseFirestore.instance
                  .collection('empresas').doc(_companyId)
                  .collection('relatorios').doc(ym);

              return _ReportCoverEnsurer(
                docRef: docRef,
                data: {'url': url, 'coverUrl': coverUrl},
                builder: (ensuredCoverUrl) {
                  // usa a URL garantida se já existir; senão, tenta a coverUrl do Firestore
                  final displayUrl = (ensuredCoverUrl != null && ensuredCoverUrl.isNotEmpty)
                      ? ensuredCoverUrl
                      : coverUrl;

                  // Se estamos no Web, passa pelo proxy (para evitar CORS). Senão, usa direto.
                  final String? coverSrc = (displayUrl.isNotEmpty)
                      ? (kIsWeb
                      ? 'https://proxyreportcover-5a3yl3wsma-uc.a.run.app?url=${Uri.encodeComponent(displayUrl)}'
                      : displayUrl)
                      : null;

                  final Widget coverWidget = (coverSrc != null)
                      ? Image.network(
                    coverSrc,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _solidCover(icon: Icons.picture_as_pdf_outlined),
                  )
                      : _solidCover(icon: Icons.picture_as_pdf_outlined);

                  return _coverCard(
                    cover: coverWidget,
                    onOpen: () => _openUrl(url),
                    disabled: false,
                    bottomCenterLabel: monthLabel,
                  );
                },
              );
            }

            // Sem documento: fundo liso + mensagem + etiqueta do mês/ano
            return _coverCard(
              cover: _solidCover(),
              onOpen: null,
              disabled: true,
              bottomCenterLabel: monthLabel,
              overlayMessage: 'Ainda não há relatórios neste mês',
            );
          },
          aspectRatio: 1.6,
          gapBetweenItems: 10,
          viewportFraction: .80,
        );
      },
    );
    final double titleSize = _isDesktop ? 26 : 25; // ↓ antes 30

    // ---------- LAYOUT ----------
    // ---------- LAYOUT ----------
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        // mantém o look padrão, mas poderia desativar a barra aqui se quisesse
        // scrollbars: true,
      ),
      child: ListView(
        // a barra vertical agora pertence a ESTE ListView de largura total da janela
        padding: _sideGutters().add(const EdgeInsets.only(bottom: 24)),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 20),
                    child: Text(
                      'Documentos',
                      style: TextStyle(
                        color: cs.onSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: _isDesktop ? 30 : 25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  docsShelf,

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 16, 20),
                    child: Text(
                      'Relatórios mensais ($currentYear)',
                      style: TextStyle(
                        color: cs.onSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: _isDesktop ? 30 : 25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  reportsShelf,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIcon({required IconData icon, required VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: cs.primary.withOpacity(.35), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

// ======== MODELOS ========
class _DocItem {
  final String title;
  final String coverAsset;
  final String link;

  _DocItem({required this.title, required this.coverAsset, required this.link});
}

// Garante coverUrl gerando miniatura da 1ª página do PDF
class _ReportCoverEnsurer extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> docRef;
  final Map<String, dynamic> data;
  final Widget Function(String? coverUrl) builder;

  const _ReportCoverEnsurer({
    Key? key,
    required this.docRef,
    required this.data,
    required this.builder,
  }) : super(key: key);

  @override
  State<_ReportCoverEnsurer> createState() => _ReportCoverEnsurerState();
}

class _ReportCoverEnsurerState extends State<_ReportCoverEnsurer> {
  String? _coverUrl;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _coverUrl = widget.data['coverUrl'] as String?;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _maybeGenerate();
    }
  }

  Future<void> _maybeGenerate() async {
    if (_coverUrl != null && _coverUrl!.isNotEmpty) return;
    final pdfUrl = widget.data['url'] as String? ?? '';
    if (pdfUrl.isEmpty) return;

    // empresas/{empresaId}/relatorios/{docId}
    final companyId = widget.docRef.parent.parent?.id ?? 'unknown_company';
    final docId = widget.docRef.id;
    final storagePath = 'reports/$companyId/${docId}_cover.png';

    final url = await generateAndUploadPdfCover(
      pdfUrl: pdfUrl,
      storageObjectPath: storagePath,
    );
    if (!mounted) return;
    if (url != null) {
      setState(() => _coverUrl = url);
      await widget.docRef.set({'coverUrl': url}, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_coverUrl);
  }
}

class _DesktopInfiniteCarousel extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final double gap;
  final double targetAr; // width/height desejado do card (menor => mais alto)
  final double minH;
  final double maxH;

  const _DesktopInfiniteCarousel({
    Key? key,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 16.0,
    this.targetAr = 1.08,
    this.minH = 240,
    this.maxH = 320,
  }) : super(key: key);

  @override
  State<_DesktopInfiniteCarousel> createState() => _DesktopInfiniteCarouselState();
}

class _DesktopInfiniteCarouselState extends State<_DesktopInfiniteCarousel> {
  static const int _loopSpan = 1000000;
  late final int _startPage;
  PageController? _controller;

  @override
  void initState() {
    super.initState();
    // alinhar o centro ao múltiplo de itemCount evita “quebras” visuais
    final mid = _loopSpan ~/ 2;
    _startPage = mid - (mid % widget.itemCount);

    // Controller provisório para garantir render no 1º frame.
    // Será substituído por _ensureController(vf) no build.
    _controller = PageController(
      viewportFraction: 1 / 3, // 3 cards por viewport como default
      initialPage: _startPage,
      keepPage: true,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _ensureController(double vf) {
    // recria o controller se o vf mudar (ex.: resize de janela)
    if (_controller == null || (_controller!.viewportFraction - vf).abs() > 0.0001) {
      _controller?.dispose();
      _controller = PageController(
        viewportFraction: vf,
        initialPage: _startPage,
        keepPage: true,
      );
      // sem setState aqui para não causar "piscar"
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, c) {
      final double w = c.maxWidth;
      const int perScreen = 3;
      final double gap = widget.gap;

      // ===== Cálculo sem bleed: 3 páginas exatas =====
      final double vf = 1 / perScreen;      // cada página ocupa 1/3 da largura
      final double pageW = w * vf;          // largura de UMA página do PageView
      final double cardW = pageW - gap;     // espaço do card dentro da página
      final double bodyH = (cardW / widget.targetAr)
          .clamp(widget.minH, widget.maxH);

      _ensureController(vf);

      Widget _arrow(IconData icon, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.secondary.withOpacity(.96),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, size: 22, color: cs.onBackground.withOpacity(.85)),
          ),
        ),
      );

      void goPrev() {
        final curr = (_controller!.page ?? 0).round();
        _controller!.animateToPage(
          curr - 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }

      void goNext() {
        final curr = (_controller!.page ?? 0).round();
        _controller!.animateToPage(
          curr + 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }

      final pageView = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            ui.PointerDeviceKind.touch,
            ui.PointerDeviceKind.mouse,
            ui.PointerDeviceKind.trackpad,
            ui.PointerDeviceKind.stylus,
          },
        ),
        child: SizedBox(
          height: bodyH,
          child: PageView.builder(
            controller: _controller!,                 // <- garante controller não-nulo
            physics: const PageScrollPhysics(),       // 1 card por “página”
            padEnds: false,
            clipBehavior: Clip.hardEdge,
            itemCount: _loopSpan,
            itemBuilder: (context, i) {
              final realIndex = i % widget.itemCount;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: gap / 2),
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: cardW,
                    height: bodyH,
                    child: widget.itemBuilder(context, realIndex),
                  ),
                ),
              );
            },
            onPageChanged: (i) {
              // wrap infinito “silencioso”
              const int guard = 9990;
              if (i < guard || i > (_loopSpan - guard)) {
                final aligned = _startPage + (i % widget.itemCount);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _controller?.hasClients == true) {
                    _controller!.jumpToPage(aligned);
                  }
                });
              }
            },
          ),
        ),
      );

      // Se houver 3 ou menos, não mostra setas
      if (widget.itemCount <= perScreen) return pageView;

      // Reserva 56px de cada lado para as setas ficarem DENTRO do Stack
      return SizedBox(
        height: bodyH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // PageView centralizado com “gutter” para as setas
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: pageView,
              ),
            ),

            // Setas visíveis e clicáveis (sem offset negativo)
            Positioned(
              left: 8,
              top: bodyH / 2 - 21,
              child: _arrow(Icons.chevron_left, goPrev),
            ),
            Positioned(
              right: 8,
              top: bodyH / 2 - 21,
              child: _arrow(Icons.chevron_right, goNext),
            ),
          ],
        ),
      );
    });
  }
}