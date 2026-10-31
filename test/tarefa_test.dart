import 'package:checklist_camda/tarefa.dart';
import 'package:flutter_test/flutter_test.dart';

Tarefa t(String id, Prioridade p, String criada, {bool feita = false, String? conc}) =>
    Tarefa(id: id, texto: id, prioridade: p, criadaEm: criada, feita: feita, concluidaEm: conc);

void main() {
  test('horário de Brasília é UTC-3, independente do fuso do aparelho', () {
    expect(agoraBrt(DateTime.utc(2026, 10, 31, 2, 30, 5)), '2026-10-30 23:30:05');
    expect(hojeBrt(DateTime.utc(2026, 10, 31, 2, 59)), '2026-10-30');
    expect(hojeBrt(DateTime.utc(2026, 10, 31, 3, 0)), '2026-10-31');
  });

  test('pendentes: urgente, normal, quando der; dentro da prioridade a mais antiga primeiro', () {
    final l = pendentes([
      t('c', Prioridade.quandoDer, '2026-10-31 08:00:00'),
      t('b2', Prioridade.normal, '2026-10-31 09:00:00'),
      t('a2', Prioridade.urgente, '2026-10-31 10:00:00'),
      t('b1', Prioridade.normal, '2026-10-31 07:00:00'),
      t('a1', Prioridade.urgente, '2026-10-31 06:00:00'),
      t('feita', Prioridade.urgente, '2026-10-31 05:00:00', feita: true, conc: '2026-10-31 11:00:00'),
    ]);
    expect(l.map((e) => e.id), ['a1', 'a2', 'b1', 'b2', 'c']);
  });

  test('feitasHoje: só as de hoje, a mais recente primeiro', () {
    final l = feitasHoje([
      t('ontem', Prioridade.normal, '2026-10-29 08:00:00', feita: true, conc: '2026-10-30 18:00:00'),
      t('manha', Prioridade.normal, '2026-10-31 07:00:00', feita: true, conc: '2026-10-31 09:00:00'),
      t('tarde', Prioridade.urgente, '2026-10-31 07:00:00', feita: true, conc: '2026-10-31 15:00:00'),
      t('aberta', Prioridade.urgente, '2026-10-31 07:00:00'),
    ], '2026-10-31');
    expect(l.map((e) => e.id), ['tarde', 'manha']);
  });

  test('prioridade desconhecida vira normal; botão gira 🔴→🟡→🟢→🔴', () {
    expect(Prioridade.doValor(1), Prioridade.urgente);
    expect(Prioridade.doValor('3'), Prioridade.quandoDer);
    expect(Prioridade.doValor(99), Prioridade.normal);
    expect(Prioridade.doValor(null), Prioridade.normal);
    expect(Prioridade.urgente.proxima, Prioridade.normal);
    expect(Prioridade.quandoDer.proxima, Prioridade.urgente);
  });

  test('linha do Turso: feita 0/1, prazo vazio vira nulo, origem vazia vira app', () {
    final a = Tarefa.fromJson({
      'id': 'x1',
      'texto': 'Ligar para o fornecedor',
      'prioridade': 1,
      'prazo': '',
      'feita': 1,
      'criada_em': '2026-10-31 08:00:00',
      'concluida_em': '2026-10-31 09:00:00',
      'origem': '',
    });
    expect(a.feita, isTrue);
    expect(a.prazo, isNull);
    expect(a.origem, origemApp);
    expect(Tarefa.fromJson(a.toJson()).toJson(), a.toJson());
  });

  test('novoId: 8 hex e diferente a cada chamada', () {
    final ids = {for (var i = 0; i < 200; i++) novoId()};
    expect(ids.length, 200);
    expect(ids.every((e) => RegExp(r'^[0-9a-f]{8}$').hasMatch(e)), isTrue);
  });
}
