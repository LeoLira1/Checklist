import 'dart:async';

import 'package:libsql_dart/libsql_dart.dart';

import 'fonte_remota.dart';
import 'tarefa.dart';

/// Esquema da tabela nova. É o MESMO texto que o camda-mcp usa
/// (`src/tarefas.ts`): quem chegar primeiro cria, o outro só reaproveita.
const sqlCriarTabela = '''
CREATE TABLE IF NOT EXISTS tarefas (
  id TEXT PRIMARY KEY,
  texto TEXT NOT NULL,
  prioridade INTEGER NOT NULL DEFAULT 2,
  prazo TEXT,
  feita INTEGER NOT NULL DEFAULT 0,
  criada_em TEXT NOT NULL,
  concluida_em TEXT,
  origem TEXT NOT NULL DEFAULT 'app'
)''';

const sqlCriarIndice = 'CREATE INDEX IF NOT EXISTS idx_tarefas_feita ON tarefas (feita, prioridade)';

const sqlInserir = '''
INSERT OR IGNORE INTO tarefas (id, texto, prioridade, prazo, feita, criada_em, concluida_em, origem)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)''';

const sqlConcluir = "UPDATE tarefas SET feita = 1, concluida_em = COALESCE(NULLIF(concluida_em, ''), ?) WHERE id = ?";

const sqlReabrir = 'UPDATE tarefas SET feita = 0, concluida_em = NULL WHERE id = ?';

const sqlBaixar = '''
SELECT id, texto, prioridade, prazo, feita, criada_em, concluida_em, origem
FROM tarefas
WHERE feita = 0 OR substr(concluida_em, 1, 10) = ?''';

/// Fala com o Turso pelo `libsql_dart` (conexão remota, a mesma dependência
/// do Gondolas). Cada chamada tem prazo: sem rede o app não pode ficar preso.
class TursoRemoto implements FonteRemota {
  TursoRemoto(this.url, this.token, {this.prazo = const Duration(seconds: 12)});

  final String url;
  final String token;
  final Duration prazo;

  LibsqlClient? _client;
  bool _esquemaOk = false;

  Future<LibsqlClient> _conectar() async {
    var c = _client;
    if (c != null) return c;
    c = LibsqlClient.remote(url.trim(), authToken: token.trim());
    await c.connect();
    return _client = c;
  }

  /// Qualquer falha descarta a conexão: a próxima tentativa abre outra, em vez
  /// de insistir num socket que a rede móvel já derrubou.
  Future<T> _rodar<T>(Future<T> Function(LibsqlClient c) acao) async {
    try {
      return await (() async => acao(await _conectar()))().timeout(prazo);
    } catch (_) {
      final c = _client;
      _client = null;
      if (c != null) {
        unawaited(c.dispose().catchError((_) {}));
      }
      rethrow;
    }
  }

  @override
  Future<void> garantirEsquema() async {
    if (_esquemaOk) return;
    await _rodar((c) async {
      await c.execute(sqlCriarTabela);
      await c.execute(sqlCriarIndice);
    });
    _esquemaOk = true;
  }

  @override
  Future<void> aplicar(Operacao op) => _rodar((c) async {
        switch (op.tipo) {
          case TipoOperacao.criar:
            final t = op.tarefa!;
            await c.execute(sqlInserir, positional: [
              t.id,
              t.texto,
              t.prioridade.valor,
              t.prazo,
              t.feita ? 1 : 0,
              t.criadaEm,
              t.concluidaEm,
              t.origem,
            ]);
          case TipoOperacao.concluir:
            await c.execute(sqlConcluir, positional: [op.em, op.id]);
          case TipoOperacao.reabrir:
            await c.execute(sqlReabrir, positional: [op.id]);
        }
      });

  @override
  Future<List<Tarefa>> baixar(String hoje) => _rodar((c) async {
        final linhas = await c.query(sqlBaixar, positional: [hoje]);
        return linhas.map((l) => Tarefa.fromJson(Map<String, Object?>.from(l))).toList();
      });

  @override
  Future<void> fechar() async {
    final c = _client;
    _client = null;
    if (c != null) await c.dispose();
  }
}
