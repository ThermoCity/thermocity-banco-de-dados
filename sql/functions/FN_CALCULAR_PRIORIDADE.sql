CREATE OR REPLACE FUNCTION FN_CALCULAR_PRIORIDADE (
    P_PESSOA_ID IN NUMBER
)
RETURN NUMBER
IS
    V_IDADE               NUMBER;
    V_MORA_SOZINHO        NUMBER(1);
    V_MOBILIDADE          NUMBER(1);
    V_CONDICAO_CRONICA    NUMBER(1);
    V_IPVS                NUMBER;
    V_NOTA_CALOR          NUMBER;
    V_LAT                 BINARY_DOUBLE;
    V_LON                 BINARY_DOUBLE;
    V_DISTANCIA_REFUGIO   NUMBER;
    V_PONTUACAO           NUMBER := 0;

BEGIN
    SELECT
        NVL(p.IDADE,
            CASE
                WHEN p.FAIXA_ETARIA = '70+' THEN 70
                ELSE 60
            END),
        p.MORA_SOZINHO,
        p.MOBILIDADE_REDUZIDA,
        p.CONDICAO_CRONICA,
        s.IPVS_GRUPO,
        NVL(c.CLASSE_CALOR, 1),
        p.LAT,
        p.LON
    INTO
        V_IDADE,
        V_MORA_SOZINHO,
        V_MOBILIDADE,
        V_CONDICAO_CRONICA,
        V_IPVS,
        V_NOTA_CALOR,
        V_LAT,
        V_LON
    FROM TMC_PESSOA_SINTETICA p
    INNER JOIN TMC_SETOR s
        ON s.CODIGO = p.SETOR_CODIGO
    LEFT JOIN TMC_CALOR_SETOR c
        ON c.CODIGO_SETOR = p.SETOR_CODIGO
    WHERE p.ID = P_PESSOA_ID;

    IF V_MORA_SOZINHO = 1 THEN
        V_PONTUACAO := V_PONTUACAO + 3;
    END IF;

    IF V_MOBILIDADE = 1 THEN
        V_PONTUACAO := V_PONTUACAO + 2;
    END IF;

    IF V_CONDICAO_CRONICA = 1 THEN
        V_PONTUACAO := V_PONTUACAO + 2;
    END IF;

    IF V_IDADE >= 70 THEN
        V_PONTUACAO := V_PONTUACAO + 2;
    END IF;

    V_PONTUACAO := V_PONTUACAO + GREATEST(0, V_NOTA_CALOR - 1);

    IF V_IPVS >= 5 THEN
        V_PONTUACAO := V_PONTUACAO + 2;
    ELSIF V_IPVS = 4 THEN
        V_PONTUACAO := V_PONTUACAO + 1;
    END IF;

    IF V_LAT IS NOT NULL AND V_LON IS NOT NULL THEN
        SELECT MIN(
            2 * 6371000 * ASIN(
                SQRT(
                    LEAST(1,
                        GREATEST(0,
                            POWER(
                                SIN((r.LAT - V_LAT) * ACOS(-1) / 360),
                                2
                            )
                            +
                            COS(V_LAT * ACOS(-1) / 180)
                            *
                            COS(r.LAT * ACOS(-1) / 180)
                            *
                            POWER(
                                SIN((r.LON - V_LON) * ACOS(-1) / 360),
                                2
                            )
                        )
                    )
                )
            )
        )
        INTO V_DISTANCIA_REFUGIO
        FROM TMC_SERVICO r
        WHERE r.TIPO = 'REFUGIO'
          AND r.REVISAO IN ('manter', 'potencial')
          AND r.LAT IS NOT NULL
          AND r.LON IS NOT NULL;

        IF V_DISTANCIA_REFUGIO IS NULL
           OR V_DISTANCIA_REFUGIO > 800 THEN
            V_PONTUACAO := V_PONTUACAO + 1;
        END IF;
    END IF;

    RETURN V_PONTUACAO;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Pessoa nao encontrada ou sem setor cadastrado.'
        );
END FN_CALCULAR_PRIORIDADE;
/
