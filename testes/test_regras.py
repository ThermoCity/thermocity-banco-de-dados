"""Testes sem banco do épico 83: estrutura dos scripts PL/SQL e MongoDB e a regra de pontuação.

Rodar (na raiz):  py -m unittest discover -s testes -v
Os testes COM banco estão em sql/regras/07_testes.sql (rodam no Oracle).
"""
import json
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "carga"))

import gerar_epico_banco as g  # noqa: E402

RAIZ = g.RAIZ
REGRAS = os.path.join(RAIZ, "sql", "regras")


def ler(*partes) -> str:
    with open(os.path.join(RAIZ, *partes), encoding="utf-8") as f:
        return f.read()


class TestObjetosPlsql(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.prio = ler("sql", "regras", "03_pkg_priorizacao.sql")
        cls.cont = ler("sql", "regras", "04_pkg_contato.sql")
        cls.gat = ler("sql", "regras", "05_gatilhos.sql")
        cls.blocos = ler("sql", "regras", "06_blocos_anonimos.sql")

    def test_dois_pacotes_com_specification_e_body(self):
        for texto, nome in [(self.prio, "PKG_PRIORIZACAO"), (self.cont, "PKG_CONTATO")]:
            self.assertRegex(texto, rf"CREATE OR REPLACE PACKAGE {nome} AS")
            self.assertRegex(texto, rf"CREATE OR REPLACE PACKAGE BODY {nome} AS")
            self.assertEqual(len(re.findall(r"^/\s*$", texto, re.M)), 2, f"{nome}: spec e body terminam com /")

    def test_funcoes_e_procedimentos_publicos(self):
        spec = lambda t: t.split("CREATE OR REPLACE PACKAGE BODY")[0]  # noqa: E731
        funcoes = re.findall(r"^\s+FUNCTION (\w+)", spec(self.prio) + spec(self.cont), re.M)
        procs = re.findall(r"^\s+PROCEDURE (\w+)", spec(self.prio) + spec(self.cont), re.M)
        self.assertGreaterEqual(len(funcoes), 2)
        self.assertGreaterEqual(len(procs), 2)
        for nome in ["fn_pontuacao", "fn_nivel_vigente", "fn_cobertura_ubs"]:
            self.assertIn(nome, funcoes)
        for nome in ["prc_gerar_lista_dia", "prc_registrar_contato"]:
            self.assertIn(nome, procs)

    def test_tudo_que_esta_na_spec_tem_corpo(self):
        for texto in [self.prio, self.cont]:
            spec, corpo = texto.split("CREATE OR REPLACE PACKAGE BODY")
            for tipo, nome in re.findall(r"^\s+(FUNCTION|PROCEDURE) (\w+)", spec, re.M):
                self.assertRegex(corpo, rf"{tipo} {nome} ", nome)
                self.assertRegex(corpo, rf"END {nome};", nome)

    def test_rotinas_nao_fazem_commit(self):
        for texto in [self.prio, self.cont, self.gat]:
            codigo = "\n".join(l for l in texto.splitlines() if not l.strip().startswith("--"))
            self.assertNotRegex(codigo, r"\bCOMMIT\b")

    def test_dois_gatilhos_um_de_auditoria(self):
        nomes = re.findall(r"CREATE OR REPLACE TRIGGER (\w+)", self.gat)
        self.assertEqual(nomes, ["TRG_TMC_PESSOA_AUDITORIA", "TRG_TMC_CONTATO_ATUALIZA_ITEM"])
        for campo in ["OPERACAO", "USUARIO", "VALORES_ANTIGOS", "VALORES_NOVOS", ":OLD.", ":NEW."]:
            self.assertIn(campo, self.gat)

    def test_blocos_anonimos_com_decisao_repeticao_e_cursor(self):
        blocos = [b for b in self.blocos.split("\n/\n") if "DECLARE" in b]
        self.assertGreaterEqual(len(blocos), 2)
        self.assertIn("CURSOR", blocos[0])
        for b in blocos:
            self.assertRegex(b, r"\bLOOP\b")
            self.assertRegex(b, r"\b(IF|CASE)\b")

    def test_executar_tudo_chama_os_arquivos_que_existem(self):
        for nome in re.findall(r"@@(\S+)", ler("sql", "regras", "00_executar_tudo.sql")):
            self.assertTrue(os.path.exists(os.path.join(REGRAS, nome)), nome)

    def test_apagar_cobre_as_tabelas_do_epico(self):
        criadas = set(re.findall(r"CREATE TABLE (\w+)", ler("sql", "regras", "01_tabelas_busca_ativa.sql")))
        apagadas = set(re.findall(r"DROP TABLE (\w+)", ler("sql", "regras", "99_apagar_regras.sql")))
        self.assertEqual(criadas, apagadas)


class TestRegraDePontuacao(unittest.TestCase):
    """A pontuação esperada nos testes Oracle (07_testes.sql) sai da mesma regra em Python."""

    @classmethod
    def setUpClass(cls):
        cls.setores = {s["CODIGO"]: s for s in g.ler("tmc_setor.csv")}
        cls.calor = {c["CODIGO_SETOR"]: c for c in g.ler("tmc_calor_setor.csv")}
        servicos = g.ler("tmc_servico.csv")
        cls.refugios = [s for s in servicos if s["TIPO"] == "REFUGIO" and s["REVISAO"] == "manter" and s["LAT"]]
        cls.pessoas = {p[0]: p for p in g.PESSOAS}

    def pts(self, pid):
        p = self.pessoas[pid]
        return g.pontuacao(p, self.setores[p[4]], self.calor.get(p[4]), self.refugios)[0]

    def test_pontuacoes_usadas_nos_testes_oracle(self):
        esperado = {900001: 14, 900002: 12, 900003: 7, 900006: 13, 900007: 4, 900010: 9, 900011: 11}
        self.assertEqual({pid: self.pts(pid) for pid in esperado}, esperado)

    def test_distancias_longe_do_limite_de_800_m(self):
        for p in g.PESSOAS:
            s = self.setores[p[4]]
            d = min(g.distancia_m(float(s["LAT_REFERENCIA"]), float(s["LON_REFERENCIA"]),
                                  float(r["LAT"]), float(r["LON"])) for r in self.refugios)
            self.assertGreater(abs(d - 800), 100, f"{p[0]} a {d:.0f} m: perto demais do limite")

    def test_dados_de_teste_trazem_as_11_pessoas(self):
        texto = ler("sql", "regras", "02_dados_teste.sql")
        ids = re.findall(r"MERGE INTO TMC_PESSOA_SINTETICA t USING \(SELECT (\d+) ID", texto)
        self.assertEqual(sorted(map(int, ids)), sorted(self.pessoas))
        setores_inseridos = set(re.findall(r"MERGE INTO TMC_SETOR t USING \(SELECT '(\d+)' CODIGO", texto))
        for p in g.PESSOAS:
            self.assertIn(p[4], setores_inseridos)


class TestMongo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.carga = ler("mongodb", "01_carga.js")

    def documentos(self, nome):
        m = re.search(rf"const {nome} = (\[.*?\n\]);", self.carga, re.S)
        texto = re.sub(r'new Date\("([^"]+)"\)', r'"\1"', m.group(1))
        return json.loads(texto)

    def test_database_colecoes_e_insercao(self):
        self.assertIn('db.getSiblingDB("thermocity")', self.carga)
        self.assertEqual(re.findall(r'db\.createCollection\("(\w+)"', self.carga), ["setores", "servicos"])
        self.assertEqual(self.carga.count("insertMany("), 2)

    def test_quantidade_de_documentos_igual_as_tabelas(self):
        setores, servicos = self.documentos("setores"), self.documentos("servicos")
        self.assertEqual(len(setores), 420)
        self.assertEqual(len(servicos), 191)
        self.assertGreaterEqual(len(setores) + len(servicos), 10)

    def test_calor_incorporado_e_servico_referenciando_setor(self):
        setores = {d["_id"]: d for d in self.documentos("setores")}
        for d in self.documentos("servicos"):
            if d["setor_codigo"]:
                self.assertIn(d["setor_codigo"], setores)
        self.assertTrue(all(d["calor"] and 1 <= d["calor"]["classe"] <= 5 for d in setores.values()))

    def test_relatorios_tem_tres_consultas_e_uma_agregacao(self):
        rel = ler("mongodb", "02_relatorios.js")
        self.assertEqual(rel.count(".aggregate("), 1)
        self.assertEqual(rel.count(".find("), 2)


if __name__ == "__main__":
    unittest.main()
