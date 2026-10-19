# Backlog v1 — Task Flow

**Fecha:** 16 Oct 2026 · **Base:** `trd.md` + `esquema-backend.md` + `contratos-api.md` + `adrs.md` + `especificaciones-interaccion.md` + diseño `diseño-interfaz.pen` (rediseño del 18 Oct 2026; el detalle de los cambios está en `diseno-cambios.md`)
**Cómo usar:** epics → historias con criterios de aceptación (AC). Tamaños S/M/L (S ≤ 1 día, M 2-3 días, L ≤ 1 semana, estimación gruesa). Cada historia se convierte en un issue; los AC son la base del "done".

**Fuera de alcance (Fase posterior):** actividad/historial, notificaciones por correo (salvo el aviso de invitación y el de eliminación de cuenta), preferencias de notificación, presencia, adjuntos, calendario, reordenar subtareas, despliegue y CD, escalado horizontal del backend, tema oscuro, móvil y tablet.

---

## Sprint 0 — Fundaciones

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| S0-1 | Repositorio y CI base | M | Compila con Java 25 + Maven; GitHub Actions corre build + tests + lint en PR; `main` y `develop` protegidas según TRD §7. |
| S0-2 | Docker de desarrollo | S | `docker-compose up` levanta backend, Postgres 16 y Mailpit, con volúmenes para datos y avatares y healthcheck de Postgres; el backend conecta con variables de entorno (`APP_TIMEZONE`, `FRONTEND_URL`, TTL de JWT, `AVATAR_STORAGE_PATH`). |
| S0-3 | Esqueleto del backend + Flyway | M | Estructura de paquetes del esquema §2; `V1__init.sql` con todas las tablas v1 (incluye `refresh_token`, `comment_mention` y `notification`), restricciones, índices (esquema §9) y extensión `pg_trgm`, aplicada al arrancar. |
| S0-4 | Errores y convenciones de API | S | Respuestas de error RFC 7807 con `code` según el catálogo de `contratos-api.md` §2; paginación `page/size/sort`; prefijo `/api`; OpenAPI publicado en `/swagger`; CORS limitado a `FRONTEND_URL` con credenciales. |
| S0-5 | Seed de datos de prueba | S | Script/servicio opcional (solo perfil dev) que crea usuario demo, tablero con 4 columnas y tareas de ejemplo (incluye una tarea completada, subtareas, un comentario con mención y notificaciones). Los datos siguen las capturas de `diseño-interfaz.pen` para que backend y frontend prueben lo mismo: Jorge Díaz (Owner), Marco Ruiz, Ana Kim y Lucía Pérez; tableros "Lanzamiento del producto", "Rediseño del sitio", "Operaciones Q4" y "Contenido y blog"; columna "En curso" con límite 4 y 4 tareas; "hoy" = 16 OCT 2026; invitaciones pendientes y una notificación de cada tipo. |
| S0-6 | Configuración de zona horaria y límites | S | `APP_TIMEZONE` (por defecto `UTC`) y los límites estructurales (12 columnas, `taskLimit` 1–100 con defecto 50, 30 subtareas) se cargan desde propiedades configurables; con pruebas. |

---

