DECLARE
    V_NIVEL CONSTANT NUMBER := 4;

    V_IDADE       NUMBER;
    V_ID          NUMBER;
    V_NOME        VARCHAR2(120);
    V_PONTUACAO   NUMBER;

    CURSOR C_PESSOAS IS
        SELECT
            p.ID,
            p.NOME,
            NVL(p.IDADE,
                CASE
                    WHEN p.FAIXA_ETARIA = '70+' THEN 70
                    ELSE 60
                END) AS IDADE,
            FN_CALCULAR_PRIORIDADE(p.ID) AS PONTUACAO
        FROM TMC_PESSOA_SINTETICA p
        WHERE FN_VERIFICAR_ELEGIBILIDADE(p.ID, V_NIVEL) = 1
        ORDER BY
            PONTUACAO DESC,
            IDADE DESC,
            p.ID ASC;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE(' LISTA DE BUSCA ATIVA - NC' || V_NIVEL);
    DBMS_OUTPUT.PUT_LINE('========================================');

    OPEN C_PESSOAS;

    LOOP
        FETCH C_PESSOAS
        INTO V_ID, V_NOME, V_IDADE, V_PONTUACAO;

        EXIT WHEN C_PESSOAS%NOTFOUND;

        IF V_PONTUACAO >= 8 THEN
            DBMS_OUTPUT.PUT_LINE(
                'ALTA PRIORIDADE | ID: '
                || V_ID
                || ' | Nome: '
                || V_NOME
                || ' | Idade: '
                || V_IDADE
                || ' | Pontos: '
                || V_PONTUACAO
            );
        ELSE
            DBMS_OUTPUT.PUT_LINE(
                'PRIORIDADE | ID: '
                || V_ID
                || ' | Nome: '
                || V_NOME
                || ' | Idade: '
                || V_IDADE
                || ' | Pontos: '
                || V_PONTUACAO
            );
        END IF;
    END LOOP;

    CLOSE C_PESSOAS;
END;
/
