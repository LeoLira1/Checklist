# Risca

**Risca** é o checklist de **tarefas urgentes** da CAMDA, em tela única, feito para celular.
O [Mural](https://github.com/LeoLira1/camda-estoque) continua para o que é menos urgente.

- Lista por prioridade: 🔴 urgente · 🟡 normal · 🟢 quando der (dentro de cada uma, a mais antiga primeiro).
- Toque na linha (ou na caixinha) para riscar. A tarefa vai para **✅ Feitas hoje**; no dia seguinte some da tela (fica no Turso como histórico). Tocar de novo desfaz.
- Adicionar em 2 toques: escreva e toque em **+** (ou Enter). O botão do emoji troca a prioridade (🔴→🟡→🟢); fica na última escolhida para lançar várias seguidas. Prazo é opcional, texto livre (`terça`, `sexta 10h`).
- Contador no topo: pendentes e feitas hoje, mais o estado da sincronização.
- **Offline:** tudo grava primeiro no aparelho. As alterações entram numa fila e sobem para o Turso quando a rede volta (a cada 30 s com o app aberto, ao voltar para o app e ao puxar a lista para baixo).
- O que o Claude lança pelo MCP (`adicionar_tarefa`) aparece aqui com 🤖.

## Banco (Turso)

Mesmo banco do CAMDA Estoque, **uma tabela nova** `tarefas`. Nenhuma tabela existente é lida nem alterada.

| Coluna | Tipo | Conteúdo |
|---|---|---|
| `id` | TEXT PK | 8 caracteres hex, sorteados no aparelho (a tarefa nasce offline) |
| `texto` | TEXT | a tarefa |
| `prioridade` | INTEGER | 1 urgente · 2 normal · 3 quando der |
| `prazo` | TEXT | opcional, texto livre |
| `feita` | INTEGER | 0 / 1 |
| `criada_em` | TEXT | horário de Brasília, `AAAA-MM-DD HH:MM:SS` |
| `concluida_em` | TEXT | idem, vazio enquanto pendente |
| `origem` | TEXT | `app` ou `Claude (MCP)` |

A tabela é criada sozinha (`CREATE TABLE IF NOT EXISTS`) no primeiro sync, tanto pelo app quanto pelo MCP.
As operações do app são idempotentes (`INSERT OR IGNORE`, `UPDATE` por id): reenviar depois de uma queda no meio não duplica nada.

### Onde fica o token

Igual ao Gondolas: **só no aparelho**. Na primeira abertura, toque em ⚙️ e informe a URL (`libsql://...turso.io`) e o token do Turso;
ficam no `shared_preferences` (chaves `turso_db_url` e `turso_db_token`). Nada vai para o repositório nem para o APK.
Use o mesmo token que você já usa no Gondolas, ou crie um só para este app no painel do Turso (um token com acesso de escrita é necessário).

## Gerar o APK pelo celular (sem PC)

Mesmo fluxo do Gondolas: GitHub Actions.

1. No navegador do celular, abra `github.com/LeoLira1/Checklist` → aba **Actions** → **Build & Release APK** → **Run workflow** → escolha a branch → **Run workflow**.
   (Todo push em `main` ou na branch `ccr-6d500a04-jega9y` também dispara o build sozinho.)
2. Espere uns 5–10 min até a bolinha ficar verde. Se ficar vermelha, abra o job e veja o passo que falhou (o build roda `flutter analyze`, `flutter test` e a verificação do SQL antes de gerar o APK).
3. Abra a aba **Releases** (ou a página inicial do repo → *Releases*) → a mais recente (`Risca #N`) → toque em **app-release.apk** para baixar.
4. Abra o arquivo baixado e instale. Na primeira vez o Android pede para permitir instalar apps do navegador/Arquivos.
5. Abra **Risca** → ⚙️ → URL + token → **Testar** → **Salvar**.

O pacote é `com.camda.checklist_camda`, diferente do Gondolas, então os dois convivem no celular.

### Atualizar por cima (assinatura fixa — opcional)

Sem configurar nada, cada build sai com uma assinatura nova e o Android recusa a atualização por cima ("App não foi instalado"): desinstale e instale de novo
(a lista sincronizada volta do Turso; só o que estava na fila offline se perde). É a mesma limitação do Gondolas.
Para o APK novo atualizar o antigo, cadastre o secret `DEBUG_KEYSTORE_BASE64` (conteúdo do `debug.keystore` em base64) em
*Settings → Secrets and variables → Actions*; o workflow restaura essa chave antes do build.

## Desenvolvimento

```bash
flutter pub get
flutter analyze
flutter test               # modelo, fila offline, mesclagem, virada de dia e tela
python3 tool/verify_sql.py # roda os SQLs reais do app num SQLite
flutter run
```

O projeto Android **não fica no repositório**: o workflow o gera com `flutter create` (como no Gondolas).

| Arquivo | O que é |
|---|---|
| `lib/tarefa.dart` | modelo, prioridades, ordenação, horário de Brasília |
| `lib/repositorio.dart` | lista local + fila de operações + sincronização |
| `lib/turso_remoto.dart` | SQL e conexão `libsql_dart` |
| `lib/tela_checklist.dart` | a tela única |
| `lib/config_page.dart` | ⚙️ URL + token |
| `test/` | testes (fonte remota falsa em `test/fonte_falsa.dart`) |

## MCP

As ferramentas `adicionar_tarefa`, `ver_tarefas` e `concluir_tarefa` ficam no repositório
[camda-mcp](https://github.com/LeoLira1/camda-mcp) (`src/tarefas.ts`), gravando na mesma tabela com `origem = "Claude (MCP)"`.
