import 'tarefa.dart';

/// Uma alteração feita no aparelho que ainda não chegou ao Turso. Cada uma é
/// idempotente (INSERT OR IGNORE / UPDATE por id), então reenviar depois de
/// uma queda no meio do envio não duplica nem estraga nada.
class Operacao {
  const Operacao.criar(Tarefa this.tarefa)
      : tipo = TipoOperacao.criar,
        id = null,
        em = null;
  const Operacao.concluir(String this.id, String this.em)
      : tipo = TipoOperacao.concluir,
        tarefa = null;
  const Operacao.reabrir(String this.id)
      : tipo = TipoOperacao.reabrir,
        tarefa = null,
        em = null;

  final TipoOperacao tipo;
  final Tarefa? tarefa;
  final String? id;
  final String? em;

  String get idTarefa => tarefa?.id ?? id!;

  Map<String, Object?> toJson() => {
        'tipo': tipo.name,
        if (tarefa != null) 'tarefa': tarefa!.toJson(),
        if (id != null) 'id': id,
        if (em != null) 'em': em,
      };

  factory Operacao.fromJson(Map<String, Object?> j) {
    final tipo = TipoOperacao.values.byName(j['tipo'] as String);
    switch (tipo) {
      case TipoOperacao.criar:
        return Operacao.criar(Tarefa.fromJson(Map<String, Object?>.from(j['tarefa'] as Map)));
      case TipoOperacao.concluir:
        return Operacao.concluir(j['id'] as String, j['em'] as String);
      case TipoOperacao.reabrir:
        return Operacao.reabrir(j['id'] as String);
    }
  }
}

enum TipoOperacao { criar, concluir, reabrir }

/// O Turso, visto pelo app. Troca-se por uma falsa nos testes.
abstract class FonteRemota {
  /// `CREATE TABLE IF NOT EXISTS tarefas` — só a tabela nova, nunca as do app de estoque.
  Future<void> garantirEsquema();

  Future<void> aplicar(Operacao op);

  /// Todas as pendentes + as concluídas em [hoje] (AAAA-MM-DD, Brasília).
  Future<List<Tarefa>> baixar(String hoje);

  Future<void> fechar();
}
