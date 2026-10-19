# ADRs — Decisiones de implementación clave

**Fecha:** 16 Oct 2026 · Decisiones abiertas del TRD resueltas. Formato corto: contexto → decisión → consecuencias. Cualquier cambio futuro se registra como un ADR nuevo que reemplaza al anterior.

**Actualización 16 Oct 2026:** al unificar `trd.md`, `esquema-backend.md`, `contratos-api.md`, `backlog.md` y `especificaciones-interaccion.md`, los ADR-001, 003, 004 y 005 se ajustaron (marcados como *Actualizado*) y se registraron los ADR-006 a ADR-014 con las decisiones tomadas en esa revisión.

**Actualización 18 Oct 2026:** tras el rediseño de la interfaz (`diseño-interfaz.pen`) se registran los ADR-015 a ADR-018 (reloj del navegador para textos relativos, paletas fijas de color, stack del frontend y permisos en la interfaz).

| ADR | Tema |
|---|---|
| 001 | Estrategia de `position` |
| 002 | Rate limiting |
| 003 | Rotación de refresh tokens |
| 004 | Límites de campos y estructurales |
| 005 | Jobs programados |
| 006 | Zona horaria única de la aplicación |
| 007 | Sesión: access token en memoria y refresh en cookie |
| 008 | Notificaciones dentro de la app |
| 009 | Eliminación de cuenta con sesión de recuperación |
| 010 | Límites estructurales del tablero |
| 011 | Tareas completadas fuera del kanban |
| 012 | Control optimista acotado |
| 013 | Búsqueda con `pg_trgm` |
| 014 | Almacenamiento de avatares |
| 015 | Reloj del navegador solo para textos relativos y saludo |
| 016 | Paletas fijas de color (tablero y etiqueta) |
| 017 | Stack del frontend: React + Vite + TypeScript |
| 018 | Permisos en la interfaz derivados por el cliente |

---

## ADR-001 — Estrategia de `position` para columnas y tareas *(Actualizado)*
**Contexto:** drag & drop en tiempo real necesita inserción entre vecinos sin reescribir todo el conjunto.

**Decisión:** enteros con separación fija. `position = 1000` para el primer elemento y para insertar entre A y B se usa `(A+B)/2`. Si la separación baja de 1, el servicio **rebalancea** la columna/tablero completo (valores 1000, 2000, …) en la misma transacción y publica el orden final en el evento (`TaskMoved`/`ColumnReordered` con `order[]`).

Precisiones:
- La restricción única `(columnId, position)` y `(boardId, position)` es **diferible** para poder rebalancear dentro de la transacción.
- En las **peticiones** (`move`, `reopen`, `PATCH .../position`) `position` es el **índice destino** (0 = primero); el servidor calcula el valor almacenado a partir de los vecinos en ese momento.
- Una tarea completada tiene `position = null`; al completar no se renumera la columna.
- Las subtareas se agregan al final (`max + 1000`); reordenarlas queda fuera de la v1.

**Alternativas consideradas:** índice fraccionario decimal/lexicográfico (menos rebalanceos, más complejo de leer y depurar); listas enlazadas (peor para consultas).

**Consecuencias:** implementación simple y consultas ordenadas nativas (`ORDER BY position`); el rebalanceo es raro a escala v1; el cliente siempre reconcilia con el `order[]` recibido. Como el destino se pide por índice, dos movimientos simultáneos pueden dejar una tarjeta una posición corrida; la regla de concurrencia sigue siendo "última escritura gana" y el evento corrige a todos.

---

## ADR-002 — Rate limiting
**Contexto:** TRD exige límites en login, correos y lookup de usuarios. Un solo nodo en v1.

**Decisión:** **Bucket4j en memoria** por clave (usuario autenticado o IP+endpoint) con configuración por endpoint: login 5/min, envío de correos 3/10 min, lookup de usuarios 10/min. Respuesta `429 RATE_LIMITED` con `Retry-After`.

**Consecuencias:** sin infraestructura extra; los límites no son compartidos entre nodos. Al escalar horizontalmente (broker externo, ver TRD §9) se migra a buckets en Redis manteniendo la misma configuración.

