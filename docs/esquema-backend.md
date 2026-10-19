# Esquema de Backend
## Task Flow
### App colaborativa de gestión de tareas — Java 25 + Spring Boot 4.1.1

**Versión:** 1
**Fecha:** 16 Octubre 2026

---

## 1. Modelo de datos (entidades)

Basado en el diagrama de clases validado. Tipos pensados para JPA/Hibernate sobre PostgreSQL.

Convenciones: todas las claves primarias son UUID; las marcas de tiempo son `Instant` (UTC); las fechas de calendario son `LocalDate`. Los borrados en cascada se definen en la base de datos (`ON DELETE CASCADE`) además de en las relaciones JPA. Los límites de longitud de los campos de texto están en ADR-004 (`adrs.md`).

### Users
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| name | String | |
| email | String | único, guardado en minúsculas |
| passwordHash | String | bcrypt costo 12; nulo si el usuario solo usa OAuth2 Google |
| accountProvider | ENUM: GOOGLE, LOCAL | |
| googleId | String | nullable; único cuando existe |
| jobTitle | String | nullable — "título o profesión" |
| urlAvatar | String | nullable; foto de Google o avatar subido |
| emailVerifiedAt | Instant | nullable; null mientras no se verifique (LOCAL). Las cuentas Google se crean ya verificadas. La verificación no bloquea el acceso. |
| accountState | ENUM: ACTIVE, PENDING_DELETION, DELETED | |
| createdAt | Instant | |
| updatedAt | Instant | |
| deletionRequestedAt | Instant | nullable; se llena al solicitar la eliminación (`PENDING_DELETION`); el plazo para recuperar la cuenta es este valor + 30 días; se borra al recuperarla |
| deletedAt | Instant | nulo hasta la purga de la cuenta |

- Al purgar (`DELETED`) se anonimizan `name`, `email`, `googleId`, `urlAvatar` y `jobTitle`, y se anula `passwordHash`; el registro permanece para conservar los comentarios.

### EmailVerificationToken
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| userId | UUID (FK → User) | |
| tokenHash | String | SHA-256 del token; no se guarda el token en claro; único |
| expiresAt | Instant | createdAt + 24 h |
| usedAt | Instant | nullable |
| createdAt | Instant | |

- Al emitir un token nuevo (reenvío) los anteriores del usuario quedan invalidados.

### PasswordResetToken
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| userId | UUID (FK → User) | |
| tokenHash | String | SHA-256 del token; único |
| expiresAt | Instant | createdAt + 60 min |
| usedAt | Instant | nullable |
| createdAt | Instant | |

### RefreshToken
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| userId | UUID (FK → User) | |
| tokenHash | String | SHA-256; no se guarda el token en claro; único |
| expiresAt | Instant | createdAt + 7 días (configurable) |
| revokedAt | Instant | nullable; se marca al hacer logout, al cambiar la contraseña (revoca todas) o al usar el token en `refresh` (rotación de un solo uso, ADR-003) |
| replacedById | UUID (FK → RefreshToken) | nullable; se llena al rotar el token en `refresh` |
| createdAt | Instant | |

- Presentar un token ya rotado o revocado revoca todas las sesiones del usuario y responde 401 `TOKEN_ALREADY_USED`. Solicitar la eliminación de la cuenta también revoca todas las sesiones.

### Board
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| name | String | |
| description | String | |
| color | String (hex) | paleta fija de 8 colores (validada): `#4A3FD6 #2563EB #0E8F8F #2E9E5B #D98A00 #E5622B #D6336C #5B6075` |
| ownerId | UUID (FK → User) | debe coincidir con el `BoardMember` de rol OWNER |
| version | Integer | control optimista; `PUT` con versión obsoleta → 409 |
| createdAt | Instant | |
| updatedAt | Instant | solo se actualiza al editar el tablero directamente |
| lastActivityAt | Instant | toda mutación hija (tarea, columna, comentario, miembro) lo actualiza con una consulta directa que **no** incrementa `version` |

### BoardMember
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| boardId | UUID (FK → Board) | |
| userId | UUID (FK → User) | |
| role | Enum: OWNER, ADMIN, MEMBER | cambio de rol solo por el Owner |
| joinedAt | Instant | |

- Restricción única: `(boardId, userId)`.
- Índice único parcial: un solo `OWNER` por tablero (`boardId` donde `role = 'OWNER'`).
- Transferir propiedad actualiza `Board.ownerId` y ambos roles en una sola transacción.

### BoardInvitation
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| boardId | UUID (FK → Board) | |
| invitedUserId | UUID (FK → User) | usuario buscado por correo exacto |
| invitedByUserId | UUID (FK → User) | quien envía la invitación |
| status | Enum: PENDING, ACCEPTED, REJECTED, EXPIRED, CANCELED | |
| expiresAt | Instant | createdAt + 5 días; job cambia PENDING → EXPIRED |
| createdAt | Instant | |

