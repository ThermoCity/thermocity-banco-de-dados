CREATE OR REPLACE FUNCTION FN_VERIFICAR_ELEGIBILIDADE (
    P_PESSOA_ID IN NUMBER,
    P_NIVEL     IN NUMBER
)
RETURN NUMBER
IS
    V_IDADE NUMBER;
    V_IPVS  NUMBER;

BEGIN
    IF P_NIVEL NOT BETWEEN 3 AND 5 THEN
        RAISE_APPLICATION_ERROR(
            -20002,
            'Nivel invalido. A busca ativa comeca no NC3.'
        );
    END IF;

    SELECT
        NVL(p.IDADE,
            CASE
                WHEN p.FAIXA_ETARIA = '70+' THEN 70
                ELSE 60
            END),
        s.IPVS_GRUPO
    INTO
        V_IDADE,
        V_IPVS
    FROM TMC_PESSOA_SINTETICA p
    INNER JOIN TMC_SETOR s
        ON s.CODIGO = p.SETOR_CODIGO
    WHERE p.ID = P_PESSOA_ID;

    IF P_NIVEL = 3 THEN
        IF V_IDADE >= 70 AND V_IPVS >= 5 THEN
            RETURN 1;
        END IF;
    ELSIF P_NIVEL = 4 THEN
        IF V_IDADE >= 60 AND V_IPVS >= 4 THEN
            RETURN 1;
        END IF;
    ELSIF P_NIVEL = 5 THEN
        IF V_IDADE >= 60 THEN
            RETURN 1;
        END IF;
    END IF;

    RETURN 0;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
END FN_VERIFICAR_ELEGIBILIDADE;
/