---

## ADR-003 — Rotación de refresh tokens *(Actualizado)*
**Contexto:** sesiones revocables (logout real, cambio de contraseña, reuso detectado).

**Decisión:** rotación de un solo uso. Cada `POST /api/auth/refresh` marca `revokedAt` en el token usado, lo enlaza con el nuevo (`replacedById`) y emite uno nuevo en la misma "familia" (la cadena de rotación). Si llega un token ya revocado → se revocan **todas** las sesiones del usuario (posible robo) y se responde **401** `TOKEN_ALREADY_USED`. El cambio de contraseña y la solicitud de eliminación de cuenta revocan todas las sesiones. La entrega del token (cookie) está en ADR-007.

**Consecuencias:** protección contra reuso con costo mínimo; los tokens se guardan con hash SHA-256 (`tokenHash`), nunca en claro. El navegador conserva siempre la última cookie, pero el cliente debe **serializar las llamadas a `refresh`** (una sola a la vez; las demás esperan su resultado) para que dos peticiones simultáneas no se interpreten como reuso.

---

## ADR-004 — Límites de campos *(Actualizado)*
**Decisión (validados en servicio + UI):**

| Campo | Límite |
|---|---|
| Nombre de tablero | 100 caracteres |
| Descripción de tablero | 500 caracteres |
| Nombre de columna | 50 caracteres |
| Título de tarea / subtarea | 200 caracteres |
| Descripción de tarea | 4000 caracteres |
| Comentario | 2000 caracteres de texto visible (cada mención cuenta como `@Nombre`) |
| Nombre de etiqueta | 50 caracteres |
| Nombre de usuario | 100 caracteres |
| Título o profesión (`jobTitle`) | 100 caracteres |
| Correo | 254 caracteres |
| Contraseña | mínimo 8, al menos 1 número, máximo 72 bytes (límite de bcrypt) |
| Etiquetas por tarea | 3 |
| Avatar | PNG/JPG/WebP, máximo 2 MB |
| Texto de búsqueda (`q`) | mínimo 2 caracteres |

Los límites estructurales (columnas, tareas por columna y subtareas) están en ADR-010.

**Consecuencias:** los límites se aplican con `VALIDATION_FAILED` y contador visible en los campos largos (descripción/comentario) al llegar al 90 %. Los valores de nombre de columna, nombre de usuario, `jobTitle`, correo, contraseña máxima y avatar se añadieron el 16 Oct 2026 y son configurables.

---

## ADR-005 — Jobs programados *(Actualizado)*
**Contexto:** expiración de invitaciones, purga de cuentas, limpieza de tokens vencidos, y desde la v1 las notificaciones programadas (ADR-008).

**Decisión:** **Spring `@Scheduled`** en el mismo proceso, con idempotencia (consultas por estado+vencimiento o `dedupeKey`) y sin solapamiento (`fixedDelay` para el job horario; protección en proceso para los de `cron`). Un solo nodo en v1.

| Job | Frecuencia |
|---|---|
| Expiración de invitaciones | cada hora |
| Purga de cuentas | diario, 03:00 UTC |
| Limpieza de tokens vencidos | diario, 03:00 UTC |
| Limpieza de notificaciones | diario, 03:00 UTC |
| Recordatorios de vencimiento | diario, 08:00 en `APP_TIMEZONE` |
| Resumen semanal | lunes, 08:00 en `APP_TIMEZONE` |

Los jobs de mantenimiento no dependen del día local y usan UTC; los que dependen del día del usuario usan la zona de la aplicación (ADR-006).

**Consecuencias:** sin Quartz ni colas; al escalar a múltiples nodos se migra a ShedLock o a un job externo (registrado como pendiente). Los fallos se registran y se reintentan en el siguiente ciclo.

---

## ADR-006 — Zona horaria única de la aplicación
**Contexto:** "hoy", "vence mañana", "esta semana", los recordatorios y los grupos de Mis tareas dependen de qué día es. Comparar la fecha del navegador con la del servidor producía diferencias de un día en el borde.

