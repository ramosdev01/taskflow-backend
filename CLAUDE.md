# TaskFlow — Backend

App web colaborativa de gestión de tareas tipo Trello. **Todos los tableros son colaborativos y en tiempo real** (columnas, tareas, subtareas, comentarios, etiquetas, invitaciones, notificaciones). Este repositorio es solo el **backend**; el frontend va aparte (React + Vite + TypeScript, ADR-017).

La especificación completa vive en `docs/`. **Esos documentos son la fuente de verdad: no inventes comportamiento que no esté en ellos.**

## Stack
- Java 25 · Spring Boot 4.1.1 · Maven (`mvnw`) · PostgreSQL 16 (+ extensión `pg_trgm`) · Flyway
- Spring Web, Data JPA, Security (+ OAuth2 Client solo Google), WebSocket (STOMP), Mail, Validation, Scheduling, Actuator
- Bucket4j (rate limit en memoria) · springdoc-openapi (`/swagger`)
- Pruebas: JUnit 5, Testcontainers (PostgreSQL real), Spring Security Test
- Docker / docker-compose (backend, postgres, Mailpit) · GitHub Actions (CI)
- **Usa solo versiones de dependencias compatibles con Spring Boot 4.1.1.** Antes de añadir o cambiar una dependencia o un starter, verifica su compatibilidad con Boot 4 (el framework se modularizó; no asumas nombres de Boot 3).

## Comandos
Entorno de desarrollo: Windows 11 (usa `mvnw.cmd` o Git Bash). Docker Desktop debe estar encendido para los tests de integración.
```
./mvnw clean verify          # compila + tests unitarios e integración (Testcontainers)
./mvnw test                  # solo unitarios
./mvnw spring-boot:run       # arranca el backend (necesita Postgres y Mailpit)
docker compose up -d         # postgres + mailpit (+ backend)
```
- Swagger: `http://localhost:8080/swagger` · Correos de desarrollo (Mailpit): `http://localhost:8025`
- Variables de entorno principales: `SPRING_DATASOURCE_URL`, `JWT_SECRET`, `JWT_ACCESS_TTL`, `JWT_REFRESH_TTL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_FROM`, `FRONTEND_URL`, `APP_TIMEZONE`, `AVATAR_STORAGE_PATH`. Nunca escribas secretos en el código ni en el repositorio.
- Ajusta esta sección cuando cambien los comandos reales.

## Documentación (`docs/`)
| Archivo | Para qué sirve |
|---|---|
| `trd.md` | **Reglas de negocio y permisos** (matriz de roles en §3.2), alcance v1, requisitos no funcionales |
| `esquema-backend.md` | Entidades y restricciones, paquetes, endpoints, tiempo real, seguridad, jobs, Docker, índices, catálogo de errores |
| `contratos-api.md` | Forma exacta de peticiones/respuestas (DTOs), códigos de error con campos extra, payloads de eventos STOMP |
| `adrs.md` | Decisiones técnicas (posiciones, rate limit, tokens, límites, jobs, zona horaria, notificaciones, etc.) |
| `backlog.md` | Épicas e historias con criterios de aceptación (AC) y Definition of Done |
| `plantillas-correo.md` | Los 4 correos transaccionales de v1 |
| `terminos-privacidad.md` | Borrador legal (requiere revisión antes de publicar) |
| `especificaciones-interaccion.md`, `diseño-interfaz.pen`, `diseno-cambios.md` | Comportamiento de la interfaz, diseño (rediseño del 18 Oct 2026) y registro de sus decisiones y hallazgos; sirven de contexto, el backend no los implementa |
| `plan-desarrollo.md` | Plan de trabajo por fases; marca allí las historias terminadas |

**Orden de prioridad si dos documentos se contradicen:** TRD (reglas) → esquema (estructura y endpoints) → contratos (formato de mensajes) → ADRs (decisiones técnicas) → backlog. **No elijas en silencio:** detente, señala la contradicción y propón cuál corregir.

**Los documentos son largos: no los cargues todos.** Lee solo las secciones de la tarea:
- Reglas y permisos de una función → `trd.md` §3.x correspondiente y §3.2
- Tablas, constraints, endpoints → `esquema-backend.md` §1 y §3
- JSON de entrada/salida, errores, eventos → `contratos-api.md` §3, §4 y §5
- Una decisión técnica → el ADR citado en el AC

## Arquitectura
- Monolito modular en `com.taskflow`: `config`, `security`, `user`, `board`, `column`, `task`, `subtask`, `comment`, `tag`, `notification`, `realtime`, `mail`, `storage`, `dashboard`, `common` (ver `esquema-backend.md` §2).
- Cada módulo: `Controller → Service → Repository`, con **DTOs de entrada/salida separados de las entidades JPA**. Las entidades muestran las llaves foráneas explícitas (`taskId`, `authorId`, …).
- **Toda regla de negocio y todo permiso viven en la capa de servicio** (los usa REST y STOMP por igual). Los controladores solo traducen HTTP.
- **Autorización por rol de tablero, no por roles globales:** se resuelve contra `BoardMember` en cada operación (`@PreAuthorize` + `PermissionEvaluator` propio). La matriz exacta está en `trd.md` §3.2.
- Una persona que no es miembro de un tablero recibe **404** `RESOURCE_NOT_FOUND`, no 403.

