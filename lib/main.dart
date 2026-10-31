import 'package:flutter/material.dart';

import 'armazenamento.dart';
import 'config_page.dart';
import 'repositorio.dart';
import 'tela_checklist.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final armazem = ArmazenamentoPrefs();
  final repo = RepositorioTarefas(armazem);
  // Só o cache local antes do primeiro quadro: a lista aparece na hora, sem
  // esperar rede. A conexão e o primeiro sync acontecem depois, na tela.
  await repo.carregar();
  await conectarSalvo(repo, armazem);
  runApp(ChecklistApp(repo: repo, armazem: armazem));
}

class ChecklistApp extends StatelessWidget {
  const ChecklistApp({super.key, required this.repo, required this.armazem, this.criarFonte = criarFontePadrao});

  final RepositorioTarefas repo;
  final Armazenamento armazem;
  final CriarFonte criarFonte;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Risca',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6B46)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E6B46), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system, // claro e pastel; escuro automático se o celular estiver no escuro
      home: TelaChecklist(repo: repo, armazem: armazem, criarFonte: criarFonte),
    );
  }
}
