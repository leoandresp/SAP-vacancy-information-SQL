/*
Propósito: Generar un reporte de cargos organizacionales que incluye:
- Cargos ocupados (con información del empleado actual).
- Cargos vacantes (con campos personales vacíos, manteniendo datos organizacionales del último ocupante).
- Información de vacantes asociadas (estado Abierto/Cerrado).
- Excluye registros de la Sociedad BUKRS 'DUMMY_SOCIEDAD_EXCLUIDA'.

Autor: LEONARDO POLANCO
Fecha de Creación: 30-07-2025
Última Modificación: 2025-07-30

Tablas:
HRP1000: Datos maestros de objetos (Cargos/Posiciones, Unidades Organizativas).
HRP1001: Relaciones entre objetos (Asignación Personas-Cargos, Posición de Jefe).
HRP1007: Datos maestros de Vacantes (Asociación Vacante/Posición y su Status).
PA0001: Infotipo 0001 - Maestro de Personas (Asignación Organizacional, Centro de Coste).
PA0016: Infotipo 0016 - Datos de Contratos (Utilizada para contar contratos y determinar tipo Fijo/Contratado).
PA0004: Infotipo 0004 - Discapacidad (Utilizada para identificar condición de trabajador).
T001P: Subdivisión de Personal (Descripciones de Sucursales/Subdivisiones).
T527X: Unidades Organizativas (Descripciones de Unidades Organizativas).
CSKS: Datos maestros de Centros de Coste (Responsable del Centro de Coste).
T528T: Posiciones (Descripciones de Posiciones).
T513S: Funciones (Descripciones de Funciones).
PA0007: Infotipo 0007 - Horario de Trabajo (Referencia al Esquema de Horario).
T508S: Esquemas de Horario de Trabajo (Descripciones de Horarios).

Notas Importantes:
1. La fecha '99991231' representa en SAP que el registro está vigente.
2. Para cargos vacantes, se mantienen los datos organizacionales del último ocupante a través de la tabla HRP1001.
3. El filtro final excluye todos los registros de la Sociedad (BUKRS) 'DUMMY_SOCIEDAD_EXCLUIDA'.
*/
WITH
  /* CTE CARGOS:
     Obtiene el registro vigente de cada cargo (posición organizacional) */
  CARGOS AS (
    SELECT
        ROW_NUMBER() OVER(PARTITION BY "OBJID" ORDER BY "ENDDA" DESC) AS RowNum,
        "OBJID", "SHORT", "STEXT", "BEGDA", "ENDDA"
    FROM "SAP_ECC"."HRP1000"
    WHERE "OTYPE" = 'S' AND "LANGU" = 'S' AND "ENDDA" = '99991231' -- Filtro por Cargo (S), idioma Español (S) y Vigente
  ),

  /* CTE ASIGNACIONES_PERSONAS:
     Identifica la última asignación persona-cargo (vigente o histórica)
     - 'SOBID' = Persona actual (si ENDDA = '99991231') o última persona.
     - 'COD_PERSONA_ANT' = Persona anterior a la actual/última (usando LEAD). */
  ASIGNACIONES_PERSONAS AS (
    SELECT
        ROW_NUMBER() OVER(PARTITION BY "OBJID" ORDER BY "ENDDA" DESC) AS RowNum,
        LEAD("SOBID") OVER(PARTITION BY "OBJID" ORDER BY "ENDDA" DESC) AS COD_PERSONA_ANT,
        "OBJID", "SOBID", "ENDDA"
    FROM "SAP_ECC"."HRP1001"
    WHERE "SCLAS" = 'P' -- Relación con Personas
  ),

  /* CTE POS_JEFE_INMEDIATO:
     Identifica la posición (OBJID) del Jefe Inmediato (SOBID) para cada cargo
     - Relación A002 (Posee) entre Cargo (S) y Cargo (S) */
    POS_JEFE_INMEDIATO AS (
    SELECT
        ROW_NUMBER() OVER(PARTITION BY "OBJID" ORDER BY "ENDDA" DESC) AS RowNum,
        "OBJID", "SOBID", "ENDDA"
    FROM "SAP_ECC"."HRP1001"
     WHERE "OTYPE" = 'S' AND "RSIGN" = 'A' AND "RELAT" = '002' -- Relación A002: Posee
  ),

  /* CTE VACANTES:
     Obtiene el último estado de vacantes ('VACAN') asociadas a cargos y su 'STATUS' */
  VACANTES AS (
    SELECT
        ROW_NUMBER() OVER(PARTITION BY "OBJID" ORDER BY "ENDDA" DESC) AS RowNum,
        "OBJID", "VACAN", "STATUS"
    FROM "SAP_ECC"."HRP1007"
  ),

  /* CTE PERSONAS:
     Datos actuales de empleados (solo registros vigentes '99991231') del infotipo 0001 */
  PERSONAS AS (
    SELECT
        "PERNR", "SNAME", FIRST_VALUE("BEGDA") OVER(PARTITION BY "PERNR" ORDER BY "BEGDA") AS "BEGDA",
        "PERSG", "WERKS", "PERSK", "BTRTL",
        "KOSTL", "ORGEH", "PLANS", "STELL", "BUKRS", "ENDDA"
    FROM "SAP_ECC"."PA0001"
    -- Se asume que el filtro de vigencia se aplica en el JOIN para obtener solo datos actuales
  ),

  -- tabla que guarda la informacion de los contratos (Infotipo 0016)
  CANT_CONTRATOS AS(
  	SELECT
  	"PERNR",
  	COUNT("PERNR") AS CANTCONTRATOS,
  	MIN(BEGDA) AS FECHAINICIO,
  	MAX(ENDDA) AS FECHAFIN
  	FROM "SAP_ECC"."PA0016" WHERE BEGDA <= CURRENT_DATE AND CTTYP = '08' -- Contratos Tipo '08'
  	GROUP BY "PERNR"
  )