- Índice único parcial: `(boardId, invitedUserId)` donde `status = 'PENDING'` (bloquea duplicados).
- Se puede crear una invitación nueva si la anterior está ACCEPTED, REJECTED, EXPIRED o CANCELED.
- No se invita a quien ya es miembro, a uno mismo ni a cuentas que no estén `ACTIVE`.
- Aceptar crea `BoardMember` con rol `MEMBER`; solo lo hace el invitado y solo si sigue PENDING.

### BoardColumn
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| boardId | UUID (FK → Board) | |
| name | String | |
| position | Integer | orden dentro del tablero; enteros con separación de 1 000 (ADR-001) |
| taskLimit | Integer | máximo de tareas pendientes en la columna; obligatorio, por defecto 50, `CHECK (taskLimit BETWEEN 1 AND 100)` |

- Restricción única `(boardId, position)` diferible (`DEFERRABLE INITIALLY DEFERRED`). Estrategia de orden (ADR-001): la primera columna usa 1 000, las siguientes suman 1 000 y al insertar entre vecinos se usa el punto medio; si la separación baja de 1, el servicio rebalancea todas las columnas del tablero en la misma transacción.
- Borrado en cascada de las tareas que están en la columna (y, con ellas, subtareas, comentarios y etiquetas asociadas).
- Color: no persistido; la interfaz lo deriva por posición.
- Al crear el tablero con `createDefaultColumns = true` se generan 4 columnas: Backlog, Por hacer, En curso, Hecho, cada una con `taskLimit = 50`.
- Máximo 12 columnas por tablero (validado en servicio; 409 `BOARD_COLUMNS_LIMIT_REACHED`).
- `taskLimit` no puede fijarse por debajo del número de tareas pendientes que la columna tiene (409 `COLUMN_LIMIT_BELOW_CURRENT`). El conteo solo incluye tareas con `isDone = false`.
- Crear, mover o reabrir una tarea hacia una columna llena responde 409 `COLUMN_LIMIT_REACHED`. La validación bloquea la fila de la columna destino (`SELECT ... FOR UPDATE`, `@Lock(PESSIMISTIC_WRITE)`) dentro de la transacción para evitar que dos movimientos simultáneos superen el límite.

### Task
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| boardId | UUID (FK → Board) | siempre presente, incluso si la tarea está completada |
| columnId | UUID (FK → BoardColumn) | nullable; nulo cuando la tarea está completada |
| assigneeId | UUID (FK → User) | nullable; debe ser miembro del tablero |
| title | String | |
| description | String | |
| isDone | Boolean | default false |
| completedAt | Instant | nullable; se llena al completar |
| startDate | LocalDate | nullable; `startDate <= dueDate` |
| dueDate | LocalDate | nullable |
| priority | Enum: LOW, MEDIUM, HIGH, URGENT | default MEDIUM |
| position | Integer | nullable; orden dentro de la columna con la misma estrategia que las columnas (ADR-001); nulo si está completada |
| version | Integer | control optimista; `PUT` con versión obsoleta → 409 |
| createdAt / updatedAt | Instant | |

- Restricción de consistencia: si `isDone = false` → `columnId` y `position` no nulos; si `isDone = true` → `columnId` y `position` nulos y `completedAt` no nulo.
- Restricción única `(columnId, position)` diferible (los nulos no cuentan).
- `version` solo se incrementa con `PUT`. Los campos `columnId`, `position`, `assigneeId`, `isDone` y `completedAt` se excluyen del bloqueo optimista (`@OptimisticLock(excluded = true)`) para que mover, asignar, completar o reabrir no provoquen 409 en quien edita el formulario.
- Máximo 3 etiquetas por tarea (validado en servicio, bloqueando la fila de la tarea para evitar carreras).

### Subtask
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| taskId | UUID (FK → Task) | |
| title | String | |
| isDone | Boolean | default false |
| position | Integer | orden dentro de la tarea |

- Restricción única `(taskId, position)` diferible. Las subtareas nuevas se agregan al final (`max + 1 000`); reordenarlas queda fuera de la v1.
- Máximo 30 subtareas por tarea (validado en servicio bloqueando la fila de la tarea; 409 `SUBTASKS_LIMIT_REACHED`).

### Comment
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| taskId | UUID (FK → Task) | |
| authorId | UUID (FK → User) | sin borrado en cascada: al anonimizar un usuario sus comentarios se conservan |
| content | String | máximo 2 000 caracteres de texto visible (cada mención cuenta como `@Nombre`); las menciones se guardan como `@[Nombre](userId)` |
| createdAt / updatedAt | Instant | |

### CommentMention
| Campo | Tipo | Notas |
|---|---|---|
| commentId | UUID (FK → Comment) | |
| mentionedUserId | UUID (FK → User) | debe ser miembro del tablero al momento de escribir |