## E1 — Autenticación

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E1-1 | Registro local con verificación por correo | M | `POST /api/auth/register` crea usuario `ACTIVE` con `emailVerifiedAt=null`, valida la política de contraseña (mínimo 8, máximo 72 bytes, al menos un número) y responde `EMAIL_ALREADY_REGISTERED` si el correo existe; envía correo con token de 24 h (hash SHA-256 en `email_verification_token`); reenviar disponible; no abre sesión; pantallas "revisa tu correo" y "enlace expirado". |
| E1-2 | Verificación de correo sin bloqueo | S | `POST /api/auth/verify-email` marca `emailVerifiedAt` (`TOKEN_INVALID` / `TOKEN_EXPIRED` si falla); el acceso nunca se bloquea; el estado se ve en Ajustes > Cuenta con botón "Verificar correo" si falta (sin botón si está verificado); las cuentas Google nacen verificadas. |
| E1-3 | Login + refresh persistido + logout | M | `POST /api/auth/login` devuelve `accessToken` (15 min) en el cuerpo y el refresh token en cookie `HttpOnly; Secure; SameSite=Lax; Path=/api/auth` (ADR-007); el refresh se guarda con hash en `refresh_token`; `POST /api/auth/refresh` rota con un solo uso y un token reusado responde 401 `TOKEN_ALREADY_USED` y revoca todas las sesiones (ADR-003); `POST /api/auth/logout` revoca la sesión actual y borra la cookie; el cliente guarda el access token en memoria y serializa las llamadas a `refresh`. |
| E1-4 | OAuth2 Google y error de proveedor | M | `GET /oauth2/authorization/google` crea/vincula usuario; al terminar deja la cookie de refresh y redirige a `FRONTEND_URL`, donde el cliente llama a `refresh`; si el correo existe con otro proveedor → error `ACCOUNT_PROVIDER_MISMATCH` y pantalla con el aviso. |
| E1-5 | Olvidé mi contraseña + restablecer | M | `forgot-password` responde igual exista o no la cuenta y envía token de 60 min; `reset-password` valida token y política, y revoca todas las sesiones; funciona también para cuentas en eliminación; pantallas de solicitud, enviado, formulario y token inválido/expirado. |
| E1-6 | Rate limiting | S | Bucket4j en memoria (ADR-002): login 5/min, envío de correos 3 por 10 min, lookup de usuarios 10/min; respuesta 429 `RATE_LIMITED` con `Retry-After`; la interfaz deshabilita el botón afectado hasta que pase la espera. |
| E1-7 | Términos y privacidad | S | Páginas públicas de Términos y de Política de Privacidad con el contenido de `terminos-privacidad.md`; el registro exige aceptar con una casilla obligatoria y enlaces, y el acceso con Google muestra los mismos enlaces; no se publican con el aviso de "BORRADOR" ni con `{fecha}` o `{soporte@taskflow.app}` sin reemplazar (requiere revisión legal previa). |

## E2 — Usuario y cuenta

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E2-1 | Ver y editar perfil | S | `GET/PUT /api/users/me` con nombre, `jobTitle` y, solo en cuentas LOCAL, correo (al cambiarlo queda sin verificar y se envía la verificación; `EMAIL_ALREADY_REGISTERED` si ya existe); la respuesta incluye `emailVerified`, `avatarUrl` y `accountState`; límites de campos de ADR-004; la pantalla de Perfil actualiza sin recargar. |
| E2-2 | Cambiar contraseña (solo LOCAL) | S | `PUT /api/users/me/password` valida la actual (`CURRENT_PASSWORD_INCORRECT`) y la política; revoca todas las sesiones y el cliente vuelve al login; el bloque no aparece en cuentas Google. |
| E2-3 | Avatar | M | `POST /api/users/me/avatar` (multipart, PNG/JPG/WebP, máx. 2 MB; `AVATAR_INVALID`) y `DELETE`; almacenamiento local detrás de `AvatarStorage` (ADR-014); `GET /api/files/avatars/{file}` público con nombre no adivinable; sin foto se muestran las iniciales. |
| E2-4 | Solicitar eliminación de cuenta | M | `DELETE /api/users/me`: si es Owner de tableros con otros miembros → 409 `ACCOUNT_DELETE_BLOCKED` y `GET /api/users/me/deletion-blockers` lista los tableros con "Transferir"; si no, pasa a `PENDING_DELETION`, guarda `deletionRequestedAt`, revoca todas las sesiones, envía el correo de aviso con la fecha límite y responde `recoveryDeadline`; el cliente vuelve al login. |
| E2-5 | Sesión y vista de recuperación | M | El login (correo o Google) de una cuenta `PENDING_DELETION` entrega una sesión de recuperación (claim `recovery`) que solo permite `GET /api/users/me`, `POST /api/users/me/restore`, `refresh` y `logout`; el resto responde 403 `ACCOUNT_PENDING_DELETION` y el WebSocket se rechaza; la vista muestra la fecha límite y el botón "Recuperar cuenta" (ADR-009). |
| E2-6 | Recuperar cuenta | S | `POST /api/users/me/restore` antes de `deletionRequestedAt + 30 días` vuelve a `ACTIVE` y borra la solicitud; pasado el plazo → 409 `RECOVERY_PERIOD_EXPIRED` aunque la purga aún no haya corrido; después el cliente llama a `refresh` para obtener una sesión normal. |
| E2-7 | Purga programada | S | Job diario (03:00 UTC) pasa las cuentas `PENDING_DELETION` con más de 30 días a `DELETED` + `deletedAt` y limpia: revoca sesiones, elimina notificaciones, cancela invitaciones pendientes, quita membresías y asignaciones, elimina los tableros donde era el único miembro y anonimiza sus datos conservando sus comentarios; la cuenta ya no puede autenticarse. |

