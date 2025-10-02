# 🧑‍💻 Consulta SQL: Estructura de Personal y Organizacional (Snapshot Actual)

Esta consulta avanzada está diseñada para generar un **snapshot actual y detallado** de la estructura organizacional y la asignación de personal dentro del sistema SAP ECC (módulos OM y PA).

El objetivo es consolidar en un solo registro la información más reciente de cada **cargo** (`PLANS`) y determinar su estado actual: **ocupado** (asignado a una persona) o **vacante**, extrayendo datos clave del empleado asignado y su contexto laboral (jefe, centro de costo, horario, estado de contrato, etc.).

## 🎯 Propósito y Visión General

Proporcionar una vista consolidada para el análisis de la plantilla, que incluya:

1.  **Datos del Cargo:** Identificador, nombre y estado de vacante.
2.  **Datos de la Persona:** Empleado asignado, fecha de ingreso, jefe inmediato y detalles de su asignación.
3.  **Estado de Contrato:** Distinción entre personal **Fijo** y **Contratado**, incluyendo el historial de contratos para estos últimos.
4.  **Información Adicional:** Detalles del centro de costo, unidad organizativa y condición de trabajador (discapacidad).

---

## 🏗️ Estructura de las Common Table Expressions (CTEs)

La consulta se basa en múltiples **CTEs** para pre-filtrar y obtener el registro *más reciente* (o vigente) de cada objeto antes de unirlos. Esto se logra utilizando la función ventana `ROW_NUMBER() OVER(PARTITION BY... ORDER BY ENDDA DESC)` y, a menudo, filtrando por la fecha de fin de validez máxima (`'99991231'`).

| CTE | Tabla Origen | Propósito | Filtros Clave |
| :--- | :--- | :--- | :--- |
| **CARGOS** | `HRP1000` | Último registro del **Puesto/Cargo** (`S`). | `OTYPE = 'S'`, `LANGU = 'S'`, `ENDDA = '99991231'` |
| **ASIGNACIONES_PERSONAS** | `HRP1001` | Última persona asignada a un cargo (vigente o histórica). | `SCLAS = 'P'` (Clase Persona) |
| **POS_JEFE_INMEDIATO** | `HRP1001` | Identifica el cargo del jefe inmediato (Relación `A002`). | `OTYPE = 'S'`, `RSIGN = 'A'`, `RELAT = '002'` |
| **VACANTES** | `HRP1007` | Último estado de la vacante asociada al cargo. | Ninguno específico (solo obtiene el último estado) |
| **PERSONAS** | `PA0001` | Datos maestros actuales de los empleados (acciones y asignaciones). | Se utiliza `FIRST_VALUE(BEGDA)` para obtener la fecha de ingreso más antigua. |
| **CANT_CONTRATOS** | `PA0016` | Cuenta el número de contratos de tipo '08' por empleado (solo vigentes a la fecha actual). | `CTTYP = '08'`, `BEGDA <= CURRENT_DATE` |

---

##