PK compuesta `(commentId, mentionedUserId)`. El servicio extrae las menciones del contenido al crear o editar; al editar solo las menciones nuevas generan notificación.

### Tag (etiqueta o label)
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| boardId | UUID (FK → Board) | |
| name | String | único por tablero sin distinguir mayúsculas: `(boardId, lower(name))` |
| color | String (hex) | paleta fija de 6 acentos (validada): `#3B30B0 #1B4DB0 #0B6663 #1A6B3F #8A5200 #A3214F`; el fondo de la etiqueta lo deriva la interfaz |

### TaskTag (tabla intermedia)
| Campo | Tipo | Notas |
|---|---|---|
| taskId | UUID (FK → Task) | |
| tagId | UUID (FK → Tag) | |

PK compuesta `(taskId, tagId)`. Al eliminar un tag, sus filas se eliminan en cascada. El servicio valida que la etiqueta pertenezca al mismo tablero que la tarea.

### Notification
| Campo | Tipo | Notas |
|---|---|---|
| id | UUID (PK) | |
| userId | UUID (FK → User) | destinatario; borrado en cascada |
| type | ENUM | ver lista abajo |
| actorId | UUID (FK → User) | nullable; quien provocó la notificación (`ON DELETE SET NULL`) |
| boardId | UUID (FK → Board) | nullable (`ON DELETE SET NULL`) |
| taskId | UUID (FK → Task) | nullable (`ON DELETE SET NULL`) |
| commentId | UUID (FK → Comment) | nullable (`ON DELETE SET NULL`) |
| invitationId | UUID (FK → BoardInvitation) | nullable (`ON DELETE SET NULL`) |
| payload | JSONB | copia de los datos mostrables (título de la tarea, nombre del tablero, contadores del resumen) para que la notificación siga siendo legible si el origen se elimina |
| dedupeKey | String | nullable; evita duplicar recordatorios y resúmenes |
| readAt | Instant | nullable |
| createdAt | Instant | |

**Tipos (`type`)**: `TASK_ASSIGNED`, `MENTION`, `INVITATION_RECEIVED`, `INVITATION_ACCEPTED`, `INVITATION_REJECTED`, `ROLE_CHANGED`, `REMOVED_FROM_BOARD`, `OWNERSHIP_TRANSFERRED`, `DUE_SOON` (vence mañana), `DUE_TODAY`, `OVERDUE` (venció ayer), `WEEKLY_DIGEST`.

- Índice único parcial: `(userId, type, dedupeKey)` donde `dedupeKey IS NOT NULL`.
- `dedupeKey` de recordatorios: `<taskId>:<dueDate>` (si cambia la fecha límite vuelve a poder notificar). De `WEEKLY_DIGEST`: semana ISO, por ejemplo `2026-W43`.
- Reglas de generación: nunca se notifica al propio actor; las asignaciones a uno mismo no notifican; solo a miembros vigentes con cuenta `ACTIVE` (no a cuentas en eliminación); los recordatorios omiten tareas completadas o "al día".
- `INVITATION_RECEIVED` se marca como leída automáticamente cuando la invitación deja de estar PENDING (aceptada, rechazada, cancelada o expirada).
- Las notificaciones se crean en la misma transacción del caso de uso y se entregan por WebSocket después de confirmar.

## 2. Estructura de paquetes propuesta

```
com.taskflow
├── config/            # SecurityConfig, WebSocketConfig, OpenApiConfig, MailConfig, SchedulingConfig, CorsConfig
├── security/          # JwtService, JwtAuthFilter, OAuth2SuccessHandler, permisos por rol, rate limiting
├── user/              # User entity, repository, service, controller (perfil, avatar, ciclo de vida, tokens, AccountPurgeJob)
├── board/             # Board, BoardMember, BoardInvitation (InvitationExpirationJob)
├── column/            # BoardColumn
├── task/              # Task
├── subtask/           # Subtask
├── comment/           # Comment, CommentMention
├── tag/               # Tag, TaskTag
├── notification/      # Notification, NotificationService, controlador, jobs de recordatorios, resumen semanal y limpieza
├── realtime/          # Handlers STOMP, publicación de eventos por tablero y por usuario, registro de suscripciones
├── mail/              # servicios de correo (verificación, restablecimiento, aviso de invitación, aviso de eliminación de cuenta)
├── storage/           # almacenamiento de avatares (interfaz + implementación local)
├── dashboard/         # resumen del Inicio, Mis tareas y cronograma
├── common/            # excepciones, DTOs base, mapeadores, auditoría, catálogo de códigos de error
└── TaskFlowAppApplication.java
```

Cada módulo sigue el patrón `Controller → Service → Repository`, con DTOs de entrada/salida
separados de las entidades JPA.

