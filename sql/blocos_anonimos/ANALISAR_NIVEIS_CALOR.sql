DECLARE
    V_TOTAL_DIAS NUMBER := 0;
    V_DIAS_CRITICOS NUMBER := 0;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE(' ANALISE DOS NIVEIS DE CALOR');
    DBMS_OUTPUT.PUT_LINE(' ULTIMOS SETE DIAS');
    DBMS_OUTPUT.PUT_LINE('========================================');

    FOR R IN (
        SELECT
            DATA_LOCAL,
            NIVEL,
            NOME_NIVEL,
            IC_MAX_C,
            ORIGEM
        FROM TMC_NIVEL_CALOR
        WHERE DATA_LOCAL >= TRUNC(SYSDATE) - 6
          AND DATA_LOCAL < TRUNC(SYSDATE) + 1
        ORDER BY DATA_LOCAL, ORIGEM
    )
    LOOP
        V_TOTAL_DIAS := V_TOTAL_DIAS + 1;

        IF R.NIVEL >= 5 THEN
            V_DIAS_CRITICOS := V_DIAS_CRITICOS + 1;

            DBMS_OUTPUT.PUT_LINE(
                'CRITICO | Data: '
                || TO_CHAR(R.DATA_LOCAL, 'DD/MM/YYYY')
                || ' | '
                || R.NOME_NIVEL
                || ' | IC maximo: '
                || R.IC_MAX_C
                || ' C'
                || ' | Origem: '
                || R.ORIGEM
            );

        ELSIF R.NIVEL >= 4 THEN
            DBMS_OUTPUT.PUT_LINE(
                'ALERTA | Data: '
                || TO_CHAR(R.DATA_LOCAL, 'DD/MM/YYYY')
                || ' | '
                || R.NOME_NIVEL
                || ' | IC maximo: '
                || R.IC_MAX_C
                || ' C'
                || ' | Origem: '
                || R.ORIGEM
            );

        ELSIF R.NIVEL = 3 THEN
            DBMS_OUTPUT.PUT_LINE(
                'ATENCAO | Data: '
                || TO_CHAR(R.DATA_LOCAL, 'DD/MM/YYYY')
                || ' | '
                || R.NOME_NIVEL
                || ' | IC maximo: '
                || R.IC_MAX_C
                || ' C'
                || ' | Origem: '
                || R.ORIGEM
            );

        ELSE
            DBMS_OUTPUT.PUT_LINE(
                'NORMAL | Data: '
                || TO_CHAR(R.DATA_LOCAL, 'DD/MM/YYYY')
                || ' | '
                || R.NOME_NIVEL
            );
        END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('----------------------------------------');

    DBMS_OUTPUT.PUT_LINE(
        'Total de registros analisados: '
        || V_TOTAL_DIAS
    );

    DBMS_OUTPUT.PUT_LINE(
        'Registros em nivel critico: '
        || V_DIAS_CRITICOS
    );

    IF V_TOTAL_DIAS = 0 THEN
        DBMS_OUTPUT.PUT_LINE(
            'Nenhum registro encontrado no periodo.'
        );
    ELSE
        DBMS_OUTPUT.PUT_LINE(
            'Analise concluida.'
        );
    END IF;
END;
/
