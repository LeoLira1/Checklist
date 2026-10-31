import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'armazenamento.dart';
import 'fonte_remota.dart';
import 'tarefa.dart';

const _chaveEstado = 'checklist_estado_v1';
const tamanhoMaxTexto = 200;
const tamanhoMaxPrazo = 40;

/// Dono da lista. A tela só lê daqui e chama [adicionar]/[alternar]:
/// tudo grava primeiro no aparelho (instantâneo, funciona sem rede) e entra
/// numa fila de [Operacao]; [sincronizar] esvazia a fila no Turso e puxa o
/// que o Claude (MCP) ou outro aparelho mexeu.
class RepositorioTarefas extends ChangeNotifier {
  RepositorioTarefas(this._armazem, {DateTime Function()? relogio}) : _agora = relogio ?? DateTime.now;

  final Armazenamento _armazem;
  final DateTime Function() _agora;

  FonteRemota? _fonte;
  List<Tarefa> _tarefas = [];
  final List<Operacao> _fila = [];

  bool _sincronizando = false;
  bool _repetir = false;
  Future<bool>? _emAndamento;
  String? _erro;
  DateTime? _ultimaSync;

  List<Tarefa> get tarefas => List.unmodifiable(_tarefas);
  List<Tarefa> get listaPendentes => pendentes(_tarefas);
  List<Tarefa> get listaFeitasHoje => feitasHoje(_tarefas, hojeBrt(_agora()));
  int get semEnviar => _fila.length;
  bool get sincronizando => _sincronizando;
  bool get configurado => _fonte != null;
  String? get erro => _erro;
  DateTime? get ultimaSync => _ultimaSync;