**Decisión:** la aplicación usa **una sola zona horaria**, configurable con la variable de entorno `APP_TIMEZONE` (zona IANA, por defecto `UTC`). El servidor calcula "hoy", la semana (lunes a domingo), los grupos (`bucket`) de Mis tareas y los contadores; las respuestas que lo necesitan incluyen `today`. Las marcas de tiempo (`Instant`) se guardan en UTC y las fechas límite son `LocalDate` sin zona.

**Alternativas consideradas:** campo `timezone` por usuario (más exacto, pero exige enviarlo al registrarse, mantenerlo y calcular por usuario en los jobs).

**Consecuencias:** resultados consistentes entre cliente y servidor; los usuarios en otra zona ven el día de la aplicación. Si se necesita zona por usuario, se registra un ADR nuevo que reemplaza a este.

---

## ADR-007 — Sesión: access token en memoria y refresh en cookie
**Contexto:** el refresh token es el secreto de mayor vida y no debe quedar al alcance del JavaScript de la página.

**Decisión:** el **access token** (15 min) viaja en el cuerpo de la respuesta y el cliente lo guarda en memoria. El **refresh token** (7 días, configurable) viaja solo en una cookie `HttpOnly; Secure; SameSite=Lax; Path=/api/auth`. CORS permite únicamente el origen `FRONTEND_URL` con credenciales. Tras el login con Google, el backend deja la cookie y redirige a `FRONTEND_URL`, donde el cliente llama a `refresh` (nunca viaja un token en la URL). El handshake STOMP envía el access token en el frame `CONNECT`.

**Consecuencias:** un XSS no puede leer el refresh token; al recargar la página el cliente recupera la sesión con `refresh`. Requiere configurar `FRONTEND_URL` y `Secure` según el entorno (en local sobre HTTP, `Secure` se desactiva por perfil).

---

## ADR-008 — Notificaciones dentro de la app
**Contexto:** la v1 incluye feed de notificaciones, menciones, recordatorios de vencimiento y resumen semanal, además de la bandeja de invitaciones.

**Decisión:**
- Tabla `notification` (destinatario, tipo, actor, referencias opcionales, `payload` JSONB con una copia de los textos, `dedupeKey`, `readAt`). Se crea en la **misma transacción** del caso de uso que la origina.
- Se entrega al usuario por `/user/queue/notifications` **después de confirmar la transacción** (`AFTER_COMMIT`), con el contador de no leídas.
- Nunca se notifica al autor de la acción, ni a no miembros, ni a cuentas que no estén `ACTIVE`.
- Recordatorios (vence mañana, hoy, venció) y resumen semanal los generan jobs (ADR-005) y son idempotentes por `dedupeKey` (`<taskId>:<dueDate>` y semana ISO).
- La invitación sigue siendo la fuente de verdad de la bandeja; su notificación se marca como leída cuando la invitación deja de estar pendiente.
- Retención: leídas > 90 días y cualquiera > 180 días se eliminan.
- Solo dentro de la app: no hay correos de notificación (salvo el aviso de invitación y el de eliminación de cuenta) ni preferencias configurables en v1.

**Consecuencias:** el feed sobrevive a que el origen se elimine (por el `payload`); el contador se mantiene sincronizado entre pestañas con el evento `NotificationsRead`. Preferencias y correo se podrán agregar con un ADR nuevo.

---

## ADR-009 — Eliminación de cuenta con sesión de recuperación
**Contexto:** el usuario debe poder arrepentirse durante 30 días sin seguir usando la aplicación.

**Decisión:** `DELETE /api/users/me` (solo si no es Owner de tableros con otros miembros) pasa la cuenta a `PENDING_DELETION`, guarda `deletionRequestedAt`, **revoca todas las sesiones** y envía un correo de aviso con la fecha límite de recuperación (`plantillas-correo.md`). Al iniciar sesión (correo o Google) el usuario recibe una **sesión de recuperación** (claim `recovery`) que solo permite `GET /api/users/me`, `POST /api/users/me/restore`, `POST /api/auth/refresh` y `POST /api/auth/logout`; el cliente lo lleva a la vista de recuperación. `restore` solo funciona antes de `deletionRequestedAt + 30 días` (si no, 409 `RECOVERY_PERIOD_EXPIRED`). El job de purga (ADR-005) pasa la cuenta a `DELETED` y la anonimiza, conservando sus comentarios.

