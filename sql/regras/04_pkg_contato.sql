-- =============================================================================
-- ThermoCity — Épico 83 · PKG_CONTATO
-- Registro dos contatos do agente de saúde e cobertura da busca ativa.
--
-- Resultados válidos: CONTATADO_BEM, PRECISA_AJUDA, NAO_ATENDEU, DADOS_INCORRETOS.
-- O STATUS do item da lista é atualizado pelo gatilho TRG_TMC_CONTATO_ATUALIZA_ITEM.
-- As rotinas NÃO fazem COMMIT: quem chama decide.
-- Erros de aplicação: -20010 pessoa não encontrada · -20011 resultado inválido ·
--                     -20012 observação acima de 1000 caracteres.
-- =============================================================================

CREATE OR REPLACE PACKAGE PKG_CONTATO AS

    -- 1 se o resultado é um dos quatro permitidos, 0 se não.
    FUNCTION fn_resultado_valido (p_resultado IN VARCHAR2) RETURN NUMBER;

    -- Percentual (0 a 100, uma casa) das pessoas da lista da UBS no dia que já tiveram contato.
    -- NULL se a UBS não tem lista naquele dia.
    FUNCTION fn_cobertura_ubs (p_ubs_id IN VARCHAR2, p_data IN DATE) RETURN NUMBER;

    -- Grava o contato da pessoa, ligado ao item da lista aberta mais recente dela (se houver).
    PROCEDURE prc_registrar_contato (p_pessoa_id  IN  NUMBER,
                                     p_resultado  IN  VARCHAR2,
                                     p_observacao IN  VARCHAR2 DEFAULT NULL,
                                     p_id_contato OUT NUMBER);

    -- Imprime (DBMS_OUTPUT) a cobertura de cada UBS no dia.
    PROCEDURE prc_resumo_cobertura (p_data IN DATE);

END PKG_CONTATO;
/

CREATE OR REPLACE PACKAGE BODY PKG_CONTATO AS

    FUNCTION fn_resultado_valido (p_resultado IN VARCHAR2) RETURN NUMBER IS
    BEGIN
        IF UPPER(TRIM(p_resultado)) IN ('CONTATADO_BEM', 'PRECISA_AJUDA', 'NAO_ATENDEU', 'DADOS_INCORRETOS') THEN
            RETURN 1;
        END IF;
        RETURN 0;
    END fn_resultado_valido;

    FUNCTION fn_cobertura_ubs (p_ubs_id IN VARCHAR2, p_data IN DATE) RETURN NUMBER IS
        v_total  NUMBER;
        v_feitos NUMBER;
    BEGIN
        SELECT COUNT(*), NVL(SUM(CASE WHEN i.STATUS <> 'PENDENTE' THEN 1 ELSE 0 END), 0)
          INTO v_total, v_feitos
          FROM TMC_ITEM_LISTA i
          JOIN TMC_LISTA_BUSCA l ON l.ID_LISTA = i.ID_LISTA
         WHERE l.UBS_ID = p_ubs_id
           AND l.DATA_LOCAL = TRUNC(p_data);
        IF v_total = 0 THEN
            RETURN NULL;
        END IF;
        RETURN ROUND(100 * v_feitos / v_total, 1);
    END fn_cobertura_ubs;

    PROCEDURE prc_registrar_contato (p_pessoa_id  IN  NUMBER,
                                     p_resultado  IN  VARCHAR2,
                                     p_observacao IN  VARCHAR2 DEFAULT NULL,
                                     p_id_contato OUT NUMBER) IS
        v_existe    NUMBER;
        v_id_item   NUMBER;
        v_resultado VARCHAR2(20);
    BEGIN
        SELECT COUNT(*) INTO v_existe FROM TMC_PESSOA_SINTETICA WHERE ID = p_pessoa_id;
        IF v_existe = 0 THEN
            RAISE_APPLICATION_ERROR(-20010, 'Pessoa ' || p_pessoa_id || ' não encontrada.');
        END IF;

        IF fn_resultado_valido(p_resultado) = 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'Resultado de contato inválido: ' || p_resultado
                || '. Use CONTATADO_BEM, PRECISA_AJUDA, NAO_ATENDEU ou DADOS_INCORRETOS.');
        END IF;
        v_resultado := UPPER(TRIM(p_resultado));

        IF LENGTH(p_observacao) > 1000 THEN
            RAISE_APPLICATION_ERROR(-20012, 'A observação deve ter no máximo 1000 caracteres.');
        END IF;

        -- Item da lista aberta mais recente da pessoa (o contato pode existir sem lista).
        BEGIN
            SELECT ID_ITEM INTO v_id_item
              FROM (SELECT i.ID_ITEM
                      FROM TMC_ITEM_LISTA i
                      JOIN TMC_LISTA_BUSCA l ON l.ID_LISTA = i.ID_LISTA
                     WHERE i.PESSOA_ID = p_pessoa_id
                       AND l.STATUS = 'ABERTA'
                     ORDER BY l.DATA_LOCAL DESC, i.ID_ITEM DESC)
             WHERE ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_id_item := NULL;
        END;

        INSERT INTO TMC_CONTATO (PESSOA_ID, ID_ITEM, RESULTADO, OBSERVACAO, REGISTRADO_POR)
        VALUES (p_pessoa_id, v_id_item, v_resultado, p_observacao, SYS_CONTEXT('USERENV', 'SESSION_USER'))
        RETURNING ID_CONTATO INTO p_id_contato;
    END prc_registrar_contato;

    PROCEDURE prc_resumo_cobertura (p_data IN DATE) IS
        CURSOR c_listas IS
            SELECT l.UBS_ID, NVL(s.NOME, l.UBS_ID) AS UBS_NOME, l.NIVEL, l.STATUS,
                   COUNT(i.ID_ITEM) AS TOTAL,
                   SUM(CASE WHEN i.STATUS = 'PRECISA_AJUDA' THEN 1 ELSE 0 END) AS AJUDA
              FROM TMC_LISTA_BUSCA l
              LEFT JOIN TMC_SERVICO s   ON s.ID = l.UBS_ID
              LEFT JOIN TMC_ITEM_LISTA i ON i.ID_LISTA = l.ID_LISTA
             WHERE l.DATA_LOCAL = TRUNC(p_data)
             GROUP BY l.UBS_ID, s.NOME, l.NIVEL, l.STATUS
             ORDER BY l.UBS_ID;
        v_linhas NUMBER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('Cobertura da busca ativa em ' || TO_CHAR(p_data, 'DD/MM/YYYY'));
        FOR r IN c_listas LOOP
            v_linhas := v_linhas + 1;
            DBMS_OUTPUT.PUT_LINE('  ' || RPAD(SUBSTR(r.UBS_NOME, 1, 45), 46) || ' NC' || r.NIVEL
                || ' · ' || r.STATUS || ' · ' || r.TOTAL || ' na lista · '
                || NVL(TO_CHAR(fn_cobertura_ubs(r.UBS_ID, p_data)), '-') || '% contatadas · '
                || r.AJUDA || ' precisam de ajuda');
        END LOOP;
        IF v_linhas = 0 THEN
            DBMS_OUTPUT.PUT_LINE('  Nenhuma lista neste dia.');
        END IF;
    END prc_resumo_cobertura;

END PKG_CONTATO;
/

SHOW ERRORS PACKAGE PKG_CONTATO
SHOW ERRORS PACKAGE BODY PKG_CONTATO
