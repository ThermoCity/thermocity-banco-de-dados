CREATE OR REPLACE PROCEDURE PROC_REGISTRAR_CONTATO (
    P_PESSOA_ID       IN NUMBER,
    P_STATUS_CONTATO  IN VARCHAR2,
    P_OBSERVACAO      IN VARCHAR2 DEFAULT NULL
)
IS
    V_PESSOA_ID NUMBER;

BEGIN
    SELECT ID
    INTO V_PESSOA_ID
    FROM TMC_PESSOA_SINTETICA
    WHERE ID = P_PESSOA_ID;

    INSERT INTO TMC_REGISTRO_CONTATO (
        PESSOA_ID,
        DATA_CONTATO,
        STATUS_CONTATO,
        OBSERVACAO
    )
    VALUES (
        V_PESSOA_ID,
        SYSTIMESTAMP,
        P_STATUS_CONTATO,
        P_OBSERVACAO
    );

    DBMS_OUTPUT.PUT_LINE(
        'Contato registrado com sucesso para a pessoa ID: '
        || V_PESSOA_ID
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(
            -20003,
            'Nao foi possivel registrar o contato: pessoa '
            || P_PESSOA_ID
            || ' nao encontrada.'
        );
END PR_REGISTRAR_CONTATO;
/
