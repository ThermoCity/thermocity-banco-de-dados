"""Conexão com o Oracle e execução dos arquivos .sql.

Credenciais nunca vão no código: variáveis de ambiente DB_USER, DB_PASSWORD e DB_DSN,
ou um arquivo .env na raiz do repositório (veja .env.example).
"""
from __future__ import annotations

import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def carregar_env() -> None:
    caminho = os.path.join(RAIZ, ".env")
    if not os.path.exists(caminho):
        return
    with open(caminho, encoding="utf-8") as f:
        for linha in f:
            linha = linha.strip()
            if linha and not linha.startswith("#") and "=" in linha:
                k, v = linha.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def conectar():
    import oracledb  # só exigido quando realmente vai ao banco

    carregar_env()
    faltando = [v for v in ("DB_USER", "DB_PASSWORD", "DB_DSN") if not os.environ.get(v)]
    if faltando:
        sys.exit(f"Defina as variáveis de ambiente {', '.join(faltando)} (ou crie o arquivo .env).")
    return oracledb.connect(user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"],
                            dsn=os.environ["DB_DSN"])


def comandos_sql(caminho: str) -> list[str]:
    """Divide um arquivo .sql em comandos: tira linhas de comentário e corta no ';' de fim de linha."""
    comandos, atual = [], []
    with open(caminho, encoding="utf-8") as f:
        for linha in f:
            limpa = linha.strip()
            if not limpa or limpa.startswith("--"):
                continue
            if limpa.endswith(";"):
                atual.append(linha.rstrip().rstrip(";"))
                comandos.append("\n".join(atual).strip())
                atual = []
            else:
                atual.append(linha.rstrip())
    if any(l.strip() for l in atual):
        comandos.append("\n".join(atual).strip())
    return comandos


def executar_arquivo(cur, caminho: str, ignorar_inexistente: bool = False) -> int:
    """Executa todos os comandos do arquivo. Com ignorar_inexistente, pula 'tabela não existe'."""
    import oracledb

    n = 0
    for sql in comandos_sql(caminho):
        try:
            cur.execute(sql)
            n += 1
        except oracledb.DatabaseError as e:
            if ignorar_inexistente and ("ORA-00942" in str(e) or "ORA-02289" in str(e)):
                continue
            raise
    return n


def tabelas_existentes(cur) -> set[str]:
    return {t for (t,) in cur.execute("SELECT TABLE_NAME FROM USER_TABLES WHERE TABLE_NAME LIKE 'TMC\\_%' ESCAPE '\\'")}
