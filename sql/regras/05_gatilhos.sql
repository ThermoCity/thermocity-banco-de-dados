-- =============================================================================
-- ThermoCity — Épico 83 · gatilhos
--   TRG_TMC_PESSOA_AUDITORIA       trilha LGPD: data, operação, usuário, valores antigo e novo
--   TRG_TMC_CONTATO_ATUALIZA_ITEM  regra: o contato registrado muda o status do item da lista
-- =============================================================================

CREATE OR REPLACE TRIGGER TRG_TMC_PESSOA_AUDITORIA
AFTER INSERT OR UPDATE OR DELETE ON TMC_PESSOA_SINTETICA
FOR EACH ROW
DECLARE
    v_operacao VARCHAR2(6);
    v_antigos  VARCHAR2(4000);
    v_novos    VARCHAR2(4000);

    -- Campos pessoais e da regra de prioridade, em texto "campo=valor; ...".
    FUNCTION descrever (p_nome VARCHAR2, p_idade NUMBER, p_setor VARCHAR2, p_ubs VARCHAR2,
                        p_telefone VARCHAR2, p_contato_ref VARCHAR2, p_tel_ref VARCHAR2,
                        p_sozinho NUMBER, p_mobilidade NUMBER, p_cronica NUMBER,
                        p_consentimento NUMBER) RETURN VARCHAR2 IS
    BEGIN
        RETURN SUBSTR('nome=' || p_nome || '; idade=' || p_idade || '; setor=' || p_setor
            || '; ubs=' || p_ubs || '; telefone=' || p_telefone
            || '; contato_ref=' || p_contato_ref || '; telefone_ref=' || p_tel_ref
            || '; mora_sozinho=' || p_sozinho || '; mobilidade_reduzida=' || p_mobilidade
            || '; condicao_cronica=' || p_cronica || '; consentimento_lgpd=' || p_consentimento, 1, 4000);
    END descrever;
BEGIN
    IF INSERTING THEN
        v_operacao := 'INSERT';
    ELSIF UPDATING THEN
        v_operacao := 'UPDATE';
    ELSE
        v_operacao := 'DELETE';
    END IF;

    IF v_operacao <> 'INSERT' THEN
        v_antigos := descrever(:OLD.NOME, :OLD.IDADE, :OLD.SETOR_CODIGO, :OLD.UBS_REF_ID, :OLD.TELEFONE,
                               :OLD.CONTATO_REF_NOME, :OLD.CONTATO_REF_TELEFONE, :OLD.MORA_SOZINHO,
                               :OLD.MOBILIDADE_REDUZIDA, :OLD.CONDICAO_CRONICA, :OLD.CONSENTIMENTO_LGPD);
    END IF;
    IF v_operacao <> 'DELETE' THEN
        v_novos := descrever(:NEW.NOME, :NEW.IDADE, :NEW.SETOR_CODIGO, :NEW.UBS_REF_ID, :NEW.TELEFONE,
                             :NEW.CONTATO_REF_NOME, :NEW.CONTATO_REF_TELEFONE, :NEW.MORA_SOZINHO,
                             :NEW.MOBILIDADE_REDUZIDA, :NEW.CONDICAO_CRONICA, :NEW.CONSENTIMENTO_LGPD);
    END IF;

    -- UPDATE que não mudou nenhum campo auditado não gera linha.
    IF v_operacao = 'UPDATE' AND v_antigos = v_novos THEN
        RETURN;
    END IF;

    INSERT INTO TMC_AUDITORIA_PESSOA (PESSOA_ID, OPERACAO, USUARIO, VALORES_ANTIGOS, VALORES_NOVOS)
    VALUES (NVL(:NEW.ID, :OLD.ID), v_operacao, SYS_CONTEXT('USERENV', 'SESSION_USER'), v_antigos, v_novos);
END TRG_TMC_PESSOA_AUDITORIA;
/

CREATE OR REPLACE TRIGGER TRG_TMC_CONTATO_ATUALIZA_ITEM
AFTER INSERT ON TMC_CONTATO
FOR EACH ROW
WHEN (NEW.ID_ITEM IS NOT NULL)
BEGIN
    UPDATE TMC_ITEM_LISTA
       SET STATUS = :NEW.RESULTADO,
           ATUALIZADO_EM = SYSTIMESTAMP
     WHERE ID_ITEM = :NEW.ID_ITEM;
END TRG_TMC_CONTATO_ATUALIZA_ITEM;
/

SHOW ERRORS TRIGGER TRG_TMC_PESSOA_AUDITORIA
SHOW ERRORS TRIGGER TRG_TMC_CONTATO_ATUALIZA_ITEM
