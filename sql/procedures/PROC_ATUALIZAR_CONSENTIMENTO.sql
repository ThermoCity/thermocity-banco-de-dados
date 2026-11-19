CREATE OR REPLACE PROCEDURE PROC_ATUALIZAR_CONSENTIMENTO (
    P_PESSOA_ID      IN NUMBER,
    P_CONSENTIMENTO  IN NUMBER
)
IS
BEGIN
    IF P_CONSENTIMENTO NOT IN (0, 1) THEN
        RAISE_APPLICATION_ERROR(
            -20004,
            'Consentimento invalido. Informe 1 para concedido ou 0 para revogado.'
        );
    END IF;

    UPDATE TMC_PESSOA_SINTETICA
    SET CONSENTIMENTO_LGPD = P_CONSENTIMENTO,
        CONSENTIMENTO_EM =
            CASE
                WHEN P_CONSENTIMENTO = 1 THEN SYSTIMESTAMP
                ELSE NULL
            END
    WHERE ID = P_PESSOA_ID;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(
            -20005,
            'Pessoa nao encontrada para atualizacao do consentimento.'
        );
    END IF;

    DBMS_OUTPUT.PUT_LINE(
        'Consentimento atualizado com sucesso.'
    );
END PR_ATUALIZAR_CONSENTIMENTO;
/