**Consecuencias:** el usuario no accede a la app durante la gracia; sus membresías y tareas asignadas se conservan hasta la purga y no recibe notificaciones; no se le puede invitar ni transferir propiedad.

---

## ADR-010 — Límites estructurales del tablero
**Contexto:** evitar que columnas, tareas y subtareas crezcan sin control.

**Decisión:**
- Máximo **12 columnas** por tablero (409 `BOARD_COLUMNS_LIMIT_REACHED`).
- `taskLimit` por columna: obligatorio, entre **1 y 100**, por defecto **50**, editable por Owner y Admin; **bloqueo duro**: crear, mover o reabrir una tarea hacia una columna llena responde 409 `COLUMN_LIMIT_REACHED`. No se puede bajar por debajo de las tareas pendientes que la columna ya tiene (409 `COLUMN_LIMIT_BELOW_CURRENT`). Las tareas completadas no cuentan.
- Máximo **30 subtareas** por tarea (409 `SUBTASKS_LIMIT_REACHED`).
- La validación se hace bloqueando la fila de la columna (o de la tarea) en la transacción para evitar carreras entre movimientos simultáneos.

**Consecuencias:** los valores son configurables; un arrastre rechazado por límite se revierte en el cliente.

---

## ADR-011 — Tareas completadas fuera del kanban
**Contexto:** el TRD se contradecía sobre si existe un estado "completada".

**Decisión:** existe `isDone` con `completedAt`. Una tarea completada **sale del kanban**: `columnId` y `position` quedan nulos (restricción `CHECK`) y `Task.boardId` identifica siempre el tablero. Al **reabrirla** el usuario elige la columna de destino. Las completadas no cuentan como vencidas, no generan recordatorios, no aparecen en el cronograma ni en los contadores, y se listan en la sección de completadas del tablero (`GET /api/boards/{id}/completed-tasks`). "Al día" (todas las subtareas hechas, con fecha límite) es un concepto distinto de `isDone`.

**Consecuencias:** la columna destino se valida contra su límite al reabrir; completar y reabrir emiten `TaskCompleted` y `TaskPending`.

---

## ADR-012 — Control optimista acotado
**Contexto:** el control por versión debe proteger los formularios sin generar conflictos por movimientos en vivo.

**Decisión:** `Task.version` y `Board.version` se incrementan **solo con `PUT`**. Mover, reordenar, asignar, completar y reabrir quedan fuera del bloqueo optimista (`@OptimisticLock(excluded = true)` en `columnId`, `position`, `assigneeId`, `isDone` y `completedAt`). `Board.lastActivityAt` se actualiza con una consulta directa que no toca `version`. Un `PUT` con versión obsoleta responde 409 (`TASK_VERSION_CONFLICT` / `BOARD_VERSION_CONFLICT`) con `currentVersion` y el estado actual; "Sobrescribir" es reenviar el `PUT` con esa versión.

**Consecuencias:** mover una tarjeta no rompe la edición abierta de otra persona; las operaciones en vivo siguen la regla "última escritura gana".

---

## ADR-013 — Búsqueda con `pg_trgm`
**Contexto:** la búsqueda del tablero cubre títulos y descripciones de tareas, etiquetas y comentarios, con coincidencia parcial.

**Decisión:** extensión `pg_trgm` con índices GIN sobre `task.title`, `task.description`, `comment.content` y `tag.name`, y consultas `ILIKE`. Mínimo 2 caracteres, máximo 20 resultados por tipo, solo dentro de tableros donde el usuario es miembro.

**Alternativas consideradas:** full-text (`tsvector`): mejor para texto largo en un idioma, peor para coincidencia parcial de palabras.

**Consecuencias:** simple y suficiente a escala v1; si el volumen crece se evalúa full-text o un motor externo.

---

## ADR-014 — Almacenamiento de avatares
**Contexto:** la v1 incluye subida de avatar y no hay almacenamiento de objetos.

