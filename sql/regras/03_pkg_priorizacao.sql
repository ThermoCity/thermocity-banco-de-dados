-- =============================================================================
-- ThermoCity — Épico 83 · PKG_PRIORIZACAO
-- Quem entra na lista de busca ativa do dia e em que ordem (regra v1, explicável).
--
-- Regra v1 (a mesma da API Java de cadastro e do motor de simulação do gêmeo):
--   Alcance (quem entra), sempre 60+ e com consentimento LGPD:
--     NC1–NC2 ninguém · NC3 70+ nos setores IPVS 5–6 · NC4 60+ nos setores IPVS 4–6 · NC5 todos
--   Pontuação (0 a 16): mora sozinho +3 · mobilidade reduzida +2 · condição crônica +2 ·
--     70+ anos +2 · nota de calor do setor − 1 (0 a 4) · IPVS 5–6 +2 / IPVS 4 +1 ·
--     refúgio público confirmado a mais de 800 m (ou nenhum) +1
--   Empate: mais velho primeiro, depois o menor id.
--
-- As rotinas NÃO fazem COMMIT: quem chama decide (os testes desfazem tudo no fim).
-- Erros de aplicação: -20001 pessoa não encontrada · -20002 dia sem nível · -20003 nível inválido.
-- Rodar no SQL Developer com F5 (Executar script). Cada objeto termina com "/".
-- =============================================================================

CREATE OR REPLACE PACKAGE PKG_PRIORIZACAO AS

    c_versao_regra    CONSTANT VARCHAR2(10) := 'v1';
    c_raio_refugio_m  CONSTANT NUMBER       := 800;

    -- Distância em metros entre dois pontos (fórmula de haversine, raio da Terra 6.371 km).
    FUNCTION fn_distancia_m (p_lat1 IN NUMBER, p_lon1 IN NUMBER,
                             p_lat2 IN NUMBER, p_lon2 IN NUMBER) RETURN NUMBER;

    -- Distância até o refúgio público confirmado (REVISAO = 'manter') mais próximo. NULL se não houver.
    FUNCTION fn_distancia_refugio_m (p_lat IN NUMBER, p_lon IN NUMBER) RETURN NUMBER;

    -- Nível de calor (1 a 5) vigente na data. Prefere o observado ao previsto. NULL se não houver.
    FUNCTION fn_nivel_vigente (p_data IN DATE) RETURN NUMBER;

    -- Pontuação de prioridade da pessoa pela regra v1 (0 a 16). Erro -20001 se a pessoa não existir.
    FUNCTION fn_pontuacao (p_pessoa_id IN NUMBER) RETURN NUMBER;

    -- Motivo em texto: por que a pessoa tem essa pontuação (vai para TMC_ITEM_LISTA.MOTIVO).
    FUNCTION fn_motivo (p_pessoa_id IN NUMBER) RETURN VARCHAR2;

    -- 1 se a pessoa entra na busca ativa no nível informado, 0 se não.
    FUNCTION fn_elegivel (p_pessoa_id IN NUMBER, p_nivel IN NUMBER) RETURN NUMBER;

    -- Gera (ou regenera) as listas do dia por UBS. Sem p_nivel, usa fn_nivel_vigente(p_data).
    -- NC1 e NC2 encerram as listas abertas do dia. Devolve quantas listas e pessoas ficaram.
    PROCEDURE prc_gerar_lista_dia (p_data    IN  DATE,
                                   p_nivel   IN  NUMBER DEFAULT NULL,
                                   p_listas  OUT NUMBER,
                                   p_pessoas OUT NUMBER);

END PKG_PRIORIZACAO;
/

