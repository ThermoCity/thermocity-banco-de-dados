-- =============================================================================
-- ThermoCity — Épico 83 · testes dos pacotes e gatilhos
-- Usa as pessoas fictícias 900001..900011 e o dia de demonstração 24/11/2026 (NC4),
-- inseridos por 02_dados_teste.sql. Cada caso imprime OK ou FALHOU com o esperado.
-- Tudo o que os testes gravam é desfeito no fim (ROLLBACK): pode rodar quantas vezes quiser.
--
-- Pontuação esperada (regra v1, conferida em carga/gerar_epico_banco.py):
--   900001 Maria   78a, mora só, crônica, setor nota 5, IPVS 5, refúgio a 2,1 km -> 3+2+2+4+2+1 = 14
--   900006 Lourdes 75a, mora só, mobilidade, crônica, nota 3, IPVS 5, refúgio a 0,6 km -> 3+2+2+2+2+2+0 = 13
--   900007 Sebastião 68a, nota 3, IPVS 5, refúgio a 0,6 km -> 2+2 = 4
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    c_dia      CONSTANT DATE := DATE '2026-11-24';
    c_ubs_a    CONSTANT VARCHAR2(40) := 'CNES-2047063';
    c_ubs_b    CONSTANT VARCHAR2(40) := 'CNES-2755114';
    v_ok       PLS_INTEGER := 0;
    v_falhas   PLS_INTEGER := 0;
    v_n        NUMBER;
    v_n2       NUMBER;
    v_listas   NUMBER;
    v_pessoas  NUMBER;
    v_id       NUMBER;
    v_txt      VARCHAR2(4000);
    v_txt2     VARCHAR2(4000);
    v_ordem    VARCHAR2(200);

    PROCEDURE confere (p_caso VARCHAR2, p_passou BOOLEAN, p_detalhe VARCHAR2 DEFAULT NULL) IS
    BEGIN
        IF p_passou THEN
            v_ok := v_ok + 1;
            DBMS_OUTPUT.PUT_LINE('OK      ' || p_caso);
        ELSE
            v_falhas := v_falhas + 1;
            DBMS_OUTPUT.PUT_LINE('FALHOU  ' || p_caso || CASE WHEN p_detalhe IS NOT NULL THEN ' -> ' || p_detalhe END);
        END IF;
    END confere;
