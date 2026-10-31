import 'dart:async';

import 'package:flutter/material.dart';

import 'armazenamento.dart';
import 'config_page.dart';
import 'repositorio.dart';
import 'tarefa.dart';

const _corPrioridade = {
  Prioridade.urgente: Color(0xFFE53935),
  Prioridade.normal: Color(0xFFFFB300),
  Prioridade.quandoDer: Color(0xFF43A047),
};

/// Tela única: contador, campo de adicionar e a lista.
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

  Future<void> _abrirConfig() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConfigPage(repo: repo, armazem: widget.armazem, criar: widget.criarFonte),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: repo,
          builder: (context, _) {
            final pend = repo.listaPendentes;
            final feitas = repo.listaFeitasHoje;
            return Column(
              children: [
                _Topo(
                  pendentes: pend.length,
                  feitas: feitas.length,
                  repo: repo,
                  onConfig: _abrirConfig,
                  onSync: repo.sincronizar,
                ),
                _Adicionar(
                  texto: _texto,
                  prazo: _prazo,
                  foco: _focoTexto,
                  prioridade: _prioridade,
                  erro: _erroCampo,
                  onPrioridade: () => setState(() => _prioridade = _prioridade.proxima),
                  onAdicionar: _adicionar,
                ),
                const Divider(height: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: repo.sincronizar,
                    child: _Lista(pendentes: pend, feitas: feitas, onToque: repo.alternar),
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
    required this.pendentes,
    required this.feitas,
    required this.repo,
    required this.onConfig,
    required this.onSync,
  });

  final int pendentes;
  final int feitas;
  final RepositorioTarefas repo;
  final VoidCallback onConfig;
  final Future<bool> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    String estado;
    IconData icone;
    Color cor;
    if (!repo.configurado) {
      estado = 'Sem banco — toque em ⚙️';
      icone = Icons.cloud_off;
      cor = Colors.orangeAccent;
    } else if (repo.sincronizando) {
      estado = 'Sincronizando…';
      icone = Icons.sync;
      cor = tema.colorScheme.primary;
    } else if (repo.erro != null) {
      estado = repo.semEnviar > 0 ? 'Offline · ${repo.semEnviar} p/ enviar' : 'Offline';
      icone = Icons.cloud_off;
      cor = Colors.orangeAccent;
    } else {
      estado = repo.semEnviar > 0 ? '${repo.semEnviar} p/ enviar' : 'Sincronizado';
      icone = Icons.cloud_done;
      cor = Colors.greenAccent;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$pendentes',
                        key: const Key('contador-pendentes'),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const Text(' pendentes  ·  '),
                    Text('$feitas',
                        key: const Key('contador-feitas'),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const Text(' feitas hoje'),
                  ],
                ),
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
          ),
          IconButton(key: const Key('botao-config'), icon: const Icon(Icons.settings), onPressed: onConfig),
        ],
      ),
    );
  }
}

class _Adicionar extends StatelessWidget {
  const _Adicionar({
    required this.texto,
    required this.prazo,
    required this.foco,
    required this.prioridade,
    required this.erro,
    required this.onPrioridade,
    required this.onAdicionar,
  });

  final TextEditingController texto;
  final TextEditingController prazo;
  final FocusNode foco;
  final Prioridade prioridade;
  final String? erro;
  final VoidCallback onPrioridade;
  final VoidCallback onAdicionar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          Row(children: [
            Tooltip(
              message: 'Prioridade: ${prioridade.rotulo} (toque para trocar)',
              child: InkWell(
                key: const Key('botao-prioridade'),
                borderRadius: BorderRadius.circular(24),
                onTap: onPrioridade,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: Text(prioridade.emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
            ),
            const SizedBox(width: 4),
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
                decoration: InputDecoration(
                  hintText: 'Nova tarefa…',
                  errorText: erro,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('botao-adicionar'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48), padding: EdgeInsets.zero),
              onPressed: onAdicionar,
              child: const Icon(Icons.add),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 52),
            Expanded(
              child: TextField(
                key: const Key('campo-prazo'),
                controller: prazo,
                maxLength: tamanhoMaxPrazo,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdicionar(),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Prazo (opcional) — ex.: terça',
                  prefixIcon: Icon(Icons.schedule, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 56),
          ]),
        ],
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.pendentes, required this.feitas, required this.onToque});

  final List<Tarefa> pendentes;
  final List<Tarefa> feitas;
  final void Function(String id) onToque;

  @override
  Widget build(BuildContext context) {
    final itens = <Widget>[];
    Prioridade? grupo;
    for (final t in pendentes) {
      if (t.prioridade != grupo) {
        grupo = t.prioridade;
        itens.add(_Cabecalho('${grupo.emoji} ${grupo.rotulo}'));
      }
      itens.add(_Item(tarefa: t, onToque: onToque));
    }
    if (pendentes.isEmpty) {
      itens.add(const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Nada pendente 🎉', style: TextStyle(fontSize: 18))),
      ));
    }
    if (feitas.isNotEmpty) {
      itens.add(const _Cabecalho('✅ Feitas hoje'));
      for (final t in feitas) {
        itens.add(_Item(tarefa: t, onToque: onToque));
      }
    }
    // physics sempre rolável: o puxar-para-sincronizar funciona com lista curta.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: itens,
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(texto, style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 0.5)),
      );
}

class _Item extends StatelessWidget {
  const _Item({required this.tarefa, required this.onToque});

  final Tarefa tarefa;
  final void Function(String id) onToque;

  @override
  Widget build(BuildContext context) {
    final t = tarefa;
    final cor = _corPrioridade[t.prioridade]!;
    final fundo = t.feita ? Theme.of(context).disabledColor : null;
    return InkWell(
      key: Key('item-${t.id}'),
      onTap: () => onToque(t.id),
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: t.feita ? Colors.transparent : cor, width: 4))),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Transform.scale(
            scale: 1.3,
            child: Checkbox(
              value: t.feita,
              activeColor: cor,
              onChanged: (_) => onToque(t.id),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.texto,
                    style: TextStyle(
                      fontSize: 17,
                      color: fundo,
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
                        style: TextStyle(fontSize: 12, color: fundo ?? Theme.of(context).hintColor),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ]),
      ),
    );
  }
}