## 3. Endpoints REST

Todos los endpoints usan el prefijo `/api`. Las formas de petición y respuesta, los ejemplos y los payloads de eventos están en `contratos-api.md`.

| Recurso | Endpoints |
|---|---|
| Auth | `POST /api/auth/register` · `POST /api/auth/verify-email` · `POST /api/auth/verify-email/resend` · `POST /api/auth/login` · `POST /api/auth/refresh` · `POST /api/auth/logout` · `POST /api/auth/forgot-password` · `POST /api/auth/reset-password` · `GET /oauth2/authorization/google` |
| Users | `GET /api/users/me` · `PUT /api/users/me` · `PUT /api/users/me/password` · `POST /api/users/me/avatar` (multipart) · `DELETE /api/users/me/avatar` · `GET /api/files/avatars/{file}` (público; nombre no adivinable) · `DELETE /api/users/me` (solicita eliminación y revoca todas las sesiones) · `POST /api/users/me/restore` (recupera la cuenta dentro de los 30 días; solo con sesión de recuperación) · `GET /api/users/me/deletion-blockers` (tableros propios que impiden eliminar) · `GET /api/users/lookup?email=&boardId=` (búsqueda exacta con rate limit; con `boardId` devuelve `FOUND`, `NOT_FOUND`, `ALREADY_MEMBER` o `ALREADY_INVITED`) |
| Boards | `GET /api/boards?role=owner\|member` (incluye `myRole` y `taskCount`) · `POST /api/boards` (`createDefaultColumns`, etiquetas iniciales e invitaciones iniciales opcionales; devuelve el resultado por correo: `INVITED` o `SKIPPED` con motivo `USER_NOT_FOUND`, `SELF` o `DUPLICATE`) · `GET /api/boards/{id}` (tablero con miembros, columnas, etiquetas y tareas no completadas con resumen) · `PUT /api/boards/{id}` (envía `version`; solo Owner) · `DELETE /api/boards/{id}` (solo Owner) · `POST /api/boards/{id}/transfer` (`newOwnerUserId`) · `DELETE /api/boards/{id}/members/me` (salir) · `GET /api/boards/{id}/search?q=` · `GET /api/boards/{id}/completed-tasks?page=&size=` · `GET /api/boards/{id}/timeline?from=&to=` |
| Members | `GET /api/boards/{id}/members` · `PATCH /api/boards/{id}/members/{userId}` (cambio de rol, solo Owner) · `DELETE /api/boards/{id}/members/{userId}` (Admin solo a `MEMBER`) |
| Invitations | `POST /api/boards/{id}/invitations` · `GET /api/boards/{id}/invitations` (pendientes) · `DELETE /api/invitations/{id}` (cancelar; Owner/Admin) · `POST /api/invitations/{id}/accept` · `POST /api/invitations/{id}/reject` · `GET /api/users/me/invitations` |
| Columns | `POST /api/boards/{id}/columns` (acepta `taskLimit`, por defecto 50) · `PUT/DELETE /api/columns/{id}` (`PUT` acepta `taskLimit`) · `PATCH /api/columns/{id}/position` |
| Tasks | `POST /api/columns/{id}/tasks` · `GET /api/tasks?assigneeId=me\|<id>&boardId=&priority=&isDone=&dueFrom=&dueTo=&q=&sort=&page=&size=` · `GET/PUT/DELETE /api/tasks/{id}` (el detalle incluye subtareas y etiquetas; `PUT` envía `version` y `tagIds` y no modifica el asignado; conflicto → 409 con la versión y el estado actuales) · `PATCH /api/tasks/{id}/move` (`columnId` + `position`) · `PATCH /api/tasks/{id}/assignee` (`assigneeId` o `null`) · `POST /api/tasks/{id}/complete` · `POST /api/tasks/{id}/reopen` (`columnId` + `position` elegidos por el usuario) |
| Subtasks | `POST /api/tasks/{id}/subtasks` · `PUT/DELETE /api/subtasks/{id}` |
| Comments | `GET /api/tasks/{id}/comments?page=&size=` · `POST /api/tasks/{id}/comments` · `PUT/DELETE /api/comments/{id}` |
| Tags | `POST /api/boards/{id}/tags` · `GET /api/boards/{id}/tags` (incluye `taskCount`) · `PUT/DELETE /api/tags/{id}` |
| Notifications | `GET /api/notifications?unread=&page=&size=` · `GET /api/notifications/unread-count` · `PATCH /api/notifications/{id}/read` · `POST /api/notifications/read-all` · `DELETE /api/notifications/{id}` |
| Dashboard | `GET /api/dashboard/summary` · `GET /api/dashboard/calendar?month=` · `GET /api/me/counters` |

