-- =============================================================================
-- ThermoCity — Épico 83 · executa tudo em sequência
-- Pré-requisito: as tabelas base (sql/01_criar_tabelas.sql). Num usuário limpo:
--   1) @sql/01_criar_tabelas.sql
--   2) @sql/regras/00_executar_tudo.sql
-- No SQL Developer: abra este arquivo e use F5 (Executar script). Os @@ são relativos a esta pasta.
-- Para rodar de novo do zero: @sql/regras/99_apagar_regras.sql
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

PROMPT == 01 tabelas da busca ativa
@@01_tabelas_busca_ativa.sql
PROMPT == 02 dados de teste
@@02_dados_teste.sql
PROMPT == 03 PKG_PRIORIZACAO
@@03_pkg_priorizacao.sql
PROMPT == 04 PKG_CONTATO
@@04_pkg_contato.sql
PROMPT == 05 gatilhos
@@05_gatilhos.sql
PROMPT == 06 blocos anonimos
@@06_blocos_anonimos.sql
PROMPT == 07 testes
@@07_testes.sql