**Decisión:** archivos en un volumen local del servidor (`AVATAR_STORAGE_PATH`) detrás de una interfaz `AvatarStorage`. Se aceptan PNG/JPG/WebP de hasta 2 MB, se renombran con un identificador aleatorio y se sirven por `GET /api/files/avatars/{file}`, público porque una etiqueta de imagen no puede enviar el token (el nombre no es adivinable). Las cuentas Google arrancan con la foto de Google.

**Consecuencias:** sin dependencias nuevas; no apto para varios nodos sin almacenamiento compartido, por lo que se migrará a un almacenamiento de objetos al escalar (ADR nuevo).

---

## ADR-015 — Reloj del navegador solo para textos relativos y saludo
**Contexto:** la interfaz muestra tiempos relativos ("hace 12 min", "Ayer", "expira en 4 días") y un saludo según la hora ("Buenos días"). ADR-006 prohíbe usar la fecha del navegador para decidir vencimientos, pero no cubre estos textos.

**Decisión:** el cliente usa su propio reloj **solo para mostrar** tiempos relativos y para el saludo. Todo lo que implica una regla de negocio ("hoy", "esta semana", vencida, al día, grupos de Mis tareas, rangos del cronograma y del calendario) sigue saliendo del servidor (`today`, `bucket`).

**Alternativas consideradas:** enviar `serverNow` en cada respuesta (exacto, pero añade un campo a varias respuestas y complica el cliente).

**Consecuencias:** sin cambios de API; un desfase de segundos en "hace N min" es aceptable. Si se necesita exactitud, se registra un ADR nuevo.

---

## ADR-016 — Paletas fijas de color (tablero y etiqueta)
**Contexto:** el rediseño de la interfaz (18 Oct 2026) sustituye los colores del diseño anterior (`#FFD43B`, `#BFF05A`, `#7FE3F2`).

**Decisión:** `color` sigue guardándose como hex y el servidor lo valida contra una lista fija. **Tablero (8):** `#4A3FD6 #2563EB #0E8F8F #2E9E5B #D98A00 #E5622B #D6336C #5B6075`. **Etiqueta (6, acento):** `#3B30B0 #1B4DB0 #0B6663 #1A6B3F #8A5200 #A3214F`. El fondo de la etiqueta lo deriva la interfaz a partir del acento.

**Alternativas consideradas:** guardar una clave de paleta (`violet`, `blue`…): permite cambiar colores sin migrar, pero cambia el contrato y los ejemplos.

**Consecuencias:** una migración o semilla que convierta los colores existentes a los nuevos; cualquier otro hex responde `VALIDATION_FAILED`.

---

## ADR-017 — Stack del frontend: React + Vite + TypeScript
**Contexto:** el frontend no tenía stack definido.

**Decisión:** aplicación de una sola página con **React + Vite + TypeScript**. Sugeridos, no obligatorios: TanStack Query (caché y reconciliación), `@stomp/stompjs` (tiempo real), dnd-kit (arrastrar y soltar) y Tailwind con los tokens del diseño (`diseño-interfaz.pen`). En desarrollo, un proxy hacia el backend permite la cookie de refresh (`Path=/api/auth`).

**Consecuencias:** sin servidor propio del frontend; el CORS del backend sigue limitado a `FRONTEND_URL`.

---

## ADR-018 — Permisos en la interfaz derivados por el cliente
**Contexto:** la interfaz oculta acciones según el rol (matriz de `trd.md` §3.2).

**Decisión:** el cliente deriva lo que se muestra de `myRole` (rol en el tablero) y del asignado de cada tarea, con la matriz del TRD documentada en el plan del frontend. El servidor sigue siendo la única autoridad: rechaza lo no permitido con 403/404. Los DTO no incluyen un objeto `permissions`.

**Alternativas consideradas:** enviar `permissions` por tablero y tarea (una sola fuente de verdad, pero más campos y más pruebas de backend).

**Consecuencias:** si cambia la matriz, hay que actualizar el cliente además del servicio; las pruebas de backend por rol siguen siendo obligatorias.