**`GET /api/dashboard/summary`** devuelve lo mínimo del Inicio: `today`, las tareas asignadas pendientes, las que vencen hoy y las próximas tareas (con `bucket`). El calendario del mes sale de `GET /api/dashboard/calendar?month=`, los tableros recientes de `GET /api/boards?sort=lastActivityAt,desc&size=4` y los contadores del sidebar (`openAssigned`, `unreadNotifications`) de `GET /api/me/counters`; la forma exacta está en `contratos-api.md`. Todas las cifras excluyen tareas completadas, y los cálculos de "hoy" y "esta semana" (lunes a domingo) usan `APP_TIMEZONE`. Del mismo modo, `GET /api/tasks` devuelve en cada tarea el grupo (`bucket`) calculado por el servidor; con `sort=dueDate` las tareas sin fecha límite quedan al final (nulos al final, luego por prioridad).

**Convenciones:**
- Prefijo `/api` en todos los endpoints.
- Errores: RFC 7807 con campo `code` (catálogo en la sección 10); la interfaz traduce el `code` y `detail` trae un texto de respaldo en español.
- Paginación: `page`, `size`, `sort`.
- Fechas: ISO-8601 (`Instant` en UTC; `LocalDate` para fechas de calendario).
- Rate limits: ver sección 5.

Al invitar se envía un correo de aviso al invitado; la invitación se acepta o rechaza **solo dentro de la app** (bandeja de invitaciones dentro de Notificaciones).

Toda mutación aplica los permisos por rol definidos en el TRD (sección 3.2), verificados en
la capa de servicio (ej. vía `@PreAuthorize` con un `PermissionEvaluator` custom por tablero). Cuando un Miembro intenta modificar campos que no le corresponden, el servicio responde 403 `TASK_FIELD_FORBIDDEN`.

**Reglas por operación:**
- **Completar** (`complete`): pone `isDone = true`, llena `completedAt` y deja `columnId` y `position` en nulo (las posiciones restantes de la columna no se renumeran).
- **Reabrir** (`reopen`): exige `columnId` (columna del mismo tablero) y `position`; pone `isDone = false` y limpia `completedAt`.
- **Posición en las peticiones**: en `move`, `reopen` y `PATCH /api/columns/{id}/position`, `position` es el índice destino (0 = primero). El servidor calcula el valor almacenado según ADR-001 y publica en el evento el orden final (`order[]`).
- **Límites** (valores configurables en la aplicación): 12 columnas por tablero, 1 a 100 tareas por columna (por defecto 50) y 30 subtareas por tarea. Aplican al crear columnas, crear tareas, mover tareas (`move`), reabrir tareas (`reopen`), cambiar `taskLimit` y crear subtareas.
- **Quitar o salir de un tablero**: las tareas asignadas al usuario quedan con `assigneeId = null` (se emite `TaskAssigneeChanged` por cada una) y se conservan sus comentarios.
- **Eliminar cuenta**: ver TRD 3.11. El bloqueo responde 409 `ACCOUNT_DELETE_BLOCKED`; si no hay bloqueo, la cuenta pasa a `PENDING_DELETION`, se guarda `deletionRequestedAt`, se revocan todas las sesiones y se envía el correo de aviso con la fecha límite de recuperación.
- **Recuperar cuenta**: `restore` solo funciona con una sesión de recuperación y antes de `deletionRequestedAt + 30 días`; después responde 409 `RECOVERY_PERIOD_EXPIRED`. Tras recuperarla, el cliente llama a `POST /api/auth/refresh` para obtener una sesión normal.

## 4. Tiempo real (WebSocket + STOMP)

- Endpoint de conexión: `/ws` (con SockJS como fallback opcional).
- Topic por tablero: `/topic/boards/{boardId}` — todo cliente suscrito recibe los eventos
  de ese tablero.
- Cola personal: `/user/queue/notifications` — notificaciones del usuario. El `Principal` de la sesión es el `userId`, de modo que el envío se hace con `convertAndSendToUser(userId, "/queue/notifications", ...)`.
- **Catálogo de eventos v1 (por tablero)**: `BoardUpdated`, `BoardDeleted`, `ColumnCreated/Updated/Deleted/Reordered`, `TaskCreated/Updated/Deleted/Moved/Completed/Pending/AssigneeChanged`, `SubtaskCreated/Updated/Deleted`, `CommentCreated/Updated/Deleted`, `TagCreated/Updated/Deleted`, `TaskTagChanged`, `MemberAdded/RoleChanged/Removed/Left`, `InvitationCreated/Accepted/Rejected/Canceled/Expired`, `OwnershipTransferred`.
- **Eventos de la cola personal**: `NotificationCreated` (incluye la notificación y el contador de no leídas) y `NotificationsRead` (mantiene sincronizadas varias pestañas con el nuevo contador).
- **Formato común de evento**:

