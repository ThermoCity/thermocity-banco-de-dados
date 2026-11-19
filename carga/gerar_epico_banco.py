"""
ThermoCity — gera os scripts do épico 83 a partir dos CSVs de dados/territorio:

  sql/regras/02_dados_teste.sql   território mínimo + 11 pessoas FICTÍCIAS + níveis de demonstração
  mongodb/01_carga.js             database thermocity, coleções setores e servicos (todos os registros)

Os dois arquivos já estão no repositório; rode de novo só se os CSVs mudarem:
    py carga/gerar_epico_banco.py

Também imprime a pontuação esperada de cada pessoa de teste (regra v1), usada em 07_testes.sql.
"""
from __future__ import annotations

import csv
import json
import math
import os

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASTA = os.path.join(RAIZ, "dados", "territorio")
SAIDA_SQL = os.path.join(RAIZ, "sql", "regras", "02_dados_teste.sql")
SAIDA_JS = os.path.join(RAIZ, "mongodb", "01_carga.js")

csv.field_size_limit(10 ** 9)

UBS_A = "CNES-2047063"   # ESF Parque Alvorada
UBS_B = "CNES-2755114"   # UBS Centro
DATA_NC4 = "2026-11-24"  # dia de demonstração em NC4
DATA_NC2 = "2026-11-23"  # dia de demonstração em NC2

# id, nome, idade, sexo, setor, ubs, mora_sozinho, mobilidade, cronica, consentimento
PESSOAS = [
    (900001, "Maria Aparecida Souza", 78, "F", "354140605000303", UBS_A, 1, 0, 1, 1),
    (900002, "Neide Rodrigues Costa", 79, "F", "354140605000214", UBS_A, 1, 1, 0, 1),
    (900003, "José Carlos Pereira", 66, "M", "354140605000240", UBS_A, 0, 0, 1, 1),
    (900004, "Antônia Ferreira Lima", 72, "F", "354140605000474", UBS_A, 1, 0, 0, 1),
    (900005, "Benedito Alves", 84, "M", "354140605000240", UBS_A, 0, 1, 1, 0),
    (900006, "Lourdes Martins", 75, "F", "354140605000207", UBS_B, 1, 1, 1, 1),
    (900007, "Sebastião Rocha", 68, "M", "354140605000207", UBS_B, 0, 0, 0, 1),
    (900008, "Aparecida Gomes", 81, "F", "354140605000031", UBS_B, 1, 0, 1, 1),
    (900009, "Joana Silva", 63, "F", "354140605000009", UBS_B, 0, 0, 0, 1),
    (900010, "Francisco Oliveira", 77, "M", "354140605000214", UBS_A, 0, 0, 1, 1),
    (900011, "Teresa Batista", 70, "F", "354140605000303", UBS_A, 0, 1, 0, 1),
]


def ler(arquivo: str) -> list[dict]:
    with open(os.path.join(PASTA, arquivo), encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f, delimiter=";"))


def num(v: str):
    v = (v or "").strip()
    if v == "":
        return None
    f = float(v)
    return int(f) if f.is_integer() and "." not in v else f


def distancia_m(lat1, lon1, lat2, lon2) -> float:
    """Mesma fórmula de PKG_PRIORIZACAO.FN_DISTANCIA_M (haversine, raio 6.371 km)."""
    rad = math.pi / 180
    dlat, dlon = (lat2 - lat1) * rad, (lon2 - lon1) * rad
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1 * rad) * math.cos(lat2 * rad) * math.sin(dlon / 2) ** 2
    return 2 * 6371000 * math.asin(min(1, math.sqrt(h)))


def sql_val(v) -> str:
    if v is None or v == "":
        return "NULL"
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


def pontuacao(p, setor, calor, refugios) -> tuple[int, float]:
    _, _, idade, _, _, _, sozinho, mob, cron, _ = p
    lat, lon = float(setor["LAT_REFERENCIA"]), float(setor["LON_REFERENCIA"])
    dist = min(distancia_m(lat, lon, float(r["LAT"]), float(r["LON"])) for r in refugios)
    v = 3 * sozinho + 2 * mob + 2 * cron + (2 if idade >= 70 else 0)
    if calor and calor["CLASSE_CALOR"]:
        v += int(calor["CLASSE_CALOR"]) - 1
    ipvs = int(setor["IPVS_GRUPO"] or 0)
    v += 2 if ipvs >= 5 else 1 if ipvs == 4 else 0
    v += 1 if dist > 800 else 0
    return v, dist


def gerar_sql(setores, calor, servicos) -> None:
    refugios = [s for s in servicos.values() if s["TIPO"] == "REFUGIO" and s["REVISAO"] == "manter" and s["LAT"]]
    ubs = [servicos[UBS_A], servicos[UBS_B]]
    codigos = sorted({p[4] for p in PESSOAS} | {s["SETOR_CODIGO"] for s in refugios + ubs if s["SETOR_CODIGO"]})

    l = ["-- =============================================================================",
         "-- ThermoCity — Épico 83 · dados de teste (GERADO por carga/gerar_epico_banco.py)",
         "-- Território mínimo para rodar num usuário limpo: setores, calor, 2 UBS e os 10",
         "-- refúgios públicos confirmados. MERGE só insere o que falta: se a carga completa",
         "-- (carga/carregar.py) já rodou, nada do território é alterado.",
         "-- Pessoas 900001..900011 são FICTÍCIAS (SINTETICO = 1, telefones não discáveis).",
         "-- =============================================================================",
         ""]
    cols_s = ["CODIGO", "SITUACAO", "CD_MUNICIPIO", "NM_MUNICIPIO", "NM_DISTRITO", "POP_TOTAL", "POP_60_69",
              "POP_70_MAIS", "STATUS_CENSO", "IPVS_GRUPO", "IPVS_NOME", "IPVS_EDICAO", "IPVS_STATUS",
              "LAT_REFERENCIA", "LON_REFERENCIA"]
    l.append("-- Setores")
    for c in codigos:
        s = setores[c]
        vals = ", ".join(f"{sql_val(num(s[k]) if k in ('POP_TOTAL','POP_60_69','POP_70_MAIS','IPVS_GRUPO','LAT_REFERENCIA','LON_REFERENCIA') else s[k])} {k}" for k in cols_s)
        l.append(f"MERGE INTO TMC_SETOR t USING (SELECT {vals} FROM DUAL) s ON (t.CODIGO = s.CODIGO) "
                 f"WHEN NOT MATCHED THEN INSERT ({', '.join(cols_s)}) VALUES ({', '.join('s.' + k for k in cols_s)});")
    cols_c = ["CODIGO_SETOR", "LST_VERAO_C", "CLASSE_CALOR", "CENA_LANDSAT", "DATA_CENA", "STATUS"]
    l += ["", "-- Nota de calor dos setores"]
    for c in codigos:
        k = calor[c]
        vals = (f"{sql_val(c)} CODIGO_SETOR, {sql_val(num(k['LST_VERAO_C']))} LST_VERAO_C, "
                f"{sql_val(num(k['CLASSE_CALOR']))} CLASSE_CALOR, {sql_val(k['CENA_LANDSAT'])} CENA_LANDSAT, "
                f"DATE '{k['DATA_CENA']}' DATA_CENA, {sql_val(k['STATUS'])} STATUS")
        l.append(f"MERGE INTO TMC_CALOR_SETOR t USING (SELECT {vals} FROM DUAL) s ON (t.CODIGO_SETOR = s.CODIGO_SETOR) "
                 f"WHEN NOT MATCHED THEN INSERT ({', '.join(cols_c)}) VALUES ({', '.join('s.' + k for k in cols_c)});")
    cols_v = ["ID", "NOME", "TIPO", "CATEGORIA", "ENDERECO", "BAIRRO", "LAT", "LON", "FONTE", "ID_FONTE",
              "SETOR_CODIGO", "COORD_STATUS", "REVISAO"]
    l += ["", "-- UBS das pessoas de teste e refúgios públicos confirmados (REVISAO = manter)"]
    for s in ubs + sorted(refugios, key=lambda r: r["ID"]):
        vals = ", ".join(f"{sql_val(num(s[k]) if k in ('LAT', 'LON') else s[k])} {k}" for k in cols_v)
        l.append(f"MERGE INTO TMC_SERVICO t USING (SELECT {vals} FROM DUAL) s ON (t.ID = s.ID) "
                 f"WHEN NOT MATCHED THEN INSERT ({', '.join(cols_v)}) VALUES ({', '.join('s.' + k for k in cols_v)});")

    l += ["", "-- Níveis de calor dos dias de demonstração (FONTE = DEMONSTRACAO, não é dado do INMET)"]
    for data, nivel, nome, ic in [(DATA_NC2, 2, "Atencao", 35.4), (DATA_NC4, 4, "Alto risco", 37.2)]:
        l.append("MERGE INTO TMC_NIVEL_CALOR t USING (SELECT DATE '%s' DATA_LOCAL, %d NIVEL, '%s' NOME_NIVEL, %s IC_MAX_C, "
                 "'PREVISTO' ORIGEM, 'DEMONSTRACAO' FONTE, 'A707-2003-2026-v1' VERSAO_LIMIAR FROM DUAL) s "
                 "ON (t.DATA_LOCAL = s.DATA_LOCAL AND t.ORIGEM = s.ORIGEM AND t.FONTE = s.FONTE AND t.VERSAO_LIMIAR = s.VERSAO_LIMIAR) "
                 "WHEN NOT MATCHED THEN INSERT (DATA_LOCAL, NIVEL, NOME_NIVEL, IC_MAX_C, ORIGEM, FONTE, VERSAO_LIMIAR) "
                 "VALUES (s.DATA_LOCAL, s.NIVEL, s.NOME_NIVEL, s.IC_MAX_C, s.ORIGEM, s.FONTE, s.VERSAO_LIMIAR);" % (data, nivel, nome, ic))

    cols_p = ["ID", "NOME", "IDADE", "FAIXA_ETARIA", "SEXO", "SETOR_CODIGO", "LAT", "LON", "MORA_SOZINHO",
              "MOBILIDADE_REDUZIDA", "CONDICAO_CRONICA", "TELEFONE", "UBS_REF_ID", "UBS_REF_NOME",
              "CONSENTIMENTO_LGPD", "SINTETICO"]
    l += ["", "-- Pessoas FICTÍCIAS de teste (a posição de cada uma é o ponto de referência do setor)"]
    print("Pontuação esperada (regra v1):")
    for p in PESSOAS:
        pid, nome, idade, sexo, setor, ubs_id, sozinho, mob, cron, cons = p
        s = setores[setor]
        v, dist = pontuacao(p, s, calor.get(setor), refugios)
        print(f"  {pid} {nome:25s} idade {idade} setor nota {calor[setor]['CLASSE_CALOR']} IPVS {s['IPVS_GRUPO']} "
              f"refúgio {dist:6.0f} m -> {v}")
        valores = [pid, nome, idade, "70+" if idade >= 70 else "60-69", sexo, setor, num(s["LAT_REFERENCIA"]),
                   num(s["LON_REFERENCIA"]), sozinho, mob, cron, f"+55 18 0000-{pid % 10000:04d}", ubs_id,
                   servicos[ubs_id]["NOME"], cons, 1]
        vals = ", ".join(f"{sql_val(v_)} {k}" for v_, k in zip(valores, cols_p))
        l.append(f"MERGE INTO TMC_PESSOA_SINTETICA t USING (SELECT {vals} FROM DUAL) s ON (t.ID = s.ID) "
                 f"WHEN NOT MATCHED THEN INSERT ({', '.join(cols_p)}, CONSENTIMENTO_EM, GERADO_EM) "
                 f"VALUES ({', '.join('s.' + k for k in cols_p)}, "
                 f"CASE WHEN s.CONSENTIMENTO_LGPD = 1 THEN SYSTIMESTAMP END, SYSTIMESTAMP);")
    l += ["", "COMMIT;", ""]
    os.makedirs(os.path.dirname(SAIDA_SQL), exist_ok=True)
    with open(SAIDA_SQL, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(l))


def doc_setor(s, c) -> dict:
    p60, p70 = num(s["POP_60_69"]), num(s["POP_70_MAIS"])
    d = {
        "_id": s["CODIGO"],
        "situacao": s["SITUACAO"] or None,
        "municipio": {"codigo": s["CD_MUNICIPIO"], "nome": s["NM_MUNICIPIO"]},
        "distrito": s["NM_DISTRITO"] or None,
        "bairro": (s["NM_BAIRRO"] or None) if s["NM_BAIRRO"] not in ("", ".") else None,
        "area_km2": num(s["AREA_KM2"]),
        "populacao": {
            "total": num(s["POP_TOTAL"]), "p60_69": p60, "p70_mais": p70,
            "idosos_60_mais": p60 + p70 if p60 is not None and p70 is not None else None,
            "status_censo": s["STATUS_CENSO"] or None,
        },
        "ipvs": {"grupo": num(s["IPVS_GRUPO"]), "nome": s["IPVS_NOME"] or None,
                 "edicao": s["IPVS_EDICAO"] or None, "status": s["IPVS_STATUS"] or None},
        "calor": None,
        "ponto_referencia": {"type": "Point", "coordinates": [num(s["LON_REFERENCIA"]), num(s["LAT_REFERENCIA"])]},
    }
    if c:
        d["calor"] = {
            "classe": num(c["CLASSE_CALOR"]), "lst_verao_c": num(c["LST_VERAO_C"]),
            "ndvi_medio": num(c["NDVI_MEDIO"]), "pct_construcoes": num(c["PCT_CONSTRUCOES"]),
            "pct_vegetacao_densa": num(c["PCT_VEGETACAO_DENSA"]), "ta_estimada_c": num(c["TA_ESTIMADA_C"]),
            "pixels_validos": num(c["PIXELS_VALIDOS"]), "cena_landsat": c["CENA_LANDSAT"] or None,
            "data_cena": c["DATA_CENA"] or None, "status": c["STATUS"] or None,
        }
    return d


def doc_servico(s) -> dict:
    d = {"_id": s["ID"], "nome": s["NOME"] or None, "tipo": s["TIPO"], "categoria": s["CATEGORIA"] or None,
         "endereco": s["ENDERECO"] or None, "bairro": s["BAIRRO"] or None, "fonte": s["FONTE"] or None,
         "id_fonte": s["ID_FONTE"] or None, "setor_codigo": s["SETOR_CODIGO"] or None,
         "coord_status": s["COORD_STATUS"] or None, "revisao": s["REVISAO"] or None,
         "motivo_revisao": s["MOTIVO_REVISAO"] or None}
    if s["LAT"] and s["LON"]:
        d["localizacao"] = {"type": "Point", "coordinates": [num(s["LON"]), num(s["LAT"])]}
    return d


def js(docs: list[dict]) -> str:
    texto = "[\n" + ",\n".join("  " + json.dumps(d, ensure_ascii=False) for d in docs) + "\n]"
    # data_cena vira Date no MongoDB (no Oracle é DATE)
    import re
    return re.sub(r'"data_cena": "(\d{4}-\d{2}-\d{2})"', r'"data_cena": new Date("\1T00:00:00Z")', texto)


def gerar_js(setores, calor, servicos) -> None:
    docs_s = [doc_setor(s, calor.get(k)) for k, s in sorted(setores.items())]
    docs_v = [doc_servico(s) for _, s in sorted(servicos.items())]
    cab = f"""// =============================================================================
// ThermoCity — Épico 83 · carga do MongoDB (GERADO por carga/gerar_epico_banco.py)
// Rodar:  mongosh "<sua conexão>" mongodb/01_carga.js
// Cria a database thermocity, as coleções setores ({len(docs_s)} documentos) e servicos
// ({len(docs_v)} documentos) a partir dos mesmos CSVs que alimentam o Oracle.
// Pode rodar de novo: as coleções são apagadas e recriadas.
// =============================================================================

// Seleciona/cria a database (equivale a "use thermocity" no shell interativo)
db = db.getSiblingDB("thermocity");

db.setores.drop();
db.servicos.drop();

// setores: território + calor INCORPORADO (1:1 com TMC_SETOR / TMC_CALOR_SETOR)
db.createCollection("setores", {{
  validator: {{ $jsonSchema: {{
    bsonType: "object",
    required: ["_id", "populacao", "ipvs", "ponto_referencia"],
    properties: {{
      _id: {{ bsonType: "string", description: "CD_SETOR do IBGE (= TMC_SETOR.CODIGO)" }},
      "calor": {{ bsonType: ["object", "null"] }}
    }}
  }} }}
}});

// servicos: UBS e refúgios, com REFERÊNCIA ao setor (N:1 com TMC_SERVICO.SETOR_CODIGO)
db.createCollection("servicos", {{
  validator: {{ $jsonSchema: {{
    bsonType: "object",
    required: ["_id", "tipo"],
    properties: {{
      tipo: {{ enum: ["UBS", "REFUGIO"] }},
      revisao: {{ enum: ["manter", "potencial", "revisar", "remover", "publico_alvo", null] }}
    }}
  }} }}
}});

"""
    corpo = (f"const setores = {js(docs_s)};\n\n"
             f"const servicos = {js(docs_v)};\n\n"
             "const rs = db.setores.insertMany(setores);\n"
             "const rv = db.servicos.insertMany(servicos);\n\n"
             "db.setores.createIndex({ \"calor.classe\": 1 });\n"
             "db.setores.createIndex({ \"ipvs.grupo\": 1 });\n"
             "db.servicos.createIndex({ setor_codigo: 1 });\n"
             "db.servicos.createIndex({ tipo: 1, revisao: 1 });\n"
             "db.servicos.createIndex({ localizacao: \"2dsphere\" });\n\n"
             "print(`setores: ${Object.keys(rs.insertedIds).length} documentos`);\n"
             "print(`servicos: ${Object.keys(rv.insertedIds).length} documentos`);\n")
    os.makedirs(os.path.dirname(SAIDA_JS), exist_ok=True)
    with open(SAIDA_JS, "w", encoding="utf-8", newline="\n") as f:
        f.write(cab + corpo)


def main() -> None:
    setores = {s["CODIGO"]: s for s in ler("tmc_setor.csv")}
    calor = {c["CODIGO_SETOR"]: c for c in ler("tmc_calor_setor.csv")}
    servicos = {s["ID"]: s for s in ler("tmc_servico.csv")}
    gerar_sql(setores, calor, servicos)
    gerar_js(setores, calor, servicos)
    print(f"Gerados: {os.path.relpath(SAIDA_SQL, RAIZ)} e {os.path.relpath(SAIDA_JS, RAIZ)}")


if __name__ == "__main__":
    main()