## E3 — Tableros

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E3-1 | Crear tablero | M | `POST /api/boards` crea el tablero (nombre ≤ 100, descripción ≤ 500, color de la paleta fija de 8, ADR-016) con `createDefaultColumns` opcional (por defecto `false`; si es `true` crea Backlog, Por hacer, En curso y Hecho con `taskLimit` 50), etiquetas iniciales opcionales e invitaciones iniciales por lote (resultado por correo: `INVITED` o `SKIPPED` con motivo `USER_NOT_FOUND`, `SELF` o `DUPLICATE`). En la interfaz, el botón "Invitar" del formulario valida el correo con `GET /api/users/lookup` (solo añade el chip si es `FOUND`) y, al crear, un aviso breve resume cuántas invitaciones se enviaron y cuántas no se pudieron enviar; no hay diálogo de resultado. |
| E3-2 | Listar tableros | S | `GET /api/boards` devuelve `myRole`, `taskCount` (pendientes), `completedTaskCount` y `memberCount`; filtro `role=owner\|member`; `sort` por `lastActivityAt`, `updatedAt` o `name` (los tableros recientes del Inicio y del sidebar usan `sort=lastActivityAt,desc&size=4`); la UI separa "MIS TABLEROS" e "INVITADO". |
| E3-3 | Detalle de tablero | M | `GET /api/boards/{id}` devuelve el tablero, columnas (con `taskLimit` y `taskCount`), miembros, etiquetas, tareas pendientes y `today` en una llamada; 404 si no es miembro; `BOARD_LOAD_FAILED` muestra la pantalla de error. |
| E3-4 | Editar tablero | S | `PUT /api/boards/{id}` (nombre, descripción, color de paleta fija, `version`), solo Owner; conflicto → 409 `BOARD_VERSION_CONFLICT` con el estado actual; evento `BoardUpdated`. En la interfaz se abre desde el menú ⋯ del tablero ("Editar tablero") y, ante un conflicto, muestra el banner Recargar / Sobrescribir. |
| E3-5 | Eliminar tablero | S | `DELETE /api/boards/{id}` solo Owner; cascada de columnas/tareas/subtareas/comentarios/etiquetas/miembros/invitaciones; diálogo de confirmación con checkbox; evento `BoardDeleted`. |
| E3-6 | Búsqueda en el tablero | M | `GET /api/boards/{id}/search?q=` busca en títulos, descripciones, etiquetas y comentarios con `pg_trgm` (ADR-013); mínimo 2 caracteres, máximo 20 resultados por tipo; las etiquetas del resultado traen `taskCount`; accesible a todos los miembros; el resultado se muestra en un desplegable con grupos (Tareas, Etiquetas, Comentarios) y, si no hay resultados, un estado "sin resultados" con sugerencias. |