```json
{ "eventId": "uuid", "type": "TaskMoved", "boardId": "uuid", "entityId": "uuid",
  "actorId": "uuid", "occurredAt": "2026-10-16T14:00:00Z", "payload": { } }
```

- Flujo: el cliente hace la mutación vía REST → el servicio persiste el cambio y registra un evento de dominio → el evento se publica con `SimpMessagingTemplate` **después de confirmar la transacción** (`@TransactionalEventListener(phase = AFTER_COMMIT)`), tanto al topic del tablero como, cuando corresponde, a la cola personal de los destinatarios.
- Autenticación del handshake STOMP: se reutiliza el JWT (interceptor en el `CONNECT` frame); se rechaza si el token es de recuperación (cuenta en eliminación).
- Autorización: al suscribirse a `/topic/boards/{boardId}`, se valida que el usuario sea
  miembro del tablero antes de aceptar la suscripción.
- Cierre de suscripciones: el servidor mantiene un registro de suscripciones por tablero y usuario. Cuando un usuario es removido, sale del tablero o el tablero se elimina, se envía el evento correspondiente y se deja de reenviarle mensajes de ese topic (interceptor de salida); el cliente además se desuscribe.
- Reconexión: el broker no reenvía eventos perdidos. Al pasar de RECONECTANDO a EN VIVO el cliente recarga el estado (`GET /api/boards/{id}` y el contador de notificaciones).
- La interfaz representa el estado de la conexión (EN VIVO / RECONECTANDO… / SIN CONEXIÓN).

## 5. Seguridad

- **JWT propio**: access token de 15 minutos + refresh token de 7 días (ambos configurables). `JwtAuthFilter` valida el
  token en cada request REST y en el handshake WebSocket. `POST /api/auth/refresh` renueva y **rota** el refresh token; los refresh tokens se persisten en `refresh_token` y son revocables: `POST /api/auth/logout` revoca la sesión actual y el cambio de contraseña revoca todas las sesiones. Presentar un refresh token ya rotado o revocado revoca todas las sesiones del usuario (error `TOKEN_ALREADY_USED`).
- **Entrega de tokens**: el refresh token viaja en una cookie `HttpOnly`, `Secure` y con `SameSite`, acotada a la ruta `/api/auth`; el access token lo guarda el cliente en memoria. CORS permite solo el origen definido en `FRONTEND_URL`, con credenciales.
- **Verificación de correo** (LOCAL): token de 24 h por SMTP; reenvío disponible. No limita el acceso: el estado se muestra en Ajustes > Cuenta (con botón "Verificar correo" cuando falte).
- **Restablecimiento de contraseña**: token de 60 min; la solicitud responde igual exista o no la cuenta. Las cuentas en `PENDING_DELETION` pueden usarlo para poder recuperarlas.
- **Sesión de recuperación**: cuando una cuenta `PENDING_DELETION` se autentica (login LOCAL, Google o `refresh`), el access token incluye el claim `recovery = true` y el login responde con `accountState = PENDING_DELETION` y la fecha límite de recuperación. `JwtAuthFilter` solo permite con ese token `GET /api/users/me`, `POST /api/users/me/restore`, `POST /api/auth/refresh` y `POST /api/auth/logout`; todo lo demás responde 403 `ACCOUNT_PENDING_DELETION`. Una cuenta `DELETED` no puede autenticarse.
- **Política de contraseña**: mínimo 8 caracteres con al menos un número y máximo 72 bytes (límite de bcrypt); bcrypt con costo 12.
- **OAuth2 Google**: flujo de autorización estándar de Spring Security OAuth2 Client;
  al primer login se crea/vincula el `User` por `googleId`/email. Al terminar, `OAuth2SuccessHandler` deja la cookie de refresh y redirige a `FRONTEND_URL`, donde el cliente llama a `POST /api/auth/refresh` para obtener el access token. Si el correo ya existe con otro proveedor, el login responde con el error "esta cuenta está registrada con otro proveedor" (`ACCOUNT_PROVIDER_MISMATCH`).
- **Autorización por rol de tablero**: no se usan roles globales de Spring Security, sino
  un chequeo contextual (¿es el usuario OWNER/ADMIN/MEMBER de *este* tablero?) resuelto
  contra `BoardMember` en cada operación.
- **Rate limiting** (Bucket4j, en memoria mientras haya un solo nodo):

| Operación | Límite |
|---|---|
| Login | 5 por minuto por IP + endpoint |
| Envío de correos (reenvío de verificación y "olvidé mi contraseña") | 3 por cada 10 minutos por IP + endpoint |
| `GET /api/users/lookup` | 10 por minuto por usuario autenticado |

La respuesta al superar un límite es 429 `RATE_LIMITED` con `Retry-After` (ADR-002).

- **Avatares**: se validan tipo (PNG/JPG/WebP) y tamaño (máx. 2 MB) y se renombran con un identificador propio.

