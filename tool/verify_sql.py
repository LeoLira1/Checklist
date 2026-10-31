#!/usr/bin/env python3
"""Roda os SQLs REAIS de lib/turso_remoto.dart num SQLite, na ordem em que o app
e o MCP os usam. O libsql_dart é nativo e não roda em `flutter test`, então
esta é a prova de que as instruções são válidas e fazem o que o README diz."""
import re
import sqlite3
import sys
from pathlib import Path

src = Path(__file__).resolve().parent.parent / "lib" / "turso_remoto.dart"
texto = src.read_text(encoding="utf-8")


def const(nome):
    m = re.search(r"const %s = (?:'''(.*?)'''|\"(.*?)\"|'(.*?)');" % nome, texto, re.S)
    assert m, f"constante {nome} não encontrada"
    return next(g for g in m.groups() if g is not None)


criar, indice, inserir, concluir, reabrir, baixar = (
    const(n) for n in ("sqlCriarTabela", "sqlCriarIndice", "sqlInserir", "sqlConcluir", "sqlReabrir", "sqlBaixar")
)

db = sqlite3.connect(":memory:")
# tabela do app de estoque: precisa ficar intacta
db.execute("CREATE TABLE divergencias (id INTEGER PRIMARY KEY, codigo TEXT)")
db.execute("INSERT INTO divergencias VALUES (1, '100')")
antes = db.execute("SELECT sql FROM sqlite_master WHERE name='divergencias'").fetchone()

for _ in range(2):  # IF NOT EXISTS: rodar duas vezes não pode falhar
    db.execute(criar)
    db.execute(indice)

cols = [r[1] for r in db.execute("PRAGMA table_info(tarefas)")]
assert cols == ["id", "texto", "prioridade", "prazo", "feita", "criada_em", "concluida_em", "origem"], cols

ins = lambda i, p, prazo, feita, conc: db.execute(
    inserir, [i, f"t{i}", p, prazo, feita, "2026-10-31 08:00:00", conc, "app"]
)
ins("a", 1, "terça", 0, None)
ins("a", 3, "outra", 0, None)  # OR IGNORE: reenvio não duplica nem sobrescreve
ins("b", 2, None, 0, None)
ins("c", 3, None, 0, None)
ins("velha", 1, None, 1, "2026-10-30 17:00:00")  # feita ontem
assert db.execute("SELECT COUNT(*) FROM tarefas").fetchone()[0] == 4  # a, b, c, velha
assert db.execute("SELECT prioridade, prazo FROM tarefas WHERE id='a'").fetchone() == (1, "terça")

db.execute(concluir, ["2026-10-31 09:00:00", "b"])
db.execute(concluir, ["2026-10-31 10:00:00", "b"])  # segunda vez mantém a primeira hora
assert db.execute("SELECT feita, concluida_em FROM tarefas WHERE id='b'").fetchone() == (1, "2026-10-31 09:00:00")

ids = sorted(r[0] for r in db.execute(baixar, ["2026-10-31"]))
assert ids == ["a", "b", "c"], ids  # pendentes + feitas de hoje; a de ontem fica de fora

db.execute(reabrir, ["b"])
assert db.execute("SELECT feita, concluida_em FROM tarefas WHERE id='b'").fetchone() == (0, None)

depois = db.execute("SELECT sql FROM sqlite_master WHERE name='divergencias'").fetchone()
assert antes == depois, "tabela existente foi alterada"
print("SQL do app OK")
sys.exit(0)