## E4 — Miembros, roles e invitaciones

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E4-1 | Listar miembros | S | `GET /api/boards/{id}/members` con nombre, correo y rol; solo miembros del tablero. |
| E4-2 | Invitar por correo exacto | M | `GET /api/users/lookup?email=&boardId=` responde `FOUND`, `NOT_FOUND`, `ALREADY_MEMBER` (con `role`), `ALREADY_INVITED` (con `invitation.expiresAt`) o `SELF` (10/min; las cuentas en eliminación cuentan como `NOT_FOUND`); `POST /api/boards/{id}/invitations` (Owner/Admin) responde `INVITATION_DUPLICATE`, `ALREADY_MEMBER`, `INVITATION_SELF` o `USER_NOT_FOUND`; envía correo de aviso, emite `InvitationCreated` y crea la notificación `INVITATION_RECEIVED`. |
| E4-3 | Bandeja y respuesta a invitaciones | M | `GET /api/users/me/invitations`; aceptar crea `BoardMember` MEMBER (eventos `InvitationAccepted` y `MemberAdded`, y notifica al invitador); rechazar → `REJECTED`; vencida → `INVITATION_EXPIRED`; ya resuelta → `INVITATION_NOT_PENDING`; aceptar/rechazar SOLO en la app. |
| E4-4 | Cancelar invitación | S | `DELETE /api/invitations/{id}` (Owner/Admin) → `CANCELED`; desaparece de pendientes; evento `InvitationCanceled` y su notificación queda leída. |
| E4-5 | Expiración de invitaciones | S | Job cada hora pasa PENDING vencidas (5 días) a `EXPIRED` (ADR-005); evento `InvitationExpired`; su notificación queda leída. |
| E4-6 | Cambiar rol | S | `PATCH /api/boards/{id}/members/{userId}` solo Owner; ADMIN↔MEMBER; nunca al Owner (`OWNER_CANNOT_BE_REMOVED`); evento `MemberRoleChanged` y notificación `ROLE_CHANGED`. |
| E4-7 | Eliminar miembro | S | `DELETE /api/boards/{id}/members/{userId}` (Owner/Admin); un Admin solo elimina Miembros (`FORBIDDEN`); nunca al Owner; sus tareas quedan sin asignado (`TaskAssigneeChanged`) y se conservan sus comentarios; evento `MemberRemoved` y notificación `REMOVED_FROM_BOARD`. |
| E4-8 | Salir del tablero | S | `DELETE /api/boards/{id}/members/me`; Owner bloqueado (`OWNER_MUST_TRANSFER`) con acceso a transferir; único miembro → equivale a eliminar el tablero; sus tareas quedan sin asignado; evento `MemberLeft`. |
| E4-9 | Transferir propiedad | M | `POST /api/boards/{id}/transfer` con `newOwnerUserId`, solo Owner; el nuevo Owner debe ser miembro activo (`TRANSFER_TARGET_INVALID`; no cuentas en eliminación); el Owner anterior pasa a ADMIN; `Board.ownerId` y roles cambian en una transacción; pide confirmación explícita; evento `OwnershipTransferred` y notificación `OWNERSHIP_TRANSFERRED`. |

## E5 — Columnas

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E5-1 | CRUD de columnas | M | Crear/renombrar/eliminar (Owner/Admin); nombre requerido (≤ 50); máximo 12 columnas por tablero (409 `BOARD_COLUMNS_LIMIT_REACHED`); posición asignada al final al crear (ADR-001). |
| E5-2 | Reordenar columnas (drag & drop) | M | `PATCH /api/columns/{id}/position` con índice destino; inserción por punto medio y rebalanceo transaccional (ADR-001); UI optimista; evento `ColumnReordered` con `order[]`; sin saltos al reconciliar. |
| E5-3 | Eliminar columna en cascada | S | Confirmación muestra el conteo de tareas afectadas (`taskCount`); borra tareas + subtareas + comentarios; la última columna del tablero también se puede eliminar (tablero queda sin columnas → estado "aún no hay columnas"). |
| E5-4 | Límite de tareas por columna | M | `taskLimit` entre 1 y 100 (por defecto 50), editable por Owner/Admin; no puede ser menor que las tareas pendientes de la columna (409 `COLUMN_LIMIT_BELOW_CURRENT`); contador `n/límite` en el encabezado con alerta al 80 %; una columna llena rechaza crear, mover y reabrir (409 `COLUMN_LIMIT_REACHED`) con bloqueo de fila (ADR-010); prueba de dos movimientos simultáneos. |