## 6. Trabajos programados

Todos usan `@Scheduled` (ADR-005), deben ser idempotentes, no solaparse y asumen un solo nodo (si el backend escala se requiere un bloqueo de jobs, por ejemplo ShedLock). Los de mantenimiento corren a las 03:00 UTC (el de invitaciones, cada hora); los que dependen del día local (recordatorios y resumen semanal) usan `APP_TIMEZONE`.

| Job | Frecuencia | Qué hace |
|---|---|---|
| Expiración de invitaciones | cada hora | `PENDING` con `expiresAt` vencido → `EXPIRED`; emite `InvitationExpired` y marca como leída su notificación |
| Purga de cuentas | diario, 03:00 UTC | cuentas `PENDING_DELETION` con `deletionRequestedAt` de hace más de 30 días → `DELETED` con limpieza y anonimización (TRD 3.11) |
| Recordatorios de vencimiento | diario, 08:00 (`APP_TIMEZONE`) | crea `DUE_SOON` (vence mañana), `DUE_TODAY` y `OVERDUE` (venció ayer) para tareas asignadas a usuarios `ACTIVE`, no completadas ni "al día" |
| Resumen semanal | lunes, 08:00 (`APP_TIMEZONE`) | crea `WEEKLY_DIGEST` con contadores (vencen esta semana, vencidas, asignadas) para cada usuario `ACTIVE` que pertenezca a algún tablero |
| Limpieza de notificaciones | diario, 03:00 UTC | elimina notificaciones leídas con más de 90 días y cualquiera con más de 180 |
| Limpieza de tokens | diario, 03:00 UTC | elimina tokens de verificación y restablecimiento vencidos o usados, y refresh tokens vencidos o revocados con más de 30 días |

## 7. Migraciones y testing

- **Flyway**: cada cambio de esquema como script versionado (`V1__init.sql`, `V2__...sql`). La primera migración crea la extensión `pg_trgm`, todas las tablas de este documento (incluidas `email_verification_token`, `password_reset_token`, `refresh_token`, `comment_mention` y `notification`), las restricciones y los índices de la sección 9.
- **Testing**: JUnit 5 + Testcontainers (PostgreSQL real en tests de integración),
  Spring Security Test para endpoints protegidos, pruebas del flujo STOMP con clientes
  WebSocket de prueba, pruebas del flujo de conflicto (409) de tareas y tablero, de la matriz de permisos por rol, de completar/reabrir tareas, de los límites de columnas, tareas y subtareas (incluida la carrera entre dos movimientos simultáneos hacia una columna casi llena), y de los jobs (recordatorios idempotentes, expiración y purga).

## 8. Docker / entorno local

```yaml
# docker-compose.yml (esquema)
services:
  postgres:
    image: postgres:16
    environment: [POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD]
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      retries: 10
  mailpit:
    image: axllent/mailpit
    ports: ["1025:1025", "8025:8025"]
  backend:
    build: .
    depends_on:
      postgres: { condition: service_healthy }
      mailpit: { condition: service_started }
    ports: ["8080:8080"]
    volumes: ["avatars:/data/avatars"]
    environment:
      - SPRING_DATASOURCE_URL
      - JWT_SECRET
      - JWT_ACCESS_TTL
      - JWT_REFRESH_TTL
      - GOOGLE_CLIENT_ID
      - GOOGLE_CLIENT_SECRET
      - MAIL_HOST
      - MAIL_PORT
      - MAIL_FROM
      - FRONTEND_URL
      - APP_TIMEZONE
      - AVATAR_STORAGE_PATH
volumes:
  pgdata:
  avatars:
```

El `Dockerfile` del backend usa una imagen base de Java 25. El pipeline de CI (ver TRD, sección 7.4) construye la imagen del `backend` a partir del
`Dockerfile` del proyecto y corre los tests de integración contra el `postgres` del compose. El despliegue queda fuera de la v1.

## 9. Índices y restricciones recomendados

| Tabla | Índice / restricción | Para qué |
|---|---|---|
| users | único `email`; único `googleId` (no nulo) | login y vinculación |
| board_member | único `(boardId, userId)`; único parcial `boardId` donde `role = 'OWNER'`; índice `(userId)` | permisos y "mis tableros" |
| board_invitation | único parcial `(boardId, invitedUserId)` donde `status = 'PENDING'`; índice `(invitedUserId, status)` | duplicados y bandeja |
| board_column | único diferible `(boardId, position)`; `CHECK (taskLimit BETWEEN 1 AND 100)` | orden y límite de tareas |
| task | índice `(boardId)`; único diferible `(columnId, position)`; índice `(assigneeId, dueDate)`; índice `(boardId, completedAt)` donde `isDone = true` | Mis tareas, resumen, completadas |
| subtask | único diferible `(taskId, position)` | orden |
| comment | índice `(taskId, createdAt)` | listado paginado |
| tag | único `(boardId, lower(name))` | nombres únicos |
| notification | índice `(userId, readAt, createdAt DESC)`; único parcial `(userId, type, dedupeKey)` | feed, contador y deduplicación |
| búsqueda | índices GIN `pg_trgm` sobre `task.title`, `task.description`, `comment.content` y `tag.name` | búsqueda por coincidencia parcial |

