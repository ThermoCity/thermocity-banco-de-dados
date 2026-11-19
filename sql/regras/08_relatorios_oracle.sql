-- =============================================================================
-- ThermoCity — Épico 83 · consultas Oracle equivalentes aos relatórios do MongoDB
-- (mongodb/02_relatorios.js). Precisam do território completo: carga/carregar.py.
-- =============================================================================

-- 0) Correspondência: linhas por tabela de origem
SELECT (SELECT COUNT(*) FROM TMC_SETOR)       AS SETORES,
       (SELECT COUNT(*) FROM TMC_CALOR_SETOR) AS SETORES_COM_CALOR,
       (SELECT COUNT(*) FROM TMC_SERVICO)     AS SERVICOS
  FROM DUAL;

-- 1) Setores e população 60+ por nota de calor  (= aggregate $group no MongoDB)
SELECT c.CLASSE_CALOR                    AS NOTA_CALOR,
       COUNT(*)                          AS SETORES,
       SUM(s.POP_60_69 + s.POP_70_MAIS)  AS IDOSOS_60_MAIS,
       SUM(s.POP_70_MAIS)                AS IDOSOS_70_MAIS,
       ROUND(AVG(c.LST_VERAO_C), 2)      AS LST_MEDIA_C
  FROM TMC_CALOR_SETOR c
  JOIN TMC_SETOR s ON s.CODIGO = c.CODIGO_SETOR
 WHERE c.CLASSE_CALOR IS NOT NULL
 GROUP BY c.CLASSE_CALOR
 ORDER BY NOTA_CALOR;

-- 2) Refúgios públicos confirmados  (= find + sort no MongoDB; ordem binária, como no MongoDB)
SELECT NOME, CATEGORIA, BAIRRO
  FROM TMC_SERVICO
 WHERE TIPO = 'REFUGIO' AND REVISAO = 'manter'
 ORDER BY NLSSORT(NOME, 'NLS_SORT=BINARY');

-- 3) Top 10 setores críticos por pessoas 70+  (= find + sort + limit no MongoDB)
SELECT s.CODIGO, s.IPVS_GRUPO AS IPVS, s.POP_70_MAIS AS P70_MAIS, s.POP_60_69 AS P60_69,
       ROUND(c.LST_VERAO_C, 1) AS LST_C
  FROM TMC_SETOR s
  JOIN TMC_CALOR_SETOR c ON c.CODIGO_SETOR = s.CODIGO
 WHERE c.CLASSE_CALOR = 5 AND s.IPVS_GRUPO >= 4
 ORDER BY s.POP_70_MAIS DESC NULLS LAST, s.CODIGO
 FETCH FIRST 10 ROWS ONLY;