-- CONSULTA PRINCIPAL
SELECT DISTINCT
    c."OBJID" AS NUMCARGO,
    c."SHORT" AS CARGO,
    c."STEXT" AS DETCARGO,

    v."STATUS" AS STATUSVACANTE,

    /* Descripción del estado de vacante:
       - '0' = Abierto, otros valores = Cerrado */
    CASE v."STATUS"
        WHEN '0' THEN 'Abierto'
        ELSE 'Cerrado'
    END AS DETESTATUSVACANTE,

    /* Campos de persona: Se muestran SOLO si el cargo está VIGENTE (enl."ENDDA" = '99991231') */
    COALESCE(pa."PERNR",'') AS CODPERSONA_ANT, -- Código de la persona anterior
    COALESCE(pa."SNAME",'') AS NOMBREPERSONA_ANT, -- Nombre de la persona anterior
    CASE WHEN enl."ENDDA" = '99991231' THEN p."PERNR" ELSE '' END AS CODPERSONA,
    CASE WHEN enl."ENDDA" = '99991231' THEN p."SNAME" ELSE '' END AS NOMBRE,
    CASE WHEN enl."ENDDA" = '99991231' THEN p."BEGDA" ELSE '' END AS FECHAINGRESO,


    -- Campos Organizacionales y Descriptivos
	CASE WHEN enl."ENDDA" = '99991231' THEN pj."PERNR" ELSE '' END AS COD_JEFE_INMEDIATO, -- Código del Jefe (Persona)
	CASE WHEN enl."ENDDA" = '99991231' THEN pj."SNAME" ELSE '' END AS NOMBRE_JEFE_INMEDIATO, -- Nombre del Jefe (Persona)
    CASE WHEN enl."ENDDA" = '99991231' THEN sps."BTEXT" ELSE '' END AS DETSUBDIVISIONPERSONAL, -- Descripción de Subdivisión
    CASE WHEN enl."ENDDA" = '99991231' THEN p."KOSTL" ELSE '' END AS CENTROCOSTE,
    CASE WHEN enl."ENDDA" = '99991231' THEN cc."VERAK" ELSE '' END AS RESPONSABLECENTROCOSTE, -- Responsable de CC (desde CSKS)
    CASE WHEN enl."ENDDA" = '99991231' THEN uo."ORGTX" ELSE '' END AS DETUNORG, -- Descripción de Unidad Organizativa

	CASE
	    WHEN enl."ENDDA" = '99991231' THEN
	        CASE
	            WHEN deth."RTEXT" LIKE '%opm%' THEN REPLACE(deth."RTEXT", 'opm', '0pm')
	            ELSE deth."RTEXT"
	        END
	    ELSE ''
	END AS DETHORARIO, -- Descripción de Horario con reemplazo específico (opm -> 0pm)

	-- Determina si el estatus de contrato es 'FIJO' (Infotipo 0016 Tipo '01' vigente) o 'CONTRATADO'
	CASE
		WHEN enl."ENDDA" = '99991231' THEN
			CASE
			WHEN pf."PERNR" IS NOT NULL THEN 'FIJO'
			ELSE 'CONTRATADO' END
		ELSE ''
	END STATUSCONTRATO,

	-- Datos de contratos SOLO si el estatus no es 'FIJO'
	CASE WHEN pf."PERNR" IS NULL THEN
	CASE WHEN enl."ENDDA" = '99991231'  THEN ctc.CANTCONTRATOS ELSE NULL END
	ELSE NULL END AS CANTCONTRATOS,

	CASE WHEN pf."PERNR" IS NULL THEN
	CASE WHEN enl."ENDDA" = '99991231' THEN ctc.FECHAINICIO ELSE NULL END
	ELSE NULL END AS FECHAINICIO,

	CASE WHEN pf."PERNR" IS NULL THEN
	CASE WHEN enl."ENDDA" = '99991231' THEN ctc.FECHAFIN ELSE NULL END
	ELSE NULL END AS FECHAFIN,


    -- Condición de trabajador: Muestra 'Invalidez' si existe registro en Infotipo 0004 vigente
		CASE
	    WHEN enl."ENDDA" = '99991231' THEN
	        CASE
	            WHEN dis."PERNR" IS NOT NULL THEN 'Invalidez'
	            ELSE ''
	        END
	    ELSE ''
	END AS CONDICIONTRABAJADOR


-- JERARQUÍA PRINCIPAL DE JOINS
FROM CARGOS c
/* Última asignación persona-cargo (vigente o histórica) */
LEFT JOIN ASIGNACIONES_PERSONAS enl
    ON c."OBJID" = enl."OBJID"
    AND enl.RowNum = 1
-- JOIN para la posición del Jefe Inmediato
LEFT JOIN POS_JEFE_INMEDIATO jf
	ON c."OBJID" = jf."OBJID"
	 AND jf.RowNum = 1

/* Último estado de vacante asociada al cargo */
LEFT JOIN VACANTES v
    ON c."OBJID" = v."OBJID"
    AND v.RowNum = 1

/* Datos de persona actual (solo vigentes) o la última persona que ocupó el cargo */
LEFT JOIN PERSONAS p
    ON enl."SOBID" = p."PERNR" AND p."ENDDA" = '99991231' -- Solo persona con registro vigente
-- JOIN para datos de la persona ANTERIOR (si aplica)
LEFT JOIN "SAP_ECC"."PA0001" AS pa
    ON enl."COD_PERSONA_ANT" = pa."PERNR"
-- JOIN Persona Jefe Inmediato (unida por PLANS de la posición del Jefe en HRP1001)
LEFT JOIN PERSONAS pj
	ON jf."SOBID" = pj."PLANS" AND pj."ENDDA" = '99991231'

/* JOINS PARA DATOS DESCRIPTIVOS: */
-- Subdivisión personal (sucursal)
LEFT JOIN "SAP_ECC"."T001P" sps
    ON p."BTRTL" = sps."BTRTL"

-- Unidad organizativa (vigente, español)
LEFT JOIN "SAP_ECC"."T527X" uo
    ON p."ORGEH" = uo."ORGEH"
    AND uo."ENDDA" = '99991231'
    AND uo."SPRSL" = 'S'

-- Centro de costo (vigente)
LEFT JOIN "SAP_ECC"."CSKS" cc
    ON p."KOSTL" = cc."KOSTL"
    AND cc."DATBI" = '99991231'

-- Posición (vigente, español)
LEFT JOIN "SAP_ECC"."T528T" pos
    ON p."PLANS" = pos."PLANS"
    AND pos."ENDDA" = '99991231'
    AND pos."SPRSL" = 'S'

-- Función (vigente, español)
LEFT JOIN "SAP_ECC"."T513S" fun
    ON p."STELL" = fun."STELL"
    AND fun."ENDDA" = '99991231'
    AND fun."SPRSL" = 'S'

-- Horario vigente de la persona
LEFT JOIN "SAP_ECC"."PA0007" h
    ON p."PERNR" = h."PERNR"
    AND h."ENDDA" = '99991231'

-- Descripción de horario (formato específico VE, español)
LEFT JOIN "SAP_ECC"."T508S" deth
    ON h."SCHKZ" = deth."SCHKZ"
    AND deth."MOFID" = 'VE'
    AND deth."SPRSL" = 'S'

-- Conteo de Contratos Tipo '08'
LEFT JOIN CANT_CONTRATOS ctc
	ON ctc."PERNR" = enl."SOBID"
-- Personal fijo en la empresa (Contrato Tipo '01' vigente)
LEFT JOIN (SELECT "PERNR" FROM "SAP_ECC"."PA0016" WHERE BEGDA <= CURRENT_DATE AND "ENDDA" = '99991231' AND CTTYP = '01') pf
	ON pf."PERNR" = enl."SOBID"


-- JOIN con información de usuarios con discapacidad (Infotipo 0004)
LEFT JOIN (SELECT DISTINCT "PERNR" FROM "SAP_ECC"."PA0004" WHERE  "ENDDA" = '99991231') dis
    ON enl."SOBID" = dis."PERNR"

/* FILTROS FINALES:
   - Solo el último registro de cada cargo (RowNum = 1)
   - Exclusión de una Sociedad específica
 */
WHERE
-- Excluimos la Sociedad DUMMY_SOCIEDAD_EXCLUIDA
    c.RowNum = 1 AND p."BUKRS" <> 'DUMMY_SOCIEDAD_EXCLUIDA'
