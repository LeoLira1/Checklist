import 'dart:math';

/// Prioridade da tarefa. O número é o que vai para a coluna `prioridade`
/// do Turso (1 = mais urgente), então ordenar por ele já ordena a lista.
enum Prioridade {
  urgente(1, '🔴', 'Urgente'),
  normal(2, '🟡', 'Normal'),
  quandoDer(3, '🟢', 'Quando der');

  const Prioridade(this.valor, this.emoji, this.rotulo);
  final int valor;
  final String emoji;
  final String rotulo;

  /// Valor desconhecido vira `normal`: uma linha estranha no banco não pode
  /// derrubar a tela.
  static Prioridade doValor(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    for (final p in values) {
      if (p.valor == n) return p;
    }
    return Prioridade.normal;
  }

  /// Ciclo do botão de prioridade: 🔴 → 🟡 → 🟢 → 🔴.
  Prioridade get proxima => values[(index + 1) % values.length];
}

const origemApp = 'app';
const origemMcp = 'Claude (MCP)';

/// Horário de Brasília ("AAAA-MM-DD HH:MM:SS"), o mesmo formato que o MCP e
/// o app de estoque usam em `criado_em`. Brasília não tem horário de verão
/// desde 2019, então UTC−3 fixo é exato — e não depende do fuso do aparelho.
String agoraBrt([DateTime? agora]) {
  final d = (agora ?? DateTime.now()).toUtc().subtract(const Duration(hours: 3));
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${dois(d.month)}-${dois(d.day)} '
      '${dois(d.hour)}:${dois(d.minute)}:${dois(d.second)}';
}

/// "AAAA-MM-DD" de hoje em Brasília.
String hojeBrt([DateTime? agora]) => agoraBrt(agora).substring(0, 10);

/// Identificador curto (8 hex) sorteado no aparelho. A tarefa nasce offline,
/// então o id não pode vir do banco (AUTOINCREMENT); 32 bits bastam para uma
/// lista de dezenas de tarefas, e o INSERT é `OR IGNORE` por segurança.
String novoId([Random? r]) {
  final rnd = r ?? Random.secure();
  return List.generate(8, (_) => rnd.nextInt(16).toRadixString(16)).join();
}

class Tarefa {
  const Tarefa({
    required this.id,
    required this.texto,
    required this.prioridade,
    this.prazo,
    this.feita = false,
    required this.criadaEm,
    this.concluidaEm,
    this.origem = origemApp,
  });

  final String id;
  final String texto;
  final Prioridade prioridade;
  final String? prazo;
  final bool feita;
  final String criadaEm;
  final String? concluidaEm;
  final String origem;

  Tarefa copyWith({Prioridade? prioridade, bool? feita, String? concluidaEm, bool limparConclusao = false}) =>
      Tarefa(
        id: id,
        texto: texto,
        prioridade: prioridade ?? this.prioridade,
        prazo: prazo,
        feita: feita ?? this.feita,
        criadaEm: criadaEm,
        concluidaEm: limparConclusao ? null : (concluidaEm ?? this.concluidaEm),
        origem: origem,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'texto': texto,
        'prioridade': prioridade.valor,
        'prazo': prazo,
        'feita': feita ? 1 : 0,
        'criada_em': criadaEm,
        'concluida_em': concluidaEm,
        'origem': origem,
      };

  /// Serve tanto para o JSON do cache local quanto para a linha do Turso.
  factory Tarefa.fromJson(Map<String, Object?> j) {
    String? vazioNulo(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final f = j['feita'];
    return Tarefa(
      id: j['id'].toString(),
      texto: (j['texto'] ?? '').toString(),
      prioridade: Prioridade.doValor(j['prioridade']),
      prazo: vazioNulo(j['prazo']),
      feita: f == true || (f is num && f != 0) || f == '1',
      criadaEm: (j['criada_em'] ?? '').toString(),
      concluidaEm: vazioNulo(j['concluida_em']),
      origem: vazioNulo(j['origem']) ?? origemApp,
    );
  }
}

/// Pendentes: urgente primeiro, depois normal, depois "quando der"; dentro de
/// cada prioridade, a mais antiga primeiro (o que está esperando há mais tempo).
List<Tarefa> pendentes(Iterable<Tarefa> todas) {
  final l = todas.where((t) => !t.feita).toList();
  l.sort((a, b) {
    final p = a.prioridade.valor.compareTo(b.prioridade.valor);
    if (p != 0) return p;
    final c = a.criadaEm.compareTo(b.criadaEm);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return l;
}

/// Concluídas no dia [hoje] (AAAA-MM-DD, Brasília), a mais recente primeiro.
List<Tarefa> feitasHoje(Iterable<Tarefa> todas, String hoje) {
  final l = todas.where((t) => t.feita && (t.concluidaEm ?? '').startsWith(hoje)).toList();
  l.sort((a, b) => (b.concluidaEm ?? '').compareTo(a.concluidaEm ?? ''));
  return l;
}
