import 'package:checklist_camda/armazenamento.dart';
import 'package:checklist_camda/main.dart';
import 'package:checklist_camda/repositorio.dart';
import 'package:checklist_camda/tarefa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fonte_falsa.dart';

Future<(RepositorioTarefas, FonteFalsa)> subir(WidgetTester tester) async {
  final arm = ArmazenamentoMemoria();
  final fonte = FonteFalsa();
  final repo = RepositorioTarefas(arm);
  await repo.carregar();
  await repo.usarFonte(fonte);
  await tester.pumpWidget(ChecklistApp(repo: repo, armazem: arm));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('botao-abrir')));
  await tester.pumpAndSettle();
  return (repo, fonte);
}

String contador(WidgetTester t, String chave) => (t.widget(find.byKey(Key(chave))) as Text).data!;

void main() {
  testWidgets('adiciona com texto + botão de prioridade, ordena e conta', (tester) async {
    final (repo, fonte) = await subir(tester);
    expect(find.text('Nada pendente 🎉'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('campo-texto')), 'Quando der: varrer');
    await tester.tap(find.byKey(const Key('botao-prioridade'))); // 🟡 → 🟢
    await tester.tap(find.byKey(const Key('botao-prioridade'))); // 🟢 → 🔴
    await tester.tap(find.byKey(const Key('botao-prioridade'))); // 🔴 → 🟡
    await tester.tap(find.byKey(const Key('botao-prioridade'))); // 🟡 → 🟢
    await tester.tap(find.byKey(const Key('botao-adicionar')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('campo-texto')), 'Separar pedido');
    await tester.enterText(find.byKey(const Key('campo-prazo')), 'terça');
    await tester.tap(find.byKey(const Key('botao-prioridade'))); // 🟢 → 🔴
    await tester.tap(find.byKey(const Key('botao-adicionar')));
    await tester.pumpAndSettle();

    expect(contador(tester, 'contador-pendentes'), '2');
    expect(contador(tester, 'contador-feitas'), '0');
    expect(find.text('⏰ terça'), findsOneWidget);
    expect(find.text('🔴 Urgente'), findsOneWidget);
    expect(find.text('🟢 Quando der'), findsOneWidget);
    // urgente aparece acima da "quando der"
    expect(tester.getTopLeft(find.text('Separar pedido')).dy, lessThan(tester.getTopLeft(find.text('Quando der: varrer')).dy));
    // campo limpo e já sincronizado com o banco
    expect((tester.widget(find.byKey(const Key('campo-texto'))) as TextField).controller!.text, isEmpty);
    expect(fonte.linhas.length, 2);
  });

  testWidgets('tocar na linha risca e manda para "feitas hoje"; tocar de novo desfaz', (tester) async {
    final (repo, fonte) = await subir(tester);
    await repo.adicionar('Conferir carga', _p);
    await tester.pumpAndSettle();
    final id = repo.listaPendentes.single.id;

    await tester.tap(find.byKey(Key('item-$id')));
    await tester.pumpAndSettle();
    expect(contador(tester, 'contador-pendentes'), '0');
    expect(contador(tester, 'contador-feitas'), '1');
    expect(find.text('✅ Feitas hoje'), findsOneWidget);
    final texto = tester.widget<Text>(find.text('Conferir carga'));
    expect(texto.style!.decoration, TextDecoration.lineThrough);
    expect(fonte.linhas[id]!.feita, isTrue);

    await tester.tap(find.byKey(Key('item-$id')));
    await tester.pumpAndSettle();
    expect(contador(tester, 'contador-pendentes'), '1');
    expect(find.text('✅ Feitas hoje'), findsNothing);
  });

  testWidgets('tarefa lançada pelo Claude (MCP) aparece com a marca da origem', (tester) async {
    final (repo, fonte) = await subir(tester);
    fonte.linhas['m1'] = daMcp('m1', 'Ligar para a transportadora', _p, prazo: 'hoje');
    await repo.sincronizar();
    await tester.pumpAndSettle();
    expect(find.text('Ligar para a transportadora'), findsOneWidget);
    expect(find.textContaining('🤖 Claude (MCP)'), findsOneWidget);
  });

  testWidgets('sem banco configurado avisa e segue funcionando', (tester) async {
    final arm = ArmazenamentoMemoria();
    final repo = RepositorioTarefas(arm);
    await repo.carregar();
    await tester.pumpWidget(ChecklistApp(repo: repo, armazem: arm));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem banco'), findsOneWidget);
    await tester.tap(find.byKey(const Key('botao-abrir')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo-texto')), 'Anotar');
    await tester.tap(find.byKey(const Key('botao-adicionar')));
    await tester.pumpAndSettle();
    expect(contador(tester, 'contador-pendentes'), '1');
  });

  testWidgets('texto vazio mostra o erro e não adiciona', (tester) async {
    await subir(tester);
    await tester.tap(find.byKey(const Key('botao-adicionar')));
    await tester.pumpAndSettle();
    expect(find.text('Escreva a tarefa.'), findsOneWidget);
    expect(contador(tester, 'contador-pendentes'), '0');
  });

  testWidgets('barra começa recolhida (só o +) e recolhe de novo', (tester) async {
    final arm = ArmazenamentoMemoria();
    final repo = RepositorioTarefas(arm);
    await repo.carregar();
    await tester.pumpWidget(ChecklistApp(repo: repo, armazem: arm));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campo-texto')), findsNothing);
    await tester.tap(find.byKey(const Key('botao-abrir')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campo-texto')), findsOneWidget);
    await tester.tap(find.byKey(const Key('botao-fechar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campo-texto')), findsNothing);
  });
}

const _p = Prioridade.normal;