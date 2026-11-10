# thermocity-banco-de-dados

Banco de dados do **ThermoCity** num lugar só: o script que **cria as tabelas** e os scripts e arquivos
que **populam** todas elas. Com este repositório dá para montar o banco do zero em qualquer usuário
Oracle em poucos minutos.

Todas as tabelas usam o prefixo **`TMC_`** (ThermoCity).

## Tabelas

| Camada | Tabela | Linhas | O que guarda | De onde vem |
|---|---|---|---|---|
| ONDE | `TMC_SETOR` | 420 | Setores censitários com população 60–69 e 70+ (Censo 2022) e IPVS 2022 | `dados/territorio/tmc_setor.csv` |
| ONDE | `TMC_SERVICO` | 191 | 36 UBS (CNES) e 155 possíveis refúgios (OpenStreetMap) | `dados/territorio/tmc_servico.csv` |
| ONDE | `TMC_CALOR_SETOR` | 420 | Nota de calor 1–5 por setor (Landsat, 08/01/2024) | `dados/territorio/tmc_calor_setor.csv` |
| QUEM | `TMC_PESSOA_SINTETICA` | — | Pessoas 60+ **fictícias** para testar a busca ativa | gerada pela `base-territorial-api` |
| QUANDO | `TMC_LIMIAR_NIVEL_CALOR` | 8 | Regras NC1–NC5 (versão `A707-2003-2026-v1`) | calculada da série do INMET |
| QUANDO | `TMC_LEITURA_CLIMA` | 188.498 | Leituras horárias da estação INMET A707 (2003–2026) + índice de calor | `dados/clima/INMET_A707_…csv` |
| QUANDO | `TMC_RESUMO_DIARIO_CLIMA` | 8.010 | Resumo de cada dia (IC máximo, temperaturas, chuva…) | calculada da série |
| QUANDO | `TMC_NIVEL_CALOR` | 7.498 | Nível NC1–NC5 de cada dia válido | calculada da série |

### Chaves estrangeiras

```
TMC_SETOR ──< TMC_SERVICO            (SETOR_CODIGO)
TMC_SETOR ──< TMC_CALOR_SETOR        (CODIGO_SETOR, 1 para 1)
TMC_SETOR ──< TMC_PESSOA_SINTETICA   (SETOR_CODIGO)
TMC_SERVICO ──< TMC_PESSOA_SINTETICA (UBS_REF_ID)

TMC_LEITURA_CLIMA      ──< TMC_NIVEL_CALOR (ID_LEITURA = leitura do pico do dia)
TMC_LIMIAR_NIVEL_CALOR ──< TMC_NIVEL_CALOR (ID_LIMIAR = regra que definiu o nível)
```

`TMC_RESUMO_DIARIO_CLIMA` se liga ao `TMC_NIVEL_CALOR` pela data (`DATA_LOCAL`), sem chave
estrangeira: o resumo tem também os dias inválidos, que não recebem nível.

## Como montar o banco

Requisitos: Python 3.9+ e acesso a um usuário Oracle.

```powershell
py -m pip install -r requirements.txt
copy .env.example .env          # preencher DB_USER, DB_PASSWORD e DB_DSN do usuário de destino
py carga\carregar.py --simular  # confere os arquivos sem conectar
py carga\carregar.py            # cria as tabelas que faltarem e carrega tudo (~2 a 5 min)
```

Depois, para ter pessoas sintéticas, suba a `base-territorial-api` apontando para o mesmo usuário e
chame `POST /admin/sinteticos` com `{ "quantidade": 5000, "semente": 42 }`.

| Comando | O que faz |
|---|---|
| `py carga\carregar.py` | cria as tabelas `TMC_` se não existirem e carrega território e clima |
| `py carga\carregar.py --somente territorio` | só setores, serviços e calor |
| `py carga\carregar.py --somente clima` | só leituras, resumo, limiares e níveis |
| `py carga\carregar.py --recriar` | **apaga** todas as tabelas `TMC_` e cria de novo (perde as pessoas sintéticas) |
| `py carga\carregar.py --simular` | só lê e confere os arquivos |

