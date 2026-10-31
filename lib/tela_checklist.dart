import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'armazenamento.dart';
import 'config_page.dart';
import 'repositorio.dart';
import 'tarefa.dart';

/// Cor da borda de cada prioridade. O fundo do cartão é essa cor bem diluída
/// (clara no tema claro, escura no escuro), então os dois temas saem da mesma base.
const _corBorda = {
  Prioridade.urgente: Color(0xFFEF6F63),
  Prioridade.normal: Color(0xFFE6B800),
  Prioridade.quandoDer: Color(0xFF5FAE72),
};

class _Paleta {
  _Paleta(Brightness b) : escuro = b == Brightness.dark;
  final bool escuro;

  Color get fundo => escuro ? const Color(0xFF121412) : const Color(0xFFF6F4EF);
  Color get texto => escuro ? const Color(0xFFEDEDE8) : const Color(0xFF2B2B2B);
  Color get suave => escuro ? const Color(0xFF9A9D98) : const Color(0xFF7A7A75);
  Color get base => escuro ? const Color(0xFF1C1E1C) : Colors.white;

  Color borda(Prioridade p) => _corBorda[p]!;
  Color fundoCartao(Prioridade p) => Color.alphaBlend(borda(p).withValues(alpha: escuro ? 0.16 : 0.15), base);
  Color get fundoFeitas => escuro ? const Color(0xFF1A1C1A) : Colors.white;
  Color get bordaFeitas => escuro ? const Color(0xFF2E312E) : const Color(0xFFE4E1DA);

  /// "Vidro": branco/preto translúcido sobre o desfoque do que passa por baixo.
  Color get vidro => (escuro ? const Color(0xFF232623) : Colors.white).withValues(alpha: escuro ? 0.72 : 0.78);
  Color get bordaVidro => (escuro ? Colors.white : Colors.white).withValues(alpha: escuro ? 0.10 : 0.85);
  Color get campo => (escuro ? Colors.white : const Color(0xFFEFEDE6)).withValues(alpha: escuro ? 0.08 : 0.9);
}

/// Tela única: contador, cartões por prioridade e a barra de vidro de adicionar.
class TelaChecklist extends StatefulWidget {
  const TelaChecklist({
    super.key,
    required this.repo,
    required this.armazem,
    this.criarFonte = criarFontePadrao,
    this.intervaloSync = const Duration(seconds: 30),
  });

  final RepositorioTarefas repo;
  final Armazenamento armazem;
  final CriarFonte criarFonte;

  /// Enquanto a tela está aberta, busca novidades (o que o Claude lançou) a cada tanto.
  final Duration intervaloSync;

  @override
  State<TelaChecklist> createState() => _TelaChecklistState();
}

class _TelaChecklistState extends State<TelaChecklist> with WidgetsBindingObserver {
  final _texto = TextEditingController();
  final _prazo = TextEditingController();
  final _focoTexto = FocusNode();
  Prioridade _prioridade = Prioridade.normal;
  String? _erroCampo;
  bool _aberta = false; // barra de lançamento recolhida: só o botão +
  Timer? _timer;