## Reglas que no se pueden romper
**Datos y tiempo**
- IDs UUID; marcas de tiempo `Instant` (UTC); fechas de calendario `LocalDate`. "Hoy" y "esta semana" se calculan **en el servidor** con `APP_TIMEZONE` (ADR-006); nunca con la fecha del cliente.
- Longitudes y límites: ADR-004 y ADR-010 (12 columnas por tablero, `taskLimit` 1–100 por columna con defecto 50, 30 subtareas por tarea, 3 etiquetas por tarea). Validar bloqueando la fila (`SELECT … FOR UPDATE`) para evitar carreras.
- Orden (`position`): enteros con separación de 1000, punto medio y rebalanceo transaccional (ADR-001). En las **peticiones** `position` es el **índice destino**; el valor guardado lo calcula el servidor. Las restricciones únicas de posición son **diferibles**.
- Tarea completada: `isDone = true` ⇒ `columnId` y `position` nulos (CHECK) y `boardId` siempre presente (ADR-011).
- Control optimista: `version` en `Task` y `Board`, **solo `PUT` la incrementa**; mover, asignar, completar y reabrir quedan fuera (`@OptimisticLock(excluded = true)`). `Board.lastActivityAt` se actualiza con consulta directa sin tocar `version` (ADR-012). Conflicto → 409 con `currentVersion` y `current`.

**Errores**
- RFC 7807 con campo `code`. Los códigos salen del catálogo (`contratos-api.md` §2 = `esquema-backend.md` §10). **Si necesitas un código nuevo, añádelo a ambos catálogos** en el mismo PR.

**Tiempo real y notificaciones**
- Los eventos STOMP se publican **después de confirmar la transacción** (`@TransactionalEventListener(AFTER_COMMIT)`), con el envelope y payloads de `contratos-api.md` §5. Tablero: `/topic/boards/{boardId}`; personal: `/user/queue/notifications`.
- Las notificaciones se crean **en la misma transacción** del caso de uso y se entregan tras el commit. Nunca notificar al autor ni a no miembros ni a cuentas que no estén `ACTIVE`. Recordatorios idempotentes por `dedupeKey` (ADR-008).
- Al quitar/salir/eliminar el tablero se deja de enviar eventos a ese usuario.

**Seguridad**
- Contraseñas con bcrypt costo 12 (mínimo 8, máximo 72 bytes, al menos un número). Tokens de verificación, restablecimiento y refresh se guardan **solo con hash SHA-256**.
- Access token (15 min) en el cuerpo; refresh en cookie `HttpOnly; Secure; SameSite=Lax; Path=/api/auth`, rotación de un solo uso; un token reusado → 401 `TOKEN_ALREADY_USED` y se revocan todas las sesiones (ADR-003, ADR-007).
- Una cuenta creada con correo solo entra con correo, y una con Google solo con Google: **no se vinculan cuentas** (`ACCOUNT_PROVIDER_MISMATCH`).
- Rate limiting con Bucket4j (ADR-002): login 5/min, correos 3 por 10 min, lookup 10/min.
- Eliminación de cuenta: `PENDING_DELETION` + sesión de recuperación (claim `recovery`); la purga anonimiza y conserva comentarios (ADR-009).
- Nunca registres en logs contraseñas, tokens ni cuerpos de autenticación.

**Correo y jobs**
- Solo 4 correos en v1 (`plantillas-correo.md`); un fallo de envío **no** revierte la operación principal.
- Jobs con `@Scheduled`, idempotentes y sin solapamiento (ADR-005).

## Convenciones de código
- Identificadores, entidades, endpoints y códigos de error en **inglés** (tal como están en los documentos); textos de interfaz, mensajes de error (`detail`) y documentación en **español**.
- Cambios de esquema **solo con Flyway** (`V1__init.sql`, `V2__…`). Una migración ya aplicada no se edita: crea una nueva (la excepción es la historia S0-3 mientras se arma `V1`).
- Prefijo `/api` en todos los endpoints; paginación `page`, `size`, `sort`.
- No crees abstracciones, módulos ni funciones "por si acaso" que no pida una historia.

## Cómo trabajar una historia
1. Identifica el ID en `docs/backlog.md` y lee sus **criterios de aceptación** y las secciones que referencia.
2. **Planifica antes de implementar** (modo plan): lista los archivos y migraciones que tocarás, los permisos por rol, los eventos y notificaciones, y los casos de prueba. Si algo no está definido, pregunta en lugar de suponer.
3. Crea una rama por historia desde `develop`: `feature/<id>-descripcion-corta` (o `fix/`, `chore/`).
4. Implementa en pasos pequeños con tests: unitarios, integración con Testcontainers, **una prueba por rol** para cada operación con permisos, y pruebas STOMP si hay eventos.
5. Verifica cada AC y la **Definition of Done** del backlog; actualiza OpenAPI.
6. Si la implementación obliga a cambiar un contrato o una regla, **actualiza los documentos afectados en el mismo PR** (esquema §3 y catálogo de errores, `contratos-api.md`, AC del backlog, y un ADR nuevo si es una decisión técnica).
7. Commits con Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`). PR a `develop` (squash); `develop` → `main` con merge commit. No hagas push directo a `main` ni a `develop`.
8. Al terminar, marca la historia en `docs/plan-desarrollo.md`.

## Fuera de alcance de la v1 (no lo implementes)
Despliegue y CD, adjuntos en tareas, notificaciones por correo (salvo invitación y eliminación de cuenta), preferencias de notificación, presencia, actividad/historial, reordenar subtareas, escalado horizontal (broker externo, Redis, ShedLock), tema oscuro, móvil y tablet.

## Pendientes conocidos
- El stack del frontend es React + Vite + TypeScript (ADR-017); sus historias están en la épica E14 del backlog.
- `terminos-privacidad.md` es un borrador pendiente de revisión legal; falta decidir si se guarda la aceptación de los términos.
- Solo faltan por diseñar en `diseño-interfaz.pen` las páginas públicas de Términos y Privacidad (`especificaciones-interaccion.md` §18); no bloquean el backend. El detalle del rediseño y los hallazgos están en `diseno-cambios.md`.