## E6 — Tareas

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E6-1 | Crear tarea | M | Solo Owner/Admin; desde columna: título (≤ 200), descripción (≤ 4000), prioridad (default MEDIUM), hasta 3 etiquetas, asignado (miembro), `startDate`, `dueDate`; validación `startDate <= dueDate` (`DATE_RANGE_INVALID`); `COLUMN_LIMIT_REACHED` si la columna está llena; se agrega al final de la columna; notifica la asignación. |
| E6-2 | Editar tarea con control optimista | M | `PUT /api/tasks/{id}` envía `version` y `tagIds` y no modifica el asignado; conflicto → 409 `TASK_VERSION_CONFLICT` con `currentVersion` y `current`; la UI muestra el banner Recargar/Sobrescribir; un Miembro solo edita título, descripción y etiquetas de sus tareas (`TASK_FIELD_FORBIDDEN` si intenta fechas o prioridad); mover, asignar, completar y reabrir no incrementan la versión (ADR-012). |
| E6-3 | Mover/reordenar tareas | M | `PATCH /api/tasks/{id}/move` con `columnId` + índice destino; UI optimista; evento `TaskMoved` con `order[]`; regla "última escritura gana" y 409 solo por `COLUMN_LIMIT_REACHED`; un Miembro solo mueve sus tareas; una tarea completada no se mueve (`TASK_ALREADY_COMPLETED`). |
| E6-4 | Asignar tarea | S | `PATCH /api/tasks/{id}/assignee`; solo miembros del tablero (`ASSIGNEE_NOT_MEMBER`); asignado único o vacío; un Miembro solo puede desasignarse de sus propias tareas; evento `TaskAssigneeChanged` y notificación `TASK_ASSIGNED` (no a uno mismo). |
| E6-5 | Eliminar tarea | S | `DELETE /api/tasks/{id}` (Owner/Admin; MEMBER no puede); cascada de subtareas y comentarios. |
| E6-6 | Etiquetas de la tarea | S | Se asignan con `tagIds` al crear o en el `PUT`; hasta 3 (`TAG_LIMIT_EXCEEDED`) y del mismo tablero; eventos `TaskUpdated` y `TaskTagChanged`. |
| E6-7 | Detalle de tarea | M | `GET /api/tasks/{id}`; panel con prioridad editable, fechas, asignado, etiquetas, subtareas y comentarios (paginados); permisos del TRD reflejados (se ocultan las acciones no permitidas). |
| E6-8 | Completar y reabrir tarea | M | `POST /api/tasks/{id}/complete` saca la tarea del kanban (`isDone`, `completedAt`, `columnId` y `position` nulos; evento `TaskCompleted`); `POST /api/tasks/{id}/reopen` con la columna elegida por el usuario (valida el límite; evento `TaskPending`); `TASK_ALREADY_COMPLETED` / `TASK_NOT_COMPLETED`; un Miembro solo las suyas; toast con "Deshacer" (ADR-011). |
| E6-9 | Tareas completadas del tablero | S | `GET /api/boards/{id}/completed-tasks` paginado, más recientes primero; sección "Completadas" del tablero con botón "Reabrir" y selector de columnas (las llenas deshabilitadas). |

## E7 — Subtareas

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E7-1 | CRUD de subtareas | S | Crear/editar/eliminar dentro de la tarea; título requerido (≤ 200); máximo 30 por tarea (409 `SUBTASKS_LIMIT_REACHED`); se agregan al final; un Miembro solo en sus tareas asignadas. |
| E7-2 | Marcar hecha/pendiente | S | `isDone` con evento `SubtaskUpdated`; el progreso (x/y) se actualiza en vivo en tarjetas y detalle. |

## E8 — Comentarios

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E8-1 | Comentar | S | Cualquier miembro comenta cualquier tarea; máximo 2000 caracteres de texto visible; `GET` paginado de más antiguo a más reciente; evento `CommentCreated`; contador en la pestaña. |
| E8-2 | Editar y eliminar comentarios | S | Editar: solo el autor. Eliminar: el autor, los Admins y el Owner (`canEdit` / `canDelete` en el DTO); eventos `CommentUpdated/Deleted`; las acciones se muestran según el permiso. |
| E8-3 | Menciones | M | Escribir `@` abre la lista de miembros del tablero; se guarda `@[Nombre](userId)` y la fila en `comment_mention`; solo miembros actuales (`VALIDATION_FAILED` si no); crea la notificación `MENTION` (no al autor); al editar solo notifican las menciones nuevas. |

