import 'package:checklist_camda/armazenamento.dart';
import 'package:checklist_camda/fonte_remota.dart';
import 'package:checklist_camda/repositorio.dart';
import 'package:checklist_camda/tarefa.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fonte_falsa.dart';

// 2026-10-31 12:00 em Brasília = 15:00 UTC.
DateTime _agora = DateTime.utc(2026, 10, 31, 15, 0, 0);

Future<RepositorioTarefas> novo(ArmazenamentoMemoria arm, {FonteFalsa? fonte}) async {
  final r = RepositorioTarefas(arm, relogio: () => _agora);
  await r.carregar();
  if (fonte != null) await r.usarFonte(fonte);
  return r;
}

void main() {
  setUp(() => _agora = DateTime.utc(2026, 10, 31, 15, 0, 0));

  test('sem rede: adiciona e conclui na hora, fila guarda tudo', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa()..semRede = true;
    final r = await novo(arm, fonte: fonte);

    expect(await r.adicionar('  Separar   pedido do João ', Prioridade.urgente, prazo: ' terça '), isNull);
    expect(await r.adicionar('Limpar prateleira', Prioridade.quandoDer), isNull);
    await r.sincronizar(); // falha, não lança
    expect(r.erro, contains('sem rede'));
    expect(r.semEnviar, 2);
    expect(r.listaPendentes.map((t) => t.texto), ['Separar pedido do João', 'Limpar prateleira']);
    expect(r.listaPendentes.first.prazo, 'terça');
    expect(r.listaPendentes.first.criadaEm, '2026-10-31 12:00:00');
    expect(r.listaPendentes.first.origem, origemApp);

    await r.alternar(r.listaPendentes.first.id);
    expect(r.listaPendentes.length, 1);
    expect(r.listaFeitasHoje.single.texto, 'Separar pedido do João');
    expect(r.listaFeitasHoje.single.concluidaEm, '2026-10-31 12:00:00');
    expect(r.semEnviar, 3);
  });

  test('volta a rede: a fila sobe em ordem e esvazia', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa()..semRede = true;
    final r = await novo(arm, fonte: fonte);
    await r.adicionar('A', Prioridade.urgente);
    await r.adicionar('B', Prioridade.normal);
    await r.alternar(r.listaPendentes.first.id);

    fonte.semRede = false;
    expect(await r.sincronizar(), isTrue);
    expect(r.erro, isNull);
    expect(r.semEnviar, 0);
    expect(fonte.linhas.length, 2);
    expect(fonte.linhas.values.where((t) => t.feita).length, 1);
    expect(fonte.linhas.values.every((t) => t.origem == origemApp), isTrue);
  });

  test('queda no meio do envio: o que já subiu não sobe de novo, o resto espera', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa()..semRede = true;
    final r = await novo(arm, fonte: fonte);
    await r.adicionar('A', Prioridade.normal);
    await r.adicionar('B', Prioridade.normal);
    fonte.semRede = false;
    // deixa passar só a primeira operação
    final f2 = _CaiNaSegunda(fonte);
    await r.usarFonte(f2);
    expect(await r.sincronizar(), isFalse);
    expect(r.semEnviar, 1);
    expect(fonte.linhas.length, 1);
    await r.usarFonte(fonte);
    expect(await r.sincronizar(), isTrue);
    expect(fonte.linhas.length, 2);
    expect(r.semEnviar, 0);
  });

  test('puxa o que o Claude (MCP) lançou, com origem, e ordena junto das do app', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa();
    fonte.linhas['m1'] = daMcp('m1', 'Conferir lote do Roundup', Prioridade.urgente, prazo: 'hoje');
    final r = await novo(arm, fonte: fonte);
    await r.adicionar('Pedir etiquetas', Prioridade.normal);
    await r.sincronizar();

    final l = r.listaPendentes;
    expect(l.map((t) => t.texto), ['Conferir lote do Roundup', 'Pedir etiquetas']);
    expect(l.first.origem, origemMcp);
    expect(l.first.prazo, 'hoje');
  });

  test('sync não apaga o toque que ainda está na fila', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa();
    final r = await novo(arm, fonte: fonte);
    await r.adicionar('A', Prioridade.normal);
    await r.sincronizar();
    final id = r.listaPendentes.single.id;

    fonte.semRede = true;
    await r.alternar(id); // feita offline
    await r.sincronizar(); // falha
    expect(r.listaFeitasHoje.single.id, id);

    // o banco ainda diz "pendente", mas a fila manda no aparelho até subir
    fonte.semRede = false;
    await r.sincronizar();
    expect(r.listaFeitasHoje.single.id, id);
    expect(fonte.linhas[id]!.feita, isTrue);
  });

  test('concluída no outro aparelho/pelo MCP aparece em feitas hoje; reabrir volta', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa();
    final r = await novo(arm, fonte: fonte);
    await r.adicionar('A', Prioridade.normal);
    await r.sincronizar();
    final id = r.listaPendentes.single.id;

    fonte.linhas[id] = fonte.linhas[id]!.copyWith(feita: true, concluidaEm: '2026-10-31 13:00:00');
    await r.sincronizar();
    expect(r.listaPendentes, isEmpty);
    expect(r.listaFeitasHoje.single.id, id);

    await r.alternar(id); // desfazer
    expect(r.listaPendentes.single.id, id);
    await r.sincronizar();
    expect(fonte.linhas[id]!.feita, isFalse);
    expect(fonte.linhas[id]!.concluidaEm, isNull);
  });

  test('feita ontem some: sai de "feitas hoje" na virada e do cache no próximo sync', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa();
    final r = await novo(arm, fonte: fonte);
    await r.adicionar('A', Prioridade.normal);
    await r.alternar(r.listaPendentes.single.id);
    await r.sincronizar();
    expect(r.listaFeitasHoje.length, 1);

    _agora = DateTime.utc(2026, 11, 1, 15, 0, 0); // dia seguinte
    expect(r.listaFeitasHoje, isEmpty);
    await r.sincronizar();
    expect(r.tarefas, isEmpty);
    expect(fonte.linhas.length, 1, reason: 'continua no Turso como histórico');
  });

  test('cache do aparelho: reabrir o app mostra tudo na hora, fila incluída', () async {
    final arm = ArmazenamentoMemoria();
    final fonte = FonteFalsa()..semRede = true;
    final r1 = await novo(arm, fonte: fonte);
    await r1.adicionar('A', Prioridade.urgente, prazo: 'sexta');
    await r1.adicionar('B', Prioridade.normal);
    await r1.alternar(r1.listaPendentes.last.id);

    final r2 = await novo(arm); // app reaberto, sem rede nem banco configurado
    expect(r2.listaPendentes.map((t) => t.texto), ['A']);
    expect(r2.listaPendentes.single.prazo, 'sexta');
    expect(r2.listaFeitasHoje.map((t) => t.texto), ['B']);
    expect(r2.semEnviar, 3);

    fonte.semRede = false;
    await r2.usarFonte(fonte);
    expect(await r2.sincronizar(), isTrue);
    expect(fonte.linhas.length, 2);
  });

  test('cache corrompido não derruba o app', () async {
    final arm = ArmazenamentoMemoria()..dados['checklist_estado_v1'] = '{lixo';
    final r = await novo(arm);
    expect(r.tarefas, isEmpty);
  });

  test('validação: vazio, texto e prazo longos', () async {
    final r = await novo(ArmazenamentoMemoria());
    expect(await r.adicionar('   ', Prioridade.normal), isNotNull);
    expect(await r.adicionar('x' * 201, Prioridade.normal), contains('longa'));
    expect(await r.adicionar('ok', Prioridade.normal, prazo: 'p' * 41), contains('Prazo'));
    expect(await r.adicionar('ok', Prioridade.normal, prazo: '   '), isNull);
    expect(r.listaPendentes.single.prazo, isNull);
  });

  test('sem banco configurado funciona só local e não lança', () async {
    final r = await novo(ArmazenamentoMemoria());
    await r.adicionar('A', Prioridade.normal);
    expect(await r.sincronizar(), isFalse);
    expect(r.configurado, isFalse);
    expect(r.listaPendentes.length, 1);
  });
}

/// Deixa a primeira operação passar e derruba a segunda.
class _CaiNaSegunda extends FonteFalsa {
  _CaiNaSegunda(this.base);
  final FonteFalsa base;
  int n = 0;

  @override
  Future<void> garantirEsquema() => base.garantirEsquema();

  @override
  Future<void> aplicar(Operacao op) async {
    if (++n == 2) throw Exception('rede caiu');
    await base.aplicar(op);
  }

  @override
  Future<List<Tarefa>> baixar(String hoje) => base.baixar(hoje);
}