La búsqueda (`GET /api/boards/{id}/search`) exige al menos 2 caracteres, se limita a 20 resultados por tipo y responde `{ tasks, tags, comments }`, cada uno con los datos mínimos para mostrarlo en el desplegable.

## 10. Catálogo de códigos de error

Formato RFC 7807 con el campo `code`. La interfaz traduce el `code`.

| code | HTTP | Cuándo |
|---|---|---|
| `VALIDATION_FAILED` | 400 | datos inválidos (incluye política de contraseña) |
| `DATE_RANGE_INVALID` | 400 | `startDate` posterior a `dueDate` |
| `TAG_LIMIT_EXCEEDED` | 400 | más de 3 etiquetas en una tarea |
| `ASSIGNEE_NOT_MEMBER` | 400 | el asignado no es miembro del tablero |
| `TRANSFER_TARGET_INVALID` | 400 | el nuevo Owner no es miembro activo |
| `INVITATION_SELF` | 400 | invitarse a uno mismo |
| `AVATAR_INVALID` | 400 | tipo o tamaño de imagen no permitido |
| `CURRENT_PASSWORD_INCORRECT` | 400 | la contraseña actual no coincide al cambiarla |
| `INVALID_CREDENTIALS` | 401 | correo o contraseña incorrectos |
| `UNAUTHENTICATED` | 401 | falta o expiró el access token |
| `TOKEN_ALREADY_USED` | 401 | refresh token ya rotado o revocado; se revocan todas las sesiones del usuario |
| `TOKEN_INVALID` / `TOKEN_EXPIRED` | 400 | token de verificación o restablecimiento inválido o vencido |
| `FORBIDDEN` | 403 | sin permiso por rol |
| `TASK_FIELD_FORBIDDEN` | 403 | un Miembro intenta modificar campos no permitidos |
| `ACCOUNT_PENDING_DELETION` | 403 | sesión de recuperación usada en un endpoint no permitido |
| `RESOURCE_NOT_FOUND` | 404 | recurso inexistente o sin acceso |
| `USER_NOT_FOUND` | 404 | correo no registrado |
| `EMAIL_ALREADY_REGISTERED` | 409 | registro con un correo existente |
| `ACCOUNT_PROVIDER_MISMATCH` | 409 | cuenta registrada con otro proveedor (incluye `provider`) |
| `TASK_VERSION_CONFLICT` | 409 | `PUT` de tarea con versión obsoleta (incluye versión y estado actuales) |
| `BOARD_VERSION_CONFLICT` | 409 | `PUT` de tablero con versión obsoleta |
| `TASK_ALREADY_COMPLETED` / `TASK_NOT_COMPLETED` | 409 | completar una tarea ya completada / reabrir una pendiente |
| `INVITATION_DUPLICATE` | 409 | ya existe una invitación pendiente |
| `ALREADY_MEMBER` | 409 | el usuario ya es miembro |
| `INVITATION_NOT_PENDING` | 409 | aceptar, rechazar o cancelar una invitación que ya no está pendiente |
| `INVITATION_EXPIRED` | 409 | la invitación venció (aunque el job aún no la haya marcado `EXPIRED`) |
| `TAG_DUPLICATE` | 409 | nombre de etiqueta repetido en el tablero |
| `OWNER_MUST_TRANSFER` | 409 | el Owner intenta salir sin transferir |
| `OWNER_CANNOT_BE_REMOVED` | 409 | intento de eliminar al Owner o cambiar su rol |
| `COLUMN_LIMIT_REACHED` | 409 | crear, mover o reabrir una tarea hacia una columna llena |
| `COLUMN_LIMIT_BELOW_CURRENT` | 409 | fijar `taskLimit` por debajo de las tareas que la columna ya tiene |
| `BOARD_COLUMNS_LIMIT_REACHED` | 409 | el tablero ya tiene 12 columnas |
| `SUBTASKS_LIMIT_REACHED` | 409 | la tarea ya tiene 30 subtareas |
| `ACCOUNT_DELETE_BLOCKED` | 409 | la cuenta es Owner de tableros con otros miembros |
| `RECOVERY_PERIOD_EXPIRED` | 409 | intento de recuperar la cuenta pasados los 30 días |
| `RATE_LIMITED` | 429 | límite de frecuencia superado |
| `BOARD_LOAD_FAILED` | 500 | error al cargar el tablero |