## E9 — Etiquetas

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E9-1 | CRUD de etiquetas del tablero | M | Nombre (≤ 50, único por tablero sin distinguir mayúsculas; `TAG_DUPLICATE`) + color (paleta fija de 6 acentos, ADR-016); `GET` incluye `taskCount`; **todos los miembros** pueden crear, editar y eliminar. En la interfaz se gestionan en el diálogo "Etiquetas" del menú ⋯ del tablero, visible para todos los roles; la confirmación de eliminar indica a cuántas tareas afecta. |
| E9-2 | Eliminar etiqueta | S | Cascada en `TaskTag`; eventos `TagDeleted` (con `affectedTaskIds`) y `TaskTagChanged`; las tareas se actualizan en vivo. |

## E10 — Tiempo real

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E10-1 | STOMP autenticado por tablero | M | Conexión `/ws` con JWT en CONNECT (se rechaza el token de recuperación); el `Principal` es el `userId`; suscripción validada por membresía; reconexión con backoff. |
| E10-2 | Catálogo de eventos | L | Todos los eventos del esquema §4 publicados con envelope `{eventId, type, boardId, entityId, actorId, occurredAt, payload}` y los payloads de `contratos-api.md` §5, después de confirmar la transacción (`AFTER_COMMIT`). |
| E10-3 | Estados de conexión (LiveChip) | S | EN VIVO / RECONECTANDO… / SIN CONEXIÓN según el estado del socket; sin parpadeos por reconexiones cortas. |
| E10-4 | Reconciliación de la UI | M | Los eventos actualizan tarjetas/contadores sin recargar y se aplican de forma idempotente (el autor también recibe su evento); si el usuario está editando la misma tarea → banner de conflicto; al reconectar se recarga el tablero y el contador de notificaciones. |
| E10-5 | Cierre de acceso al tablero | S | Al ser removido, salir o eliminarse el tablero, el servidor deja de enviar eventos de ese topic y el cliente se desuscribe, vuelve al listado y muestra un toast. |

## E11 — Inicio, Mis tareas y Cronograma

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E11-1 | Resumen del Inicio y contadores | M | `GET /api/dashboard/summary?limit=`: `today`, `assigned` (pendientes asignadas), `dueToday` y `upcoming` (6 por defecto; vencidas primero, luego por fecha, cada una con `bucket`); excluye tareas completadas; calcula con `APP_TIMEZONE`. `GET /api/me/counters` devuelve `openAssigned` (sin completadas ni "al día") y `unreadNotifications`, para el sidebar. Los tableros recientes salen de `GET /api/boards` (E3-2) y las notificaciones recientes de E13-2. |
| E11-2 | Calendario del mes | S | `GET /api/dashboard/calendar?month=YYYY-MM`: días con tareas asignadas pendientes cuyo `dueDate` cae en ese mes (según `APP_TIMEZONE`), con `boardColor` para los puntos; los días sin tareas se omiten; el Inicio permite cambiar de mes. |
| E11-3 | Mis tareas | M | `GET /api/tasks` con filtros (`assigneeId=me`, tablero, prioridad, `isDone`, vencimiento, texto), paginación y `bucket` por tarea calculado por el servidor; dos secciones: con fecha (VENCIDAS · HOY · ESTA SEMANA · MÁS ADELANTE · AL DÍA) y SIN FECHA al final, ordenada por prioridad; solo tableros donde el usuario es miembro. |
| E11-4 | Cronograma | M | `GET /api/boards/{id}/timeline?from=&to=`; solo tareas pendientes con `dueDate`; cada ítem trae `bucket`; barra `startDate→dueDate` o marcador de un día; línea de HOY con el `today` del servidor; rango por defecto de 4 semanas desde el lunes de la semana en curso y máximo de 92 días; la interfaz permite desplazar el rango, volver a "Hoy" y muestra una leyenda de prioridades. |
| E11-5 | ~~Barra de progreso de tableros~~ | — | **Retirada (18 Oct 2026):** el Inicio rediseñado no muestra la barra de progreso por tablero. |