  /// Troca o banco (primeira configuração ou token novo). A fila fica: o que
  /// foi feito offline ainda precisa subir para o banco novo.
  Future<void> usarFonte(FonteRemota? fonte) async {
    final antiga = _fonte;
    _fonte = fonte;
    _erro = null;
    if (antiga != null) {
      try {
        await antiga.fechar();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Lê o cache do aparelho. É o que faz o app abrir instantâneo: a tela
  /// aparece com a lista de ontem à noite antes de qualquer rede.
  Future<void> carregar() async {
    final bruto = await _armazem.ler(_chaveEstado);
    if (bruto != null) {
      try {
        final j = json.decode(bruto) as Map<String, dynamic>;
        _tarefas = [
          for (final t in (j['tarefas'] as List? ?? const [])) Tarefa.fromJson(Map<String, Object?>.from(t as Map)),
        ];
        _fila
          ..clear()
          ..addAll([
            for (final o in (j['fila'] as List? ?? const [])) Operacao.fromJson(Map<String, Object?>.from(o as Map)),
          ]);
        final s = j['ultima_sync'] as String?;
        _ultimaSync = s == null ? null : DateTime.tryParse(s);
      } catch (_) {
        // Cache ilegível: recomeça vazio, o próximo sync repõe a lista.
        _tarefas = [];
        _fila.clear();
      }
    }
    _descartarAntigas();
    notifyListeners();
  }

  /// Concluída em dia anterior "some" daqui; continua no Turso como histórico.
  void _descartarAntigas() {
    final hoje = hojeBrt(_agora());
    _tarefas = _tarefas.where((t) => !t.feita || (t.concluidaEm ?? '').startsWith(hoje)).toList();
  }

  Future<void> _salvar() => _armazem.gravar(
        _chaveEstado,
        json.encode({
          'tarefas': _tarefas.map((t) => t.toJson()).toList(),
          'fila': _fila.map((o) => o.toJson()).toList(),
          'ultima_sync': _ultimaSync?.toIso8601String(),
        }),
      );

  /// Devolve a mensagem de erro de validação, ou null se adicionou.
  Future<String?> adicionar(String texto, Prioridade prioridade, {String? prazo}) async {
    final t = texto.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'Escreva a tarefa.';
    if (t.length > tamanhoMaxTexto) return 'Tarefa muito longa (máx. $tamanhoMaxTexto letras).';
    final p = prazo?.trim();
    if (p != null && p.length > tamanhoMaxPrazo) return 'Prazo muito longo (máx. $tamanhoMaxPrazo letras).';
    final nova = Tarefa(
      id: novoId(),
      texto: t,
      prioridade: prioridade,
      prazo: (p == null || p.isEmpty) ? null : p,
      criadaEm: agoraBrt(_agora()),
    );
    _tarefas = [..._tarefas, nova];
    _fila.add(Operacao.criar(nova));
    await _salvar();
    notifyListeners();
    unawaited(sincronizar());
    return null;
  }

  /// Toca na caixinha: pendente vira feita (vai para "feitas hoje"); feita
  /// volta a pendente (desfazer um toque errado).
  Future<void> alternar(String id) async {
    final i = _tarefas.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = _tarefas[i];
    final lista = [..._tarefas];
    if (t.feita) {
      lista[i] = t.copyWith(feita: false, limparConclusao: true);
      _fila.add(Operacao.reabrir(id));
    } else {
      final em = agoraBrt(_agora());
      lista[i] = t.copyWith(feita: true, concluidaEm: em);
      _fila.add(Operacao.concluir(id, em));
    }
    _tarefas = lista;
    await _salvar();
    notifyListeners();
    unawaited(sincronizar());
  }

  /// Envia a fila e puxa o banco. Nunca lança: sem rede vira [erro] e a fila
  /// espera. Devolve true se sincronizou. Chamada durante um sync em andamento
  /// não empilha outro: pede uma repetição (para pegar o que acabou de entrar
  /// na fila) e devolve o mesmo resultado, só quando tudo terminar.
  Future<bool> sincronizar() {
    final fonte = _fonte;
    if (fonte == null) return Future.value(false);
    final andando = _emAndamento;
    if (andando != null) {
      _repetir = true;
      return andando;
    }
    return _emAndamento = _sincronizar(fonte).whenComplete(() => _emAndamento = null);
  }

  Future<bool> _sincronizar(FonteRemota fonte) async {
    _sincronizando = true;
    notifyListeners();
    var ok = false;
    // Repete enquanto alguém pedir durante a rodada (inclusive depois de uma
    // falha: quem pediu quer uma tentativa que comece depois do pedido).
    do {
      _repetir = false;
      try {
        await fonte.garantirEsquema();
        while (_fila.isNotEmpty) {
          await fonte.aplicar(_fila.first);
          _fila.removeAt(0);
          await _salvar();
        }
        final remotas = await fonte.baixar(hojeBrt(_agora()));
        _mesclar(remotas);
        _ultimaSync = _agora();
        _erro = null;
        ok = true;
        await _salvar();
      } catch (e) {
        _erro = _mensagem(e);
        ok = false;
      }
    } while (_repetir);
    _sincronizando = false;
    notifyListeners();
    return ok;
  }

  /// O banco manda, exceto nas tarefas que ainda têm operação na fila: essas
  /// ficam como estão no aparelho, senão o sync apagaria o toque que acabou de
  /// ser feito. Roda sem `await`, logo nada entra na fila no meio da mesclagem.
  void _mesclar(List<Tarefa> remotas) {
    final naFila = _fila.map((o) => o.idTarefa).toSet();
    final locais = {for (final t in _tarefas) t.id: t};
    final nova = <Tarefa>[
      for (final r in remotas)
        if (!naFila.contains(r.id)) r,
      for (final id in naFila)
        if (locais[id] != null) locais[id]!,
    ];
    _tarefas = nova;
    _descartarAntigas();
  }

  String _mensagem(Object e) {
    final s = e.toString();
    if (e is Exception && s.startsWith('Exception: ')) return s.substring(11);
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}
