-- =============================================================================
-- ThermoCity — Épico 83 · blocos PL/SQL anônimos (decisão, repetição e cursor)
-- Rodar com SET SERVEROUTPUT ON para ver as mensagens.
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

-- Bloco 1 — classifica os setores pelo risco territorial (cursor explícito + LOOP + IF/ELSIF).
--   CRÍTICO  = nota de calor 5 e IPVS 4 ou mais (calor alto onde a vulnerabilidade é maior)
--   ATENÇÃO  = nota de calor 4 ou mais, ou IPVS 5 ou mais
--   ROTINA   = o resto
DECLARE
    CURSOR c_setores IS
        SELECT s.CODIGO, s.IPVS_GRUPO, c.CLASSE_CALOR, s.POP_70_MAIS
          FROM TMC_SETOR s
          JOIN TMC_CALOR_SETOR c ON c.CODIGO_SETOR = s.CODIGO
         WHERE c.STATUS = 'OK'
         ORDER BY c.CLASSE_CALOR DESC, s.IPVS_GRUPO DESC NULLS LAST, s.CODIGO;
    r            c_setores%ROWTYPE;
    v_critico    NUMBER := 0;
    v_atencao    NUMBER := 0;
    v_rotina     NUMBER := 0;
    v_idosos_crit NUMBER := 0;
BEGIN
    OPEN c_setores;
    LOOP
        FETCH c_setores INTO r;
        EXIT WHEN c_setores%NOTFOUND;
        IF r.CLASSE_CALOR = 5 AND NVL(r.IPVS_GRUPO, 0) >= 4 THEN
            v_critico := v_critico + 1;
            v_idosos_crit := v_idosos_crit + NVL(r.POP_70_MAIS, 0);
            DBMS_OUTPUT.PUT_LINE('CRÍTICO  setor ' || r.CODIGO || ' · nota ' || r.CLASSE_CALOR
                                 || ' · IPVS ' || r.IPVS_GRUPO || ' · ' || NVL(TO_CHAR(r.POP_70_MAIS), '?') || ' pessoas 70+');
        ELSIF r.CLASSE_CALOR >= 4 OR NVL(r.IPVS_GRUPO, 0) >= 5 THEN
            v_atencao := v_atencao + 1;
        ELSE
            v_rotina := v_rotina + 1;
        END IF;
    END LOOP;
    CLOSE c_setores;
    DBMS_OUTPUT.PUT_LINE('---');
    DBMS_OUTPUT.PUT_LINE('Setores críticos: ' || v_critico || ' (' || v_idosos_crit || ' pessoas 70+)');
    DBMS_OUTPUT.PUT_LINE('Setores em atenção: ' || v_atencao);
    DBMS_OUTPUT.PUT_LINE('Setores em rotina: ' || v_rotina);
END;
/

-- Bloco 2 — manhã de 24/11/2026: lê o nível do dia, decide a ação (CASE) e, se houver busca
-- ativa, gera as listas e percorre cada uma (FOR com cursor). Grava (COMMIT) para a demonstração.
DECLARE
    v_data    DATE := DATE '2026-11-24';
    v_nivel   NUMBER;
    v_listas  NUMBER;
    v_pessoas NUMBER;
BEGIN
    v_nivel := PKG_PRIORIZACAO.fn_nivel_vigente(v_data);
    DBMS_OUTPUT.PUT_LINE('Nível de calor em ' || TO_CHAR(v_data, 'DD/MM/YYYY') || ': NC' || NVL(TO_CHAR(v_nivel), '?'));

    CASE
        WHEN v_nivel IS NULL THEN
            DBMS_OUTPUT.PUT_LINE('Sem nível cadastrado para o dia: nada a fazer.');
        WHEN v_nivel < 3 THEN
            DBMS_OUTPUT.PUT_LINE('NC' || v_nivel || ': rotina, sem busca ativa.');
        ELSE
            PKG_PRIORIZACAO.prc_gerar_lista_dia(v_data, v_nivel, v_listas, v_pessoas);
            DBMS_OUTPUT.PUT_LINE('Busca ativa: ' || v_listas || ' listas, ' || v_pessoas || ' pessoas.');
            FOR lst IN (SELECT lb.ID_LISTA, NVL(sv.NOME, lb.UBS_ID) AS UBS
                          FROM TMC_LISTA_BUSCA lb LEFT JOIN TMC_SERVICO sv ON sv.ID = lb.UBS_ID
                         WHERE lb.DATA_LOCAL = v_data ORDER BY lb.UBS_ID) LOOP
                DBMS_OUTPUT.PUT_LINE('');
                DBMS_OUTPUT.PUT_LINE(lst.UBS);
                FOR i IN (SELECT it.POSICAO, p.NOME, it.PONTUACAO, it.MOTIVO, it.STATUS
                            FROM TMC_ITEM_LISTA it JOIN TMC_PESSOA_SINTETICA p ON p.ID = it.PESSOA_ID
                           WHERE it.ID_LISTA = lst.ID_LISTA AND it.POSICAO <= 10
                           ORDER BY it.POSICAO) LOOP
                    DBMS_OUTPUT.PUT_LINE('  ' || i.POSICAO || '. ' || RPAD(i.NOME, 24) || ' ' || LPAD(i.PONTUACAO, 2)
                                         || ' pts · ' || i.MOTIVO || ' · ' || i.STATUS);
                END LOOP;
            END LOOP;
    END CASE;
    COMMIT;
END;
/