## E12 — Infraestructura y calidad

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E12-1 | Correo SMTP | S | Mailpit en local; plantillas de verificación, restablecimiento, invitación y eliminación de cuenta (`plantillas-correo.md`) con enlaces basados en `FRONTEND_URL`; fallos de envío no rompen la transacción. |
| E12-2 | Jobs programados | M | Los de ADR-005: invitaciones cada hora; purga de cuentas, limpieza de tokens y de notificaciones a las 03:00 UTC; recordatorios y resumen semanal a las 08:00 en `APP_TIMEZONE`; idempotentes, sin solapamiento y con pruebas. |
| E12-3 | Observabilidad | S | Actuator con health/metrics; logs estructurados con request-id. |
| E12-4 | Validación de límites de campos | S | Los límites de ADR-004 se validan en servicio (`VALIDATION_FAILED`) y en la UI, con contador visible en descripción y comentario al llegar al 90 %. |

## E13 — Notificaciones

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E13-1 | Modelo y servicio de notificaciones | M | Tabla `notification` (esquema §1); se crea en la misma transacción del caso de uso; nunca notifica al autor, a no miembros ni a cuentas que no estén `ACTIVE`; `payload` con copia de los textos; referencias con `ON DELETE SET NULL` (ADR-008). |
| E13-2 | Feed y contador | M | `GET /api/notifications?unread=&page=&size=`, `GET /api/notifications/unread-count`, `PATCH /api/notifications/{id}/read`, `POST /api/notifications/read-all` y `DELETE /api/notifications/{id}`; cada usuario solo ve las suyas; por defecto el feed excluye las `INVITATION_RECEIVED` con invitación pendiente (se muestran en el bloque de invitaciones) pero `unread-count` sí las cuenta. |
| E13-3 | Entrega en tiempo real | M | `/user/queue/notifications` entrega `NotificationCreated` (notificación + contador) y `NotificationsRead` entre pestañas, después de confirmar la transacción. |
| E13-4 | Notificaciones de tablero | M | Se generan: asignación, invitación recibida, aceptada y rechazada, cambio de rol, remoción y transferencia de propiedad; `INVITATION_RECEIVED` se marca leída cuando la invitación deja de estar pendiente. (Las menciones están en E8-3.) |
| E13-5 | Recordatorios de vencimiento | M | Job diario 08:00 (`APP_TIMEZONE`) crea `DUE_SOON` (vence mañana), `DUE_TODAY` y `OVERDUE` (venció ayer) solo para tareas asignadas, con fecha, no completadas ni "al día" y de cuentas `ACTIVE`; idempotente por `dedupeKey` `<taskId>:<dueDate>`. |
| E13-6 | Resumen semanal | S | Job del lunes 08:00 crea `WEEKLY_DIGEST` con contadores (`dueThisWeek`, `overdue`, `assigned`) para cada usuario `ACTIVE` con tableros; `dedupeKey` por semana ISO; solo dentro de la app. |
| E13-7 | Retención de notificaciones | S | Job diario 03:00 UTC elimina las leídas con más de 90 días y cualquiera con más de 180. |
| E13-8 | Pantalla de Notificaciones | M | Bloque de invitaciones pendientes (Aceptar/Rechazar, expiración) + feed paginado; abrir una notificación la marca leída y navega al recurso ("Ya no está disponible" si falta); "Marcar todas como leídas"; contador en el sidebar ("Notificaciones") actualizado en vivo; descartar una notificación; tiempos relativos con el reloj del navegador (ADR-015). |

## E14 — Frontend

El stack es React + Vite + TypeScript (ADR-017). Estas historias corren en paralelo a las de backend: E14-0 a E14-5 junto con S0, E1 y E2; las pantallas (E14-10) a medida que termina la historia de backend de cada una.