CREATE OR REPLACE PACKAGE BODY PKG_PRIORIZACAO AS

    -- Dados da pessoa necessários para a regra (setor, IPVS e nota de calor).
    CURSOR c_pessoa (p_id NUMBER) IS
        SELECT p.ID, p.IDADE, p.MORA_SOZINHO, p.MOBILIDADE_REDUZIDA, p.CONDICAO_CRONICA,
               p.CONSENTIMENTO_LGPD, p.LAT, p.LON, s.IPVS_GRUPO, c.CLASSE_CALOR
          FROM TMC_PESSOA_SINTETICA p
          JOIN TMC_SETOR s        ON s.CODIGO = p.SETOR_CODIGO
          LEFT JOIN TMC_CALOR_SETOR c ON c.CODIGO_SETOR = p.SETOR_CODIGO AND c.STATUS = 'OK'
         WHERE p.ID = p_id;

    PROCEDURE carregar_pessoa (p_id IN NUMBER, r OUT c_pessoa%ROWTYPE) IS
    BEGIN
        OPEN c_pessoa(p_id);
        FETCH c_pessoa INTO r;
        IF c_pessoa%NOTFOUND THEN
            CLOSE c_pessoa;
            RAISE_APPLICATION_ERROR(-20001, 'Pessoa ' || p_id || ' não encontrada.');
        END IF;
        CLOSE c_pessoa;
    END carregar_pessoa;

    FUNCTION fn_distancia_m (p_lat1 IN NUMBER, p_lon1 IN NUMBER,
                             p_lat2 IN NUMBER, p_lon2 IN NUMBER) RETURN NUMBER IS
        c_raio_terra CONSTANT NUMBER := 6371000;
        c_rad        CONSTANT NUMBER := ACOS(-1) / 180;
        v_dlat NUMBER;
        v_dlon NUMBER;
        v_h    NUMBER;
    BEGIN
        IF p_lat1 IS NULL OR p_lon1 IS NULL OR p_lat2 IS NULL OR p_lon2 IS NULL THEN
            RETURN NULL;
        END IF;
        v_dlat := (p_lat2 - p_lat1) * c_rad;
        v_dlon := (p_lon2 - p_lon1) * c_rad;
        v_h := POWER(SIN(v_dlat / 2), 2)
             + COS(p_lat1 * c_rad) * COS(p_lat2 * c_rad) * POWER(SIN(v_dlon / 2), 2);
        RETURN 2 * c_raio_terra * ASIN(LEAST(1, SQRT(v_h)));
    END fn_distancia_m;

    FUNCTION fn_distancia_refugio_m (p_lat IN NUMBER, p_lon IN NUMBER) RETURN NUMBER IS
        v_menor NUMBER;
        v_d     NUMBER;
    BEGIN
        IF p_lat IS NULL OR p_lon IS NULL THEN
            RETURN NULL;
        END IF;
        FOR r IN (SELECT LAT, LON FROM TMC_SERVICO
                   WHERE TIPO = 'REFUGIO' AND REVISAO = 'manter'
                     AND LAT IS NOT NULL AND LON IS NOT NULL) LOOP
            v_d := fn_distancia_m(p_lat, p_lon, r.LAT, r.LON);
            IF v_menor IS NULL OR v_d < v_menor THEN
                v_menor := v_d;
            END IF;
        END LOOP;
        RETURN v_menor;
    END fn_distancia_refugio_m;

    FUNCTION fn_nivel_vigente (p_data IN DATE) RETURN NUMBER IS
        v_nivel NUMBER;
    BEGIN
        SELECT NIVEL INTO v_nivel
          FROM (SELECT NIVEL
                  FROM TMC_NIVEL_CALOR
                 WHERE DATA_LOCAL = TRUNC(p_data)
                 ORDER BY CASE ORIGEM WHEN 'OBSERVADO' THEN 1 ELSE 2 END, CALCULADO_EM DESC)
         WHERE ROWNUM = 1;
        RETURN v_nivel;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
    END fn_nivel_vigente;

    FUNCTION fn_pontuacao (p_pessoa_id IN NUMBER) RETURN NUMBER IS
        r      c_pessoa%ROWTYPE;
        v_pts  NUMBER := 0;
        v_dist NUMBER;
    BEGIN
        carregar_pessoa(p_pessoa_id, r);
        IF r.MORA_SOZINHO = 1 THEN v_pts := v_pts + 3; END IF;
        IF r.MOBILIDADE_REDUZIDA = 1 THEN v_pts := v_pts + 2; END IF;
        IF r.CONDICAO_CRONICA = 1 THEN v_pts := v_pts + 2; END IF;
        IF r.IDADE >= 70 THEN v_pts := v_pts + 2; END IF;
        IF r.CLASSE_CALOR IS NOT NULL THEN
            v_pts := v_pts + (r.CLASSE_CALOR - 1);
        END IF;
        IF NVL(r.IPVS_GRUPO, 0) >= 5 THEN
            v_pts := v_pts + 2;
        ELSIF r.IPVS_GRUPO = 4 THEN
            v_pts := v_pts + 1;
        END IF;
        v_dist := fn_distancia_refugio_m(r.LAT, r.LON);
        IF v_dist IS NULL OR v_dist > c_raio_refugio_m THEN
            v_pts := v_pts + 1;
        END IF;
        RETURN v_pts;
    END fn_pontuacao;

    FUNCTION fn_motivo (p_pessoa_id IN NUMBER) RETURN VARCHAR2 IS
        r      c_pessoa%ROWTYPE;
        v_txt  VARCHAR2(400);
        v_dist NUMBER;
    BEGIN
        carregar_pessoa(p_pessoa_id, r);
        IF r.MORA_SOZINHO = 1 THEN v_txt := v_txt || 'mora sozinho(a) · '; END IF;
        IF r.MOBILIDADE_REDUZIDA = 1 THEN v_txt := v_txt || 'mobilidade reduzida · '; END IF;
        IF r.CONDICAO_CRONICA = 1 THEN v_txt := v_txt || 'condição crônica · '; END IF;
        v_txt := v_txt || r.IDADE || ' anos · setor nota ' || NVL(TO_CHAR(r.CLASSE_CALOR), '?')
                       || ' · IPVS ' || NVL(TO_CHAR(r.IPVS_GRUPO), '?');
        v_dist := fn_distancia_refugio_m(r.LAT, r.LON);
        IF v_dist IS NULL THEN
            v_txt := v_txt || ' · sem refúgio público';
        ELSE
            v_txt := v_txt || ' · refúgio a '
                  || TO_CHAR(ROUND(v_dist / 1000, 1), 'FM990D0', 'NLS_NUMERIC_CHARACTERS='',.''') || ' km';
        END IF;
        RETURN v_txt;
    END fn_motivo;

    FUNCTION fn_elegivel (p_pessoa_id IN NUMBER, p_nivel IN NUMBER) RETURN NUMBER IS
        r      c_pessoa%ROWTYPE;
        v_ipvs NUMBER;
    BEGIN
        carregar_pessoa(p_pessoa_id, r);
        v_ipvs := NVL(r.IPVS_GRUPO, 0);
        IF r.CONSENTIMENTO_LGPD <> 1 OR NVL(r.IDADE, 0) < 60 OR p_nivel IS NULL OR p_nivel < 3 THEN
            RETURN 0;
        ELSIF p_nivel >= 5 THEN
            RETURN 1;
        ELSIF p_nivel = 4 AND v_ipvs >= 4 THEN
            RETURN 1;
        ELSIF p_nivel = 3 AND r.IDADE >= 70 AND v_ipvs >= 5 THEN
            RETURN 1;
        END IF;
        RETURN 0;
    END fn_elegivel;

    PROCEDURE prc_gerar_lista_dia (p_data    IN  DATE,
                                   p_nivel   IN  NUMBER DEFAULT NULL,
                                   p_listas  OUT NUMBER,
                                   p_pessoas OUT NUMBER) IS
        v_data     DATE   := TRUNC(p_data);
        v_nivel    NUMBER := p_nivel;
        v_id_lista NUMBER;
        v_qtd      NUMBER;

        -- Uma lista por UBS que tenha pessoas acompanhadas com consentimento.
        CURSOR c_ubs IS
            SELECT DISTINCT UBS_REF_ID
              FROM TMC_PESSOA_SINTETICA
             WHERE UBS_REF_ID IS NOT NULL AND CONSENTIMENTO_LGPD = 1
             ORDER BY UBS_REF_ID;
    BEGIN
        p_listas  := 0;
        p_pessoas := 0;

        IF v_nivel IS NULL THEN
            v_nivel := fn_nivel_vigente(v_data);
        END IF;
        IF v_nivel IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'Sem nível de calor para ' || TO_CHAR(v_data, 'DD/MM/YYYY')
                                            || '. Informe o nível.');
        END IF;
        IF v_nivel NOT BETWEEN 1 AND 5 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Nível de calor deve estar entre 1 e 5 (recebido: ' || v_nivel || ').');
        END IF;

        -- NC1 e NC2: não há busca ativa; encerra as listas que estiverem abertas no dia.
        IF v_nivel < 3 THEN
            UPDATE TMC_LISTA_BUSCA
               SET STATUS = 'ENCERRADA', ENCERRADA_EM = SYSTIMESTAMP
             WHERE DATA_LOCAL = v_data AND STATUS = 'ABERTA';
            RETURN;
        END IF;

        FOR u IN c_ubs LOOP
            MERGE INTO TMC_LISTA_BUSCA l
            USING (SELECT v_data AS DATA_LOCAL, u.UBS_REF_ID AS UBS_ID FROM DUAL) s
               ON (l.DATA_LOCAL = s.DATA_LOCAL AND l.UBS_ID = s.UBS_ID)
             WHEN MATCHED THEN
                  UPDATE SET l.NIVEL = v_nivel, l.STATUS = 'ABERTA', l.ENCERRADA_EM = NULL,
                             l.GERADA_EM = SYSTIMESTAMP, l.VERSAO_REGRA = c_versao_regra
             WHEN NOT MATCHED THEN
                  INSERT (DATA_LOCAL, UBS_ID, NIVEL, VERSAO_REGRA)
                  VALUES (s.DATA_LOCAL, s.UBS_ID, v_nivel, c_versao_regra);

            SELECT ID_LISTA INTO v_id_lista
              FROM TMC_LISTA_BUSCA
             WHERE DATA_LOCAL = v_data AND UBS_ID = u.UBS_REF_ID;

            -- Quem ainda não foi contatado sai e entra de novo com a pontuação de agora.
            DELETE FROM TMC_ITEM_LISTA WHERE ID_LISTA = v_id_lista AND STATUS = 'PENDENTE';

            INSERT INTO TMC_ITEM_LISTA (ID_LISTA, PESSOA_ID, PONTUACAO, MOTIVO)
            SELECT v_id_lista, p.ID, PKG_PRIORIZACAO.fn_pontuacao(p.ID), PKG_PRIORIZACAO.fn_motivo(p.ID)
              FROM TMC_PESSOA_SINTETICA p
             WHERE p.UBS_REF_ID = u.UBS_REF_ID
               AND PKG_PRIORIZACAO.fn_elegivel(p.ID, v_nivel) = 1
               AND NOT EXISTS (SELECT 1 FROM TMC_ITEM_LISTA i
                                WHERE i.ID_LISTA = v_id_lista AND i.PESSOA_ID = p.ID);

            -- Posição: maior pontuação, depois o mais velho, depois o menor id.
            MERGE INTO TMC_ITEM_LISTA i
            USING (SELECT it.ID_ITEM,
                          ROW_NUMBER() OVER (ORDER BY it.PONTUACAO DESC, p.IDADE DESC, p.ID) AS POS
                     FROM TMC_ITEM_LISTA it
                     JOIN TMC_PESSOA_SINTETICA p ON p.ID = it.PESSOA_ID
                    WHERE it.ID_LISTA = v_id_lista) s
               ON (i.ID_ITEM = s.ID_ITEM)
             WHEN MATCHED THEN UPDATE SET i.POSICAO = s.POS;

            SELECT COUNT(*) INTO v_qtd FROM TMC_ITEM_LISTA WHERE ID_LISTA = v_id_lista;
            IF v_qtd = 0 THEN
                DELETE FROM TMC_LISTA_BUSCA WHERE ID_LISTA = v_id_lista;   -- UBS sem ninguém no alcance
            ELSE
                p_listas  := p_listas + 1;
                p_pessoas := p_pessoas + v_qtd;
            END IF;
        END LOOP;
    END prc_gerar_lista_dia;

END PKG_PRIORIZACAO;
/

SHOW ERRORS PACKAGE PKG_PRIORIZACAO
SHOW ERRORS PACKAGE BODY PKG_PRIORIZACAO