BEGIN
    SAVEPOINT inicio_testes;
    DBMS_OUTPUT.PUT_LINE('ThermoCity · testes do épico 83');
    DBMS_OUTPUT.PUT_LINE('--------------------------------');

    -- T01..T03 · PKG_PRIORIZACAO.fn_pontuacao
    v_n := PKG_PRIORIZACAO.fn_pontuacao(900001);
    confere('T01 pontuação da Maria (78a, mora só, setor nota 5) = 14', v_n = 14, 'obtido ' || v_n);
    v_n := PKG_PRIORIZACAO.fn_pontuacao(900006);
    v_n2 := PKG_PRIORIZACAO.fn_pontuacao(900007);
    confere('T02 pontuação Lourdes = 13 e Sebastião = 4 (refúgio a menos de 800 m não soma)',
            v_n = 13 AND v_n2 = 4, 'obtido ' || v_n || ' e ' || v_n2);
    BEGIN
        v_n := PKG_PRIORIZACAO.fn_pontuacao(999999);
        confere('T03 pessoa inexistente gera erro -20001', FALSE, 'não deu erro');
    EXCEPTION WHEN OTHERS THEN
        confere('T03 pessoa inexistente gera erro -20001', SQLCODE = -20001, SQLERRM);
    END;

    -- T04 · fn_nivel_vigente
    v_n := PKG_PRIORIZACAO.fn_nivel_vigente(c_dia);
    v_n2 := PKG_PRIORIZACAO.fn_nivel_vigente(DATE '2026-11-23');
    confere('T04 nível vigente: 24/11 = NC4, 23/11 = NC2, dia sem dado = NULL',
            v_n = 4 AND v_n2 = 2 AND PKG_PRIORIZACAO.fn_nivel_vigente(DATE '2035-01-01') IS NULL,
            'obtido ' || v_n || ' e ' || v_n2);

    -- T05 · fn_elegivel (alcance)
    confere('T05 alcance: sem consentimento nunca entra; 66a IPVS 5 fica fora no NC3 e entra no NC4',
            PKG_PRIORIZACAO.fn_elegivel(900005, 5) = 0
            AND PKG_PRIORIZACAO.fn_elegivel(900003, 3) = 0
            AND PKG_PRIORIZACAO.fn_elegivel(900003, 4) = 1
            AND PKG_PRIORIZACAO.fn_elegivel(900004, 4) = 0
            AND PKG_PRIORIZACAO.fn_elegivel(900004, 5) = 1);

    -- T06..T07 · prc_gerar_lista_dia em NC4
    PKG_PRIORIZACAO.prc_gerar_lista_dia(c_dia, NULL, v_listas, v_pessoas);
    SELECT COUNT(*) INTO v_n
      FROM TMC_ITEM_LISTA i JOIN TMC_LISTA_BUSCA l ON l.ID_LISTA = i.ID_LISTA
     WHERE l.DATA_LOCAL = c_dia AND i.PESSOA_ID BETWEEN 900001 AND 900011;
    confere('T06 NC4 coloca 7 das 11 pessoas de teste nas listas das 2 UBS', v_n = 7 AND v_listas >= 2,
            v_n || ' pessoas de teste, ' || v_listas || ' listas');

    SELECT LISTAGG(i.PESSOA_ID, ',') WITHIN GROUP (ORDER BY i.POSICAO) INTO v_ordem
      FROM TMC_ITEM_LISTA i JOIN TMC_LISTA_BUSCA l ON l.ID_LISTA = i.ID_LISTA
     WHERE l.DATA_LOCAL = c_dia AND l.UBS_ID = c_ubs_a AND i.PESSOA_ID BETWEEN 900001 AND 900011;
    confere('T07 ordem na UBS Parque Alvorada: Maria(14), Neide(12), Teresa(11), Francisco(9), José(7)',
            v_ordem = '900001,900002,900011,900010,900003', 'obtido ' || v_ordem);

    -- T08..T09 · prc_registrar_contato com erro: nada é gravado
    SELECT COUNT(*) INTO v_n FROM TMC_CONTATO;
    BEGIN
        PKG_CONTATO.prc_registrar_contato(999999, 'CONTATADO_BEM', NULL, v_id);
        confere('T08 contato de pessoa inexistente gera erro -20010', FALSE, 'não deu erro');
    EXCEPTION WHEN OTHERS THEN
        SELECT COUNT(*) INTO v_n2 FROM TMC_CONTATO;
        confere('T08 contato de pessoa inexistente gera erro -20010 e nada é gravado',
                SQLCODE = -20010 AND v_n2 = v_n, SQLERRM);
    END;
    BEGIN
        PKG_CONTATO.prc_registrar_contato(900001, 'OCUPADO', NULL, v_id);
        confere('T09 resultado fora dos permitidos gera erro -20011', FALSE, 'não deu erro');
    EXCEPTION WHEN OTHERS THEN
        confere('T09 resultado fora dos permitidos gera erro -20011', SQLCODE = -20011, SQLERRM);
    END;

    -- T10..T11 · contato válido + gatilho TRG_TMC_CONTATO_ATUALIZA_ITEM + cobertura
    PKG_CONTATO.prc_registrar_contato(900001, 'PRECISA_AJUDA', 'Tontura; ventilador quebrado.', v_id);
    SELECT i.STATUS INTO v_txt
      FROM TMC_ITEM_LISTA i JOIN TMC_LISTA_BUSCA l ON l.ID_LISTA = i.ID_LISTA
     WHERE l.DATA_LOCAL = c_dia AND i.PESSOA_ID = 900001;
    confere('T10 contato PRECISA_AJUDA muda o item da Maria para PRECISA_AJUDA (gatilho)',
            v_txt = 'PRECISA_AJUDA', 'obtido ' || v_txt);

    PKG_CONTATO.prc_registrar_contato(900006, 'contatado_bem', NULL, v_id);
    SELECT ROUND(100 * SUM(CASE WHEN i.STATUS <> 'PENDENTE' THEN 1 ELSE 0 END) / COUNT(*), 1) INTO v_n2
      FROM TMC_ITEM_LISTA i JOIN TMC_LISTA_BUSCA l ON l.ID_LISTA = i.ID_LISTA
     WHERE l.DATA_LOCAL = c_dia AND l.UBS_ID = c_ubs_b;
    v_n := PKG_CONTATO.fn_cobertura_ubs(c_ubs_b, c_dia);
    confere('T11 cobertura da UBS Centro confere com a contagem dos itens', v_n = v_n2,
            'função ' || v_n || ' x contagem ' || v_n2);

    -- T12..T13 · gatilho de auditoria LGPD
    UPDATE TMC_PESSOA_SINTETICA SET TELEFONE = '+55 18 0000-7777' WHERE ID = 900002;
    SELECT VALORES_ANTIGOS, VALORES_NOVOS INTO v_txt, v_txt2
      FROM (SELECT VALORES_ANTIGOS, VALORES_NOVOS FROM TMC_AUDITORIA_PESSOA
             WHERE PESSOA_ID = 900002 AND OPERACAO = 'UPDATE' ORDER BY ID_AUDITORIA DESC)
     WHERE ROWNUM = 1;
    confere('T12 alteração de telefone gera UPDATE na auditoria com valor antigo e novo',
            INSTR(v_txt, 'telefone=+55 18 0000-0002') > 0 AND INSTR(v_txt2, 'telefone=+55 18 0000-7777') > 0);

    INSERT INTO TMC_PESSOA_SINTETICA (ID, NOME, IDADE, FAIXA_ETARIA, SEXO, SETOR_CODIGO, TELEFONE, SINTETICO)
    VALUES (900099, 'Pessoa Temporária de Teste', 65, '60-69', 'F', '354140605000009', '+55 18 0000-0099', 1);
    DELETE FROM TMC_PESSOA_SINTETICA WHERE ID = 900099;
    SELECT COUNT(CASE WHEN OPERACAO = 'INSERT' THEN 1 END),
           COUNT(CASE WHEN OPERACAO = 'DELETE' AND VALORES_ANTIGOS LIKE 'nome=Pessoa Temporária de Teste;%'
                           AND VALORES_NOVOS IS NULL AND USUARIO IS NOT NULL THEN 1 END)
      INTO v_n, v_n2
      FROM TMC_AUDITORIA_PESSOA WHERE PESSOA_ID = 900099;
    confere('T13 inclusão e exclusão geram INSERT e DELETE na auditoria (com valores antigos)',
            v_n >= 1 AND v_n2 >= 1, v_n || ' INSERT, ' || v_n2 || ' DELETE');

    -- T14 · NC2 encerra as listas do dia
    PKG_PRIORIZACAO.prc_gerar_lista_dia(c_dia, 2, v_listas, v_pessoas);
    SELECT COUNT(*) INTO v_n FROM TMC_LISTA_BUSCA WHERE DATA_LOCAL = c_dia AND STATUS = 'ABERTA';
    confere('T14 nível 2 encerra as listas abertas do dia', v_n = 0 AND v_listas = 0, v_n || ' ainda abertas');

    -- T15 · nível inválido
    BEGIN
        PKG_PRIORIZACAO.prc_gerar_lista_dia(c_dia, 6, v_listas, v_pessoas);
        confere('T15 nível 6 gera erro -20003', FALSE, 'não deu erro');
    EXCEPTION WHEN OTHERS THEN
        confere('T15 nível 6 gera erro -20003', SQLCODE = -20003, SQLERRM);
    END;

    -- T16 · objetos compilados
    SELECT COUNT(*) INTO v_n FROM USER_OBJECTS
     WHERE OBJECT_NAME IN ('PKG_PRIORIZACAO', 'PKG_CONTATO')
       AND OBJECT_TYPE IN ('PACKAGE', 'PACKAGE BODY') AND STATUS = 'VALID';
    SELECT COUNT(*) INTO v_n2 FROM USER_TRIGGERS
     WHERE TRIGGER_NAME IN ('TRG_TMC_PESSOA_AUDITORIA', 'TRG_TMC_CONTATO_ATUALIZA_ITEM') AND STATUS = 'ENABLED';
    confere('T16 2 pacotes VALID (specification e body) e 2 gatilhos ativos', v_n = 4 AND v_n2 = 2,
            v_n || ' partes de pacote, ' || v_n2 || ' gatilhos');

    ROLLBACK TO inicio_testes;
    DBMS_OUTPUT.PUT_LINE('--------------------------------');
    DBMS_OUTPUT.PUT_LINE(v_ok || ' OK · ' || v_falhas || ' FALHOU · alterações dos testes desfeitas');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO inicio_testes;
        DBMS_OUTPUT.PUT_LINE('ERRO inesperado nos testes: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/