  RepositorioTarefas get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.intervaloSync, (_) => repo.sincronizar());
    unawaited(repo.sincronizar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _texto.dispose();
    _prazo.dispose();
    _focoTexto.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(repo.sincronizar());
  }

  Future<void> _adicionar() async {
    final erro = await repo.adicionar(_texto.text, _prioridade, prazo: _prazo.text);
    if (!mounted) return;
    setState(() => _erroCampo = erro);
    if (erro == null) {
      _texto.clear();
      _prazo.clear();
      _focoTexto.requestFocus(); // segue digitando a próxima, sem tocar de novo no campo
    }
  }

  void _abrirBarra() {
    setState(() => _aberta = true);
    _focoTexto.requestFocus();
  }

  void _fecharBarra() {
    _focoTexto.unfocus();
    setState(() {
      _aberta = false;
      _erroCampo = null;
    });
  }

  Future<void> _abrirConfig() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConfigPage(repo: repo, armazem: widget.armazem, criar: widget.criarFonte),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = _Paleta(Theme.of(context).brightness);
    return Scaffold(
      backgroundColor: p.fundo,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: repo,
          builder: (context, _) {
            final pend = repo.listaPendentes;
            final feitas = repo.listaFeitasHoje;
            return Stack(
              children: [
                Column(
                  children: [
                    _Topo(
                      paleta: p,
                      pendentes: pend.length,
                      feitas: feitas.length,
                      repo: repo,
                      onConfig: _abrirConfig,
                      onSync: repo.sincronizar,
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: repo.sincronizar,
                        child: _Lista(paleta: p, pendentes: pend, feitas: feitas, onToque: repo.alternar),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12 + MediaQuery.paddingOf(context).bottom,
                  child: _BarraAdicionar(
                    aberta: _aberta,
                    onAbrir: _abrirBarra,
                    onFechar: _fecharBarra,
                    paleta: p,
                    texto: _texto,
                    prazo: _prazo,
                    foco: _focoTexto,
                    prioridade: _prioridade,
                    erro: _erroCampo,
                    onPrioridade: () => setState(() => _prioridade = _prioridade.proxima),
                    onAdicionar: _adicionar,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Topo extends StatelessWidget {
  const _Topo({
    required this.paleta,
    required this.pendentes,
    required this.feitas,
    required this.repo,
    required this.onConfig,
    required this.onSync,
  });

  final _Paleta paleta;
  final int pendentes;
  final int feitas;
  final RepositorioTarefas repo;
  final VoidCallback onConfig;
  final Future<bool> Function() onSync;

  @override
  Widget build(BuildContext context) {
    String estado;
    IconData icone;
    Color cor;
    if (!repo.configurado) {
      estado = 'Sem banco — toque em ⚙️';
      icone = Icons.cloud_off;
      cor = const Color(0xFFE08A00);
    } else if (repo.sincronizando) {
      estado = 'Sincronizando…';
      icone = Icons.sync;
      cor = paleta.suave;
    } else if (repo.erro != null) {
      estado = repo.semEnviar > 0 ? 'Offline · ${repo.semEnviar} p/ enviar' : 'Offline';
      icone = Icons.cloud_off;
      cor = const Color(0xFFE08A00);
    } else {
      estado = repo.semEnviar > 0 ? '${repo.semEnviar} p/ enviar' : 'Sincronizado';
      icone = Icons.cloud_done;
      cor = const Color(0xFF3E9B5A);
    }
    final grande = TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: paleta.texto);
    final pequeno = TextStyle(fontSize: 14, color: paleta.suave);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Risca',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: paleta.texto, letterSpacing: -0.5)),
            ),
            _BotaoVidro(
              paleta: paleta,
              chave: const Key('botao-config'),
              icone: Icons.settings_outlined,
              onTap: onConfig,
            ),
          ]),
          Divider(height: 14, color: paleta.suave.withValues(alpha: 0.25)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$pendentes', key: const Key('contador-pendentes'), style: grande),
              Text(' pendentes   ·   ', style: pequeno),
              Text('$feitas', key: const Key('contador-feitas'), style: grande),
              Text(' feitas hoje', style: pequeno),
            ],
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: onSync,
            child: Row(children: [
              Icon(icone, size: 14, color: cor),
              const SizedBox(width: 4),
              Text(estado, key: const Key('estado-sync'), style: TextStyle(fontSize: 12, color: cor)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _BotaoVidro extends StatelessWidget {
  const _BotaoVidro({required this.paleta, required this.chave, required this.icone, required this.onTap});

  final _Paleta paleta;
  final Key chave;
  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: paleta.vidro,
        shape: CircleBorder(side: BorderSide(color: paleta.bordaVidro)),
        elevation: 0,
        child: InkWell(
          key: chave,
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icone, color: paleta.texto)),
        ),
      );
}

class _Lista extends StatelessWidget {
  const _Lista({required this.paleta, required this.pendentes, required this.feitas, required this.onToque});

  final _Paleta paleta;
  final List<Tarefa> pendentes;
  final List<Tarefa> feitas;
  final void Function(String id) onToque;

  @override
  Widget build(BuildContext context) {
    final cartoes = <Widget>[];
    for (final prio in Prioridade.values) {
      final doGrupo = pendentes.where((t) => t.prioridade == prio).toList();
      if (doGrupo.isEmpty) continue;
      cartoes.add(_Cartao(
        titulo: '${prio.emoji} ${prio.rotulo}',
        fundo: paleta.fundoCartao(prio),
        borda: paleta.borda(prio),
        paleta: paleta,
        tarefas: doGrupo,
        corCheck: paleta.borda(prio),
        onToque: onToque,
      ));
    }
    if (pendentes.isEmpty) {
      cartoes.add(Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text('Nada pendente 🎉', style: TextStyle(fontSize: 18, color: paleta.texto))),
      ));
    }
    if (feitas.isNotEmpty) {
      cartoes.add(_Cartao(
        titulo: '✅ Feitas hoje',
        fundo: paleta.fundoFeitas,
        borda: paleta.bordaFeitas,
        paleta: paleta,
        tarefas: feitas,
        corCheck: paleta.suave,
        onToque: onToque,
      ));
    }
    // physics sempre rolável: o puxar-para-sincronizar funciona com lista curta.
    // Folga embaixo para a barra de vidro não cobrir o último cartão.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 190),
      children: cartoes,
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.titulo,
    required this.fundo,
    required this.borda,
    required this.paleta,
    required this.tarefas,
    required this.corCheck,
    required this.onToque,
  });

  final String titulo;
  final Color fundo;
  final Color borda;
  final _Paleta paleta;
  final List<Tarefa> tarefas;
  final Color corCheck;
  final void Function(String id) onToque;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borda, width: 4),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: paleta.escuro ? 0.35 : 0.07), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(titulo, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: paleta.texto)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Divider(height: 1, color: paleta.suave.withValues(alpha: 0.3)),
          ),
          for (final t in tarefas) _Item(tarefa: t, paleta: paleta, corCheck: corCheck, onToque: onToque),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.tarefa, required this.paleta, required this.corCheck, required this.onToque});

  final Tarefa tarefa;
  final _Paleta paleta;
  final Color corCheck;
  final void Function(String id) onToque;

  @override
  Widget build(BuildContext context) {
    final t = tarefa;
    final cor = t.feita ? paleta.suave : paleta.texto;
    return InkWell(
      key: Key('item-${t.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => onToque(t.id),
      child: Row(children: [
        Transform.scale(
          scale: 1.25,
          child: Checkbox(
            value: t.feita,
            activeColor: corCheck,
            side: BorderSide(color: paleta.suave, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            onChanged: (_) => onToque(t.id),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.texto,
                  style: TextStyle(
                    fontSize: 16.5,
                    color: cor,
                    decoration: t.feita ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (t.prazo != null || t.origem != origemApp)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (t.prazo != null) '⏰ ${t.prazo}',
                        if (t.origem != origemApp) '🤖 ${t.origem}',
                      ].join('   '),
                      style: TextStyle(fontSize: 12.5, color: paleta.suave),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }
}

/// Pílula de vidro no rodapé (alcance do polegar): prazo opcional em cima,
/// e embaixo o emoji de prioridade, o texto e o botão +.
class _BarraAdicionar extends StatelessWidget {
  const _BarraAdicionar({
    required this.aberta,
    required this.onAbrir,
    required this.onFechar,
    required this.paleta,
    required this.texto,
    required this.prazo,
    required this.foco,
    required this.prioridade,
    required this.erro,
    required this.onPrioridade,
    required this.onAdicionar,
  });

  final bool aberta;
  final VoidCallback onAbrir;
  final VoidCallback onFechar;
  final _Paleta paleta;
  final TextEditingController texto;
  final TextEditingController prazo;
  final FocusNode foco;
  final Prioridade prioridade;
  final String? erro;
  final VoidCallback onPrioridade;
  final VoidCallback onAdicionar;

  InputDecoration _deco(String dica, {String? erro, Widget? icone}) => InputDecoration(
        hintText: dica,
        hintStyle: TextStyle(color: paleta.suave),
        errorText: erro,
        prefixIcon: icone,
        isDense: true,
        filled: true,
        fillColor: paleta.campo,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomRight,
      child: Align(
        alignment: Alignment.bottomRight,
        heightFactor: 1,
        child: aberta ? _barra(context) : _botaoMais(context),
      ),
    );
  }

  Widget _botaoMais(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Nova tarefa',
      child: InkWell(
        key: const Key('botao-abrir'),
        customBorder: const CircleBorder(),
        onTap: onAbrir,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary,
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Icon(Icons.add, color: cs.onPrimary, size: 30),
        ),
      ),
    );
  }

  Widget _barra(BuildContext context) {
    final destaque = paleta.borda(prioridade);
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: paleta.vidro,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: paleta.bordaVidro, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 52, bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('campo-prazo'),
                      controller: prazo,
                      maxLength: tamanhoMaxPrazo,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onAdicionar(),
                      style: TextStyle(fontSize: 14, color: paleta.texto),
                      decoration: _deco('Prazo, ex.: terça',
                          icone: Icon(Icons.schedule, size: 18, color: paleta.suave)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const Key('botao-fechar'),
                    tooltip: 'Recolher',
                    onPressed: onFechar,
                    icon: Icon(Icons.keyboard_arrow_down, color: paleta.suave),
                  ),
                ]),
              ),
              Row(children: [
                Tooltip(
                  message: 'Prioridade: ${prioridade.rotulo} (toque para trocar)',
                  child: InkWell(
                    key: const Key('botao-prioridade'),
                    customBorder: const CircleBorder(),
                    onTap: onPrioridade,
                    child: Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: destaque.withValues(alpha: 0.22),
                        border: Border.all(color: destaque, width: 2),
                      ),
                      child: Text(prioridade.emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('campo-texto'),
                    controller: texto,
                    focusNode: foco,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: tamanhoMaxTexto,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    onSubmitted: (_) => onAdicionar(),
                    style: TextStyle(fontSize: 16, color: paleta.texto),
                    decoration: _deco('Nova tarefa…', erro: erro),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  key: const Key('botao-adicionar'),
                  customBorder: const CircleBorder(),
                  onTap: onAdicionar,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.primary),
                    child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary, size: 28),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
