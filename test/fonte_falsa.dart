import 'package:checklist_camda/fonte_remota.dart';
import 'package:checklist_camda/tarefa.dart';

/// Turso de mentira: guarda as linhas em memória e aplica as operações com a
/// mesma semântica dos SQLs reais (OR IGNORE, COALESCE no concluir).
class FonteFalsa implements FonteRemota {
  final Map<String, Tarefa> linhas = {};
  bool semRede = false;
  int aplicadas = 0;
  int esquemas = 0;

  void _rede() {
    if (semRede) throw Exception('sem rede');
  }

  @override
  Future<void> garantirEsquema() async {
    _rede();
    esquemas++;
  }

  @override
  Future<void> aplicar(Operacao op) async {
    _rede();
    aplicadas++;
    switch (op.tipo) {
      case TipoOperacao.criar:
        linhas.putIfAbsent(op.tarefa!.id, () => op.tarefa!);
      case TipoOperacao.concluir:
        final t = linhas[op.id];
        if (t != null) {
          linhas[op.id!] = t.copyWith(feita: true, concluidaEm: t.concluidaEm ?? op.em);
        }
      case TipoOperacao.reabrir:
        final t = linhas[op.id];
        if (t != null) linhas[op.id!] = t.copyWith(feita: false, limparConclusao: true);
    }
  }

  @override
  Future<List<Tarefa>> baixar(String hoje) async {
    _rede();
    return linhas.values.where((t) => !t.feita || (t.concluidaEm ?? '').startsWith(hoje)).toList();
  }

  @override
  Future<void> fechar() async {}
}

/// Tarefa lançada pelo Claude (MCP) direto no banco.
Tarefa daMcp(String id, String texto, Prioridade p, {String criada = '2026-10-31 08:00:00', String? prazo}) =>
    Tarefa(id: id, texto: texto, prioridade: p, prazo: prazo, criadaEm: criada, origem: origemMcp);