- **Pode rodar de novo:** o território usa `MERGE` (atualiza sem duplicar) e o clima apaga e grava
  de novo só as observações do INMET.
- **Erro no meio:** cada bloco é uma transação. Se falhar, nada daquele bloco fica gravado.
- **Credenciais:** só no `.env` ou em variáveis de ambiente. O `.env` está no `.gitignore` e **não** vai
  para o GitHub.
- **Sem Python:** dá para criar as tabelas rodando `sql/01_criar_tabelas.sql` no SQL Developer (F5).
  Os dados, porém, precisam do script.

## Estrutura

```
sql/
  01_criar_tabelas.sql      DDL: 8 tabelas, chaves, checks, índices e comentários
  02_apagar_tabelas.sql     apaga tudo (ordem inversa das chaves estrangeiras)
  03_consultas_exemplo.sql  contagens e consultas de ONDE e QUANDO
carga/
  carregar.py               ponto de entrada (cria tabelas e carrega)
  territorio.py             TMC_SETOR, TMC_SERVICO, TMC_CALOR_SETOR
  clima.py                  TMC_LIMIAR_NIVEL_CALOR, TMC_LEITURA_CLIMA, TMC_RESUMO_DIARIO_CLIMA, TMC_NIVEL_CALOR
  analise_niveis_calor.py   índice de calor (Rothfusz) e limiares NC1–NC5
  conexao.py                conexão e execução dos .sql
dados/
  territorio/               CSVs prontos, no formato das tabelas
  clima/                    série unificada da A707 (2003-02-04 a 2026-10-31)
testes/                     testes sem banco (DDL, arquivos e índice de calor)
```

Testes: `py -m unittest discover -s testes -v`

## De onde vieram os dados

**Território** (`dados/territorio`, separador `;`, UTF-8, ponto decimal, vazio = NULL):

- **Setores:** malha e agregados do IBGE (Censo 2022, município 3541406) e IPVS 2022 da Fundação Seade,
  preparados no QGIS (`prudente_setores_final.gpkg`).
  - `LAT/LON_REFERENCIA` é o ponto interior calculado pela `base-territorial-api` (JTS).
  - `STATUS_CENSO`: 390 `OK`, 21 `SUPRIMIDO` (sigilo do IBGE) e 9 `SEM_REGISTRO`.
  - `IPVS_STATUS`: 392 `OK` e 28 `SEM_DADO`.
- **Serviços:** UBS da API de dados abertos do CNES e refúgios do OpenStreetMap (Overpass), revisados
  manualmente. `SETOR_CODIGO` e `COORD_STATUS` foram calculados pela API (ponto dentro do polígono).
- **Calor:** Landsat 8 Collection 2 Level-2, cena `LC08_L2SP_222075_20240108_20240122_02_T1`,
  processada no QGIS (`landsat/setores_calor.gpkg`).
  - `CLASSE_CALOR` são quintis da temperatura de superfície: 84 setores por classe.
  - **Não** é o nível NC: mede o chão e os telhados às 10h20, e serve para comparar setores.

**Clima:** série horária da estação INMET A707, baixada e unificada no repositório
[ThermoCity/Tratamento-de-Dados-PresidPrud-Python](https://github.com/ThermoCity/Tratamento-de-Dados-PresidPrud-Python).
O cálculo (índice de calor, dia válido, limiares por percentil e regra de 3 dias) é o mesmo daquele
repositório. Os detalhes estão no README de lá.

## Se os dados mudarem

- **Território:** gere de novo o CSV correspondente em `dados/territorio` com as mesmas colunas e
  rode `--somente territorio`.
- **Série do INMET:** troque o CSV em `dados/clima` e rode `--somente clima`. Os limiares são
  recalculados.
- **Tabela nova:** coloque o `CREATE TABLE` em `sql/01_criar_tabelas.sql` com o prefixo `TMC_` e o
  `DROP` em `sql/02_apagar_tabelas.sql`. Os testes conferem os dois.