| ID | Historia | Tamaño | Criterios de aceptación |
|---|---|---|---|
| E14-0 | Proyecto base del frontend | M | Repositorio o carpeta del frontend con React + Vite + TypeScript, lint, formato y pruebas; proxy de desarrollo hacia el backend (cookie de refresh con `Path=/api/auth`); variables de entorno para la URL de la API; CI que compila y prueba en cada PR. |
| E14-1 | Tokens del diseño y tipografías | S | Las variables de `diseño-interfaz.pen` (colores, espaciado, radios, fuentes) como tema; tipografías Plus Jakarta Sans (títulos) e Inter (cuerpo); solo tema claro. |
| E14-2 | Biblioteca de componentes | L | Botones, campos (con mostrar/ocultar en contraseñas), casillas, insignias, etiquetas, avatares, toasts, banners, diálogos con velo, tarjeta de tarea, columna, estados vacío/error/cargando; foco visible de 2 px siempre; estados con texto además de color. |
| E14-3 | Shell de la aplicación | M | Sidebar de 288 px (Inicio, Mis tareas, Tableros recientes, Notificaciones con contador, Cerrar sesión), barra superior con chip de conexión, engranaje de Ajustes y avatar; rutas públicas y privadas; pantalla 404; comportamiento degradado por debajo de 1280 px documentado. |
| E14-4 | Cliente HTTP y errores | M | Access token en memoria, refresh serializado, mapeo de `code` a mensajes en español, `RATE_LIMITED` con cuenta regresiva (`Retry-After`) y botón afectado deshabilitado. |
| E14-5 | Cliente STOMP y reconciliación | L | Conexión autenticada, estados EN VIVO / RECONECTANDO… / SIN CONEXIÓN (el aviso de "Sin conexión" es un banner flotante abajo), eventos idempotentes, recarga del tablero y de los contadores al reconectar. |
| E14-6 | Arrastrar y soltar | L | Tareas y columnas (arranque a 150 ms, original al 40 %, hueco de inserción, columna llena atenuada con "Columna llena (N/N)", reversión con toast ante 403/404/409). |
| E14-7 | Visibilidad por rol | M | Acciones ocultas (no deshabilitadas) según `myRole` y el asignado, con la matriz del TRD §3.2 (ADR-018); "Salir del tablero" bloqueado para el Owner con ruta a transferir; el menú ⋯ del tablero muestra "Etiquetas" a todos los roles. |
| E14-8 | Formato de fechas y textos relativos | S | Fechas `dd MMM` en español, tiempos relativos y saludo con el reloj del navegador (ADR-015); vencimientos y grupos siempre desde el servidor. |
| E14-9 | Accesibilidad | M | Botones de icono con etiqueta accesible (por ejemplo "Agregar columna"), diálogos con foco atrapado, `Esc` cierra y `Enter` confirma, contraste AA salvo excepciones documentadas. |
| E14-10 | Pantallas por épica | L | Cada pantalla de `diseño-interfaz.pen` implementada con su historia de backend: acceso, Inicio, Mis tareas, tableros, kanban, detalle de tarea, Completadas, cronograma, miembros e invitaciones, notificaciones, ajustes, errores. |
| E14-11 | Pruebas de extremo a extremo | M | Flujos críticos: registro y login, crear tablero, mover tarea, conflicto de versión, invitar y aceptar, eliminar cuenta con recuperación. |

---

## Definition of Ready (por historia)
- AC claros y verificables; dependencias identificadas; diseño disponible (pantalla en `diseño-interfaz.pen`; solo faltan por diseñar las páginas públicas de Términos y Privacidad, ver `especificaciones-interaccion.md` §18); contrato de API en `contratos-api.md`.

## Definition of Done (por historia)
- Código + tests (unitarios e integración con Testcontainers cuando aplique); migración Flyway si cambia esquema; OpenAPI actualizado; permisos por rol verificados con pruebas según la matriz del TRD §3.2; AC verificados en local; sin regresiones en CI; evento STOMP publicado después de confirmar la transacción si muta datos de tablero; notificación generada si el caso de uso la define.
