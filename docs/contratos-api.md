# Contratos de API — Task Flow

**Versión:** 1
**Fecha:** 16 Octubre 2026 · Complemento de `trd.md` y `esquema-backend.md`. Define formas de petición/respuesta, catálogo de errores y payloads de eventos en tiempo real. Las reglas de negocio y permisos están en el TRD; las entidades, endpoints y restricciones, en el esquema de backend.

## 1. Convenciones generales

- Base: `https://{host}/api`. Autenticación: `Authorization: Bearer <accessToken>` (salvo auth pública y lectura de avatares).
- **Tokens**: el access token (15 min) se devuelve en el cuerpo y el cliente lo guarda en memoria. El **refresh token nunca viaja en el cuerpo**: va en una cookie `HttpOnly; Secure; SameSite=Lax; Path=/api/auth` que el servidor define en login/refresh y borra en logout. CORS permite solo el origen `FRONTEND_URL` con credenciales (`credentials: 'include'` en las llamadas a `/api/auth/*`).
- IDs: UUID v4 en string. Fechas de calendario: `YYYY-MM-DD` (LocalDate). Marcas de tiempo: ISO-8601 UTC.
- "Hoy" y "esta semana" (lunes a domingo) los calcula siempre el servidor con la zona `APP_TIMEZONE`; el cliente no hace aritmética de fechas para agrupar. Las respuestas que lo necesitan (detalle de tablero, cronograma y resumen del Inicio) incluyen `today`, la fecha actual de la aplicación, para pintar vencimientos y la línea de HOY.
- **Orden**: `position` en las respuestas es el valor interno de orden (enteros con separación de 1 000, ADR-001); el cliente ordena por él y, tras un evento de movimiento, se reconcilia con `order[]`. En las peticiones (`move`, `reopen`, `PATCH .../position`) `position` es el **índice destino** (0 = primero) y el servidor calcula el valor almacenado.
- JSON en `UTF-8`; `Content-Type: application/json`, excepto la subida de avatar (`multipart/form-data`).
- Paginación: `?page=0&size=20&sort=campo,asc|desc`. Respuesta paginada:
```json
{ "items": [ ... ], "page": 0, "size": 20, "total": 42, "totalPages": 3 }
```
- Errores (RFC 7807 + `code`):
```json
{ "type": "about:blank", "title": "Conflict", "status": 409,
  "detail": "La tarea cambió mientras la editabas",
  "code": "TASK_VERSION_CONFLICT", "errors": [] }
```
- `errors[]` se usa para validación: `{ "field": "title", "message": "requerido" }`. `detail` es un texto de respaldo en español; la interfaz traduce a partir de `code`. Algunos errores añaden campos propios (ver sección 2).
- **Quien no es miembro de un tablero recibe 404 `RESOURCE_NOT_FOUND`**, no 403, para no revelar si el recurso existe.
- Una **sesión de recuperación** (cuenta en eliminación) solo puede llamar a `GET /api/users/me`, `POST /api/users/me/restore`, `POST /api/auth/refresh` y `POST /api/auth/logout`; el resto responde 403 `ACCOUNT_PENDING_DELETION`.

## 2. Catálogo de códigos de error

Este catálogo es el mismo del esquema de backend (sección 10), con los campos adicionales que devuelve cada error.

| Código | HTTP | Cuándo | Campos extra |
|---|---|---|---|
| `VALIDATION_FAILED` | 400 | Campos inválidos o faltantes (incluye política de contraseña, contenido de comentario > 2 000 caracteres, búsqueda < 2 caracteres) | `errors[]` |
| `DATE_RANGE_INVALID` | 400 | `startDate > dueDate` | |
| `TAG_LIMIT_EXCEEDED` | 400 | Más de 3 etiquetas en una tarea | |
| `ASSIGNEE_NOT_MEMBER` | 400 | Asignado fuera del tablero | |
| `TRANSFER_TARGET_INVALID` | 400 | El nuevo Owner no es miembro activo | |
| `INVITATION_SELF` | 400 | Invitarse a uno mismo | |
| `AVATAR_INVALID` | 400 | Tipo o tamaño de imagen no permitido | |
| `CURRENT_PASSWORD_INCORRECT` | 400 | La contraseña actual no coincide | |
| `TOKEN_INVALID` / `TOKEN_EXPIRED` | 400 | Token de verificación o restablecimiento inválido (incluye ya usado) o vencido | |
| `INVALID_CREDENTIALS` | 401 | Correo/contraseña incorrectos | |
| `UNAUTHENTICATED` | 401 | Falta, venció o es inválido el access token o el refresh token | |
| `TOKEN_ALREADY_USED` | 401 | Refresh token ya rotado o revocado; se revocan todas las sesiones del usuario | |
| `FORBIDDEN` | 403 | Permiso insuficiente por rol | |
| `TASK_FIELD_FORBIDDEN` | 403 | Un Miembro intenta modificar campos no permitidos | `fields[]` |
| `ACCOUNT_PENDING_DELETION` | 403 | Sesión de recuperación usada en un endpoint no permitido | |
| `RESOURCE_NOT_FOUND` | 404 | Recurso inexistente o sin acceso | `resource` (`BOARD`, `COLUMN`, `TASK`, `SUBTASK`, `COMMENT`, `TAG`, `MEMBER`, `INVITATION`) |
| `USER_NOT_FOUND` | 404 | Correo no registrado al invitar (el lookup responde 200 con `status`) | |
| `EMAIL_ALREADY_REGISTERED` | 409 | Registro o cambio de correo con un correo existente | |
| `ACCOUNT_PROVIDER_MISMATCH` | 409 | Cuenta registrada con otro proveedor | `provider` |
| `TASK_VERSION_CONFLICT` | 409 | `PUT` de tarea con versión obsoleta | `currentVersion`, `current` (TaskDetailDto) |
| `BOARD_VERSION_CONFLICT` | 409 | `PUT` de tablero con versión obsoleta | `currentVersion`, `current` (BoardSummary) |
| `TASK_ALREADY_COMPLETED` / `TASK_NOT_COMPLETED` | 409 | Completar o mover una tarea ya completada / reabrir una pendiente | |
| `INVITATION_DUPLICATE` | 409 | Ya existe una invitación pendiente | |
| `ALREADY_MEMBER` | 409 | El usuario ya es miembro | |
| `INVITATION_NOT_PENDING` | 409 | Aceptar, rechazar o cancelar una invitación ya resuelta | |
| `INVITATION_EXPIRED` | 409 | La invitación venció (aunque el job aún no la marcara `EXPIRED`) | |
| `TAG_DUPLICATE` | 409 | Nombre de etiqueta repetido en el tablero | |
| `OWNER_MUST_TRANSFER` | 409 | El Owner intenta salir sin transferir | |
| `OWNER_CANNOT_BE_REMOVED` | 409 | Intento de eliminar al Owner o cambiar su rol | |
| `ACCOUNT_DELETE_BLOCKED` | 409 | Owner de tableros con otros miembros | `blockingBoards[]` |
| `RECOVERY_PERIOD_EXPIRED` | 409 | Recuperar la cuenta pasados los 30 días | |
| `COLUMN_LIMIT_REACHED` | 409 | Crear, mover o reabrir una tarea hacia una columna llena | `columnId`, `taskLimit` |
| `COLUMN_LIMIT_BELOW_CURRENT` | 409 | `taskLimit` menor que las tareas que la columna ya tiene | `taskCount` |
| `BOARD_COLUMNS_LIMIT_REACHED` | 409 | El tablero ya tiene 12 columnas | |
| `SUBTASKS_LIMIT_REACHED` | 409 | La tarea ya tiene 30 subtareas | |
| `RATE_LIMITED` | 429 | Límite de intentos/consultas | cabecera `Retry-After` |
| `BOARD_LOAD_FAILED` | 500 | Fallo al cargar el tablero (pantalla de error) | |

## 3. DTOs principales

**UserRef** (referencia mínima a una persona, usada en todos los DTO)
```json
{ "userId":"…", "name":"Marco Ruiz", "initials":"MR", "avatarUrl":null }
```

**UserMe**
```json
{ "id":"…", "name":"Jorge Díaz", "email":"jorge@taskflow.app", "jobTitle":"Diseñador de producto",
  "avatarUrl":"https://{host}/api/files/avatars/3f2c….webp", "accountProvider":"GOOGLE",
  "emailVerified":true, "accountState":"ACTIVE", "recoveryDeadline":null,
  "createdAt":"2026-09-01T12:00:00Z" }
```
`accountState` es `ACTIVE` o `PENDING_DELETION`; `recoveryDeadline` solo se llena cuando la cuenta está pendiente de eliminación (solicitud + 30 días).

**BoardSummary** (listado)
```json
{ "id":"…", "name":"Lanzamiento del producto", "color":"#4A3FD6", "description":"…",
  "myRole":"OWNER", "taskCount":10, "completedTaskCount":4, "memberCount":5, "version":2,
  "updatedAt":"2026-10-12T15:20:00Z", "lastActivityAt":"2026-10-16T15:20:00Z" }
```
`color` es uno de los 8 colores de tablero de la paleta fija (`#4A3FD6 #2563EB #0E8F8F #2E9E5B #D98A00 #E5622B #D6336C #5B6075`); cualquier otro valor responde `VALIDATION_FAILED`. `taskCount` cuenta solo las tareas pendientes (no completadas). `updatedAt` cambia únicamente al editar el tablero; `lastActivityAt` refleja cualquier actividad hija (tareas, columnas, comentarios, miembros).

**ColumnDto**
```json
{ "id":"…", "name":"Por hacer", "position":2000, "taskLimit":50, "taskCount":3 }
```

**MemberDto**
```json
{ "userId":"…", "name":"Marco Ruiz", "initials":"MR", "avatarUrl":null,
  "email":"marco.ruiz@taskflow.app", "role":"MEMBER", "joinedAt":"2026-10-01T09:00:00Z" }
```

**BoardDetail** (`GET /api/boards/{id}`: todo en una llamada, solo tareas no completadas)
```json
{ "today":"2026-10-16", "board": { …BoardSummary },
  "columns": [ { …ColumnDto } ],
  "members": [ { …MemberDto } ],
  "tags": [ { "id":"…", "name":"DATA", "color":"#0B6663", "taskCount":2 } ],
  "tasks": [ { …TaskCardDto } ] }
```

**TaskCardDto**
```json
{ "id":"…", "boardId":"…", "columnId":"…", "title":"Configurar analítica", "priority":"HIGH",
  "startDate":"2026-10-19", "dueDate":"2026-10-23", "position":2000, "version":3,
  "isDone":false, "completedAt":null,
  "assignee": { …UserRef o null },
  "tags": [ { "id":"…", "name":"DATA", "color":"#0B6663" } ],
  "subtasksDone":1, "subtasksTotal":4, "commentsCount":3 }
```
En una tarea completada, `columnId` y `position` son `null`, `isDone` es `true` y `completedAt` trae la fecha.

**TaskListItemDto** = TaskCardDto + `board { "id":"…", "name":"…", "color":"#4A3FD6" }` (listas que cruzan tableros: Mis tareas, próximas, completadas).

**TaskDetailDto** = TaskCardDto + `description`, `createdAt`, `updatedAt` y `subtasks: [ { …SubtaskDto } ]`. Los comentarios se piden aparte (paginados).

**SubtaskDto**
```json
{ "id":"…", "title":"Definir eventos", "isDone":false, "position":1000 }
```

**CommentDto**
```json
{ "id":"…", "author": { …UserRef }, "content":"Revisa esto @[Ana Kim](uuid-de-ana)",
  "mentions": [ { "userId":"…", "name":"Ana Kim" } ],
  "createdAt":"2026-10-12T15:20:00Z", "updatedAt":"2026-10-12T15:20:00Z",
  "canEdit":true, "canDelete":true }
```
El contenido (máximo 2 000 caracteres de texto visible; cada mención cuenta como `@Nombre`) escribe las menciones como `@[Nombre](userId)`. `canEdit` es verdadero solo para el autor; `canDelete`, para el autor, Admins y Owner.

**InvitationDto**
```json
{ "id":"…", "board": { "id":"…", "name":"…", "color":"#4A3FD6" },
  "invitedBy": { "userId":"…", "name":"Jorge Díaz" },
  "invitedUser": { "userId":"…", "name":"Ana Kim", "email":"ana.kim@taskflow.app" },
  "status":"PENDING", "expiresAt":"2026-10-21T15:20:00Z", "createdAt":"2026-10-16T15:20:00Z" }
```

**TagDto**: `{ id, name, color, taskCount }`. `color` es uno de los 6 acentos de etiqueta de la paleta fija (`#3B30B0 #1B4DB0 #0B6663 #1A6B3F #8A5200 #A3214F`); el color de fondo de la etiqueta lo deriva el cliente.

**NotificationDto**
```json
{ "id":"…", "type":"MENTION", "actor": { …UserRef o null },
  "boardId":"…", "taskId":"…", "commentId":"…", "invitationId":null,
  "payload": { "taskTitle":"…", "boardName":"…", "snippet":"…" },
  "readAt":null, "createdAt":"2026-10-16T15:20:00Z" }
```
Los identificadores pueden ser `null` si el recurso fue eliminado; el `payload` conserva el texto para mostrarla igualmente. Contenido del `payload` por tipo:

| `type` | `payload` |
|---|---|
| `TASK_ASSIGNED` | `{ taskTitle, boardName }` |
| `MENTION` | `{ taskTitle, boardName, snippet }` (máx. 120 caracteres) |
| `INVITATION_RECEIVED` | `{ boardName, invitedByName }` |
| `INVITATION_ACCEPTED` / `INVITATION_REJECTED` | `{ boardName, userName }` |
| `ROLE_CHANGED` | `{ boardName, role }` |
| `REMOVED_FROM_BOARD` | `{ boardName }` |
| `OWNERSHIP_TRANSFERRED` | `{ boardName, fromUserName }` (al nuevo Owner) |
| `DUE_SOON` / `DUE_TODAY` / `OVERDUE` | `{ taskTitle, boardName, dueDate }` |
| `WEEKLY_DIGEST` | `{ dueThisWeek, overdue, assigned }` |

## 4. Ejemplos por endpoint

### Auth
`POST /api/auth/register`
```json
{ "name":"Ada Lovelace", "email":"ada@empresa.com", "password":"secreta123" }
→ 201 { "user": { …UserMe }, "verificationEmailSent": true }
```
Errores: `EMAIL_ALREADY_REGISTERED`, `VALIDATION_FAILED`. El registro no abre sesión.

`POST /api/auth/login` `{ "email":"…", "password":"…" }` →
```json
200 { "accessToken":"…", "expiresIn":900, "user": { …UserMe } }
+ Set-Cookie: refresh_token=…; HttpOnly; Secure; SameSite=Lax; Path=/api/auth
```
Si la cuenta está en `PENDING_DELETION`, la respuesta es la misma pero con `user.accountState = "PENDING_DELETION"` y `user.recoveryDeadline`; el access token es de recuperación y el cliente muestra la vista de recuperación. Errores: `INVALID_CREDENTIALS`, `ACCOUNT_PROVIDER_MISMATCH`, `RATE_LIMITED`.

`POST /api/auth/refresh` (sin cuerpo; usa la cookie) → `200 { "accessToken":"…", "expiresIn":900, "user": { …UserMe } }` y rota la cookie (rotación de un solo uso). Errores: `UNAUTHENTICATED`; `TOKEN_ALREADY_USED` si se presenta un refresh token ya rotado o revocado.
`POST /api/auth/logout` → `204` (revoca la sesión actual y borra la cookie).
`POST /api/auth/verify-email` `{ "token":"…" }` → `200 { "emailVerified": true }`. Errores: `TOKEN_INVALID`, `TOKEN_EXPIRED`.
`POST /api/auth/verify-email/resend` → `200 {}` (`RATE_LIMITED` si abusa).
`POST /api/auth/forgot-password` `{ "email":"…" }` → `200 {}` (uniforme, exista o no).
`POST /api/auth/reset-password` `{ "token":"…", "newPassword":"…" }` → `204` (revoca todas las sesiones).
`GET /oauth2/authorization/google` → redirección a Google; al terminar, el servidor deja la cookie de refresh y redirige a `FRONTEND_URL`, donde el cliente llama a `POST /api/auth/refresh`.

### Users
`PUT /api/users/me` `{ "name":"…", "jobTitle":"…", "email":"…" }` → `200 UserMe`. `email` solo lo aceptan las cuentas LOCAL; al cambiarlo, `emailVerified` pasa a `false` y se envía un correo de verificación (`EMAIL_ALREADY_REGISTERED` si ya existe).
`PUT /api/users/me/password` `{ "currentPassword":"…", "newPassword":"…" }` → `204`; revoca todas las sesiones y el cliente vuelve al login. Errores: `CURRENT_PASSWORD_INCORRECT`, `VALIDATION_FAILED`.
`POST /api/users/me/avatar` (multipart, campo `file`: PNG/JPG/WebP, máx. 2 MB) → `200 { "avatarUrl":"https://{host}/api/files/avatars/3f2c….webp" }`. Error: `AVATAR_INVALID`.
`DELETE /api/users/me/avatar` → `204`.
`GET /api/files/avatars/{file}` → imagen (público; el nombre del archivo no es adivinable).
`GET /api/users/me/deletion-blockers` → `200 { "boards":[ { "id":"…", "name":"…", "memberCount":4 } ] }`.
`DELETE /api/users/me` → `200 { "recoveryDeadline":"2026-11-15T15:20:00Z" }` (revoca todas las sesiones y envía el correo de aviso) o `409 ACCOUNT_DELETE_BLOCKED` + `blockingBoards[]`.
`POST /api/users/me/restore` → `204` (solo sesión de recuperación; luego el cliente llama a `refresh` para obtener una sesión normal) o `409 RECOVERY_PERIOD_EXPIRED`.
`GET /api/users/lookup?email=ana.kim@taskflow.app&boardId=…`
```json
→ 200 { "status":"FOUND", "user": { …UserRef, "jobTitle":"…" } }
→ 200 { "status":"NOT_FOUND" }
→ 200 { "status":"ALREADY_MEMBER", "user": { … }, "role":"ADMIN" }
→ 200 { "status":"ALREADY_INVITED", "user": { … }, "invitation": { "expiresAt":"2026-10-21T15:20:00Z" } }
→ 200 { "status":"SELF" }
```
`boardId` es opcional; sin él solo se devuelve `FOUND`, `NOT_FOUND` o `SELF`. Las cuentas en eliminación se tratan como `NOT_FOUND`. Límite: 10 por minuto por usuario (`RATE_LIMITED`).

### Boards
`POST /api/boards`
```json
{ "name":"Marketing Q4", "description":"…", "color":"#4A3FD6", "createDefaultColumns":true,
  "initialTags": [ { "name":"DISEÑO", "color":"#3B30B0" } ],
  "initialInvitations": [ "ana.kim@taskflow.app", "marco.ruiz@taskflow.app" ] }
→ 201 { "board": { …BoardDetail }, "invitations": [ { "email":"…", "result":"INVITED|SKIPPED", "reason":"USER_NOT_FOUND|SELF|DUPLICATE" } ] }
```
`createDefaultColumns` es opcional (por defecto `false`); si es `true` crea Backlog, Por hacer, En curso y Hecho con `taskLimit` 50.
`GET /api/boards?role=member&sort=lastActivityAt,desc&page=0&size=20` → paginado de `BoardSummary`. Campos de `sort` permitidos: `lastActivityAt`, `updatedAt` y `name`. Los tableros recientes del Inicio y del sidebar usan `sort=lastActivityAt,desc&size=4`.
`GET /api/boards/{id}` → `200 BoardDetail` (error `BOARD_LOAD_FAILED` si falla la carga).
`PUT /api/boards/{id}` `{ "name":"…", "description":"…", "color":"#…", "version":2 }` → `200 BoardSummary` (solo Owner); `409 BOARD_VERSION_CONFLICT`.
`DELETE /api/boards/{id}` → `204` (solo Owner).
`POST /api/boards/{id}/transfer` `{ "newOwnerUserId":"…" }` → `200`; evento `OwnershipTransferred`. Error: `TRANSFER_TARGET_INVALID`.
`DELETE /api/boards/{id}/members/me` → `204` o `409 OWNER_MUST_TRANSFER`.
`GET /api/boards/{id}/search?q=landing` →
```json
200 { "tasks":[ { "id":"…", "title":"…", "columnId":"…", "isDone":false } ],
      "tags":[ { "id":"…", "name":"…", "color":"#…", "taskCount":5 } ],
      "comments":[ { "id":"…", "taskId":"…", "taskTitle":"…", "snippet":"…" } ] }
```
Mínimo 2 caracteres (`VALIDATION_FAILED`); máximo 20 resultados por tipo.
`GET /api/boards/{id}/completed-tasks?page=0&size=20` → paginado de `TaskCardDto` completadas, ordenadas por `completedAt` descendente.
`GET /api/boards/{id}/timeline?from=2026-10-01&to=2026-10-31` →
```json
200 { "today":"2026-10-16", "items":[ { "taskId":"…", "title":"…", "priority":"HIGH", "startDate":"2026-10-19",
                  "dueDate":"2026-10-23", "columnId":"…", "bucket":"THIS_WEEK", "assignee": { …UserRef o null } } ] }
```
Solo tareas con `dueDate` que no estén completadas. `bucket` es el mismo del listado de Mis tareas (`OVERDUE`, `TODAY`, `THIS_WEEK`, `LATER`, `ON_TRACK`; los `NO_DATE` no aparecen porque no tienen `dueDate`). Sin `from`/`to` devuelve 4 semanas desde el lunes de la semana en curso (según `APP_TIMEZONE`); el rango máximo por consulta es de 92 días (`VALIDATION_FAILED` si lo supera o si `from > to`).

### Miembros e invitaciones
`GET /api/boards/{id}/members` → lista de `MemberDto`.
`PATCH /api/boards/{id}/members/{userId}` `{ "role":"ADMIN" }` → `200 MemberDto` (solo Owner); `OWNER_CANNOT_BE_REMOVED` si apunta al Owner.
`DELETE /api/boards/{id}/members/{userId}` → `204`. Errores: `FORBIDDEN` (un Admin no puede quitar a Admins ni al Owner), `OWNER_CANNOT_BE_REMOVED`.
`POST /api/boards/{id}/invitations` `{ "email":"lucia.perez@taskflow.app" }` → `201 InvitationDto`. Errores: `USER_NOT_FOUND`, `ALREADY_MEMBER`, `INVITATION_DUPLICATE`, `INVITATION_SELF`.
`GET /api/boards/{id}/invitations` → lista de `InvitationDto` pendientes (Owner/Admin).
`DELETE /api/invitations/{id}` → `204` (Owner/Admin; `INVITATION_NOT_PENDING` si ya se resolvió).
`POST /api/invitations/{id}/accept` → `200 { "member": { …MemberDto } }`. Errores: `INVITATION_EXPIRED`, `INVITATION_NOT_PENDING`.
`POST /api/invitations/{id}/reject` → `204`.
`GET /api/users/me/invitations?status=PENDING` → lista de `InvitationDto`.

### Columnas y tareas
`POST /api/boards/{id}/columns` `{ "name":"En curso", "taskLimit":10 }` → `201 ColumnDto` (`taskLimit` opcional, por defecto 50). Error: `BOARD_COLUMNS_LIMIT_REACHED`.
`PUT /api/columns/{id}` `{ "name":"En curso", "taskLimit":8 }` → `200 ColumnDto`. Error: `COLUMN_LIMIT_BELOW_CURRENT`.
`PATCH /api/columns/{id}/position` `{ "position":2 }` → `200`.
`DELETE /api/columns/{id}` → `204` (borra en cascada sus tareas; la confirmación en la interfaz usa `ColumnDto.taskCount`).
`POST /api/columns/{id}/tasks` (solo Owner/Admin)
```json
{ "title":"…", "description":"…", "priority":"MEDIUM", "assigneeId":"…",
  "startDate":"2026-10-19", "dueDate":"2026-10-23", "tagIds":["…","…"] }
→ 201 TaskDetailDto
```
Errores: `COLUMN_LIMIT_REACHED`, `ASSIGNEE_NOT_MEMBER`, `TAG_LIMIT_EXCEEDED`, `DATE_RANGE_INVALID`.
`GET /api/tasks/{id}` → `200 TaskDetailDto`.
`PUT /api/tasks/{id}` `{ "title":"…", "description":"…", "priority":"HIGH", "startDate":"…", "dueDate":"…", "tagIds":["…"], "version":3 }` → `200 TaskDetailDto` con `version` incrementada. No modifica el asignado (usa `assignee`). Un Miembro solo puede enviar `title`, `description` y `tagIds` en tareas asignadas a él (`TASK_FIELD_FORBIDDEN` si intenta cambiar fechas o prioridad).
Conflicto:
```json
409 { "status":409, "code":"TASK_VERSION_CONFLICT", "detail":"La tarea cambió mientras la editabas",
      "currentVersion":4, "current": { …TaskDetailDto } }
```
"Sobrescribir" en la interfaz es reenviar el `PUT` con `"version": 4`.
`DELETE /api/tasks/{id}` → `204`.
`PATCH /api/tasks/{id}/move` `{ "columnId":"…", "position":1 }` → `200 TaskCardDto`. Errores: `COLUMN_LIMIT_REACHED`, `TASK_ALREADY_COMPLETED` (una tarea completada no se mueve; se reabre), `FORBIDDEN`.
`PATCH /api/tasks/{id}/assignee` `{ "assigneeId":"…" }` (o `null` para quitar) → `200 TaskCardDto`. Un Miembro solo puede enviar `null` y solo en tareas que tiene asignadas.
`POST /api/tasks/{id}/complete` (sin cuerpo) → `200 TaskCardDto` con `isDone: true`, `columnId: null`. Error: `TASK_ALREADY_COMPLETED`.
`POST /api/tasks/{id}/reopen` `{ "columnId":"…", "position":0 }` → `200 TaskCardDto` pendiente en la columna elegida. Errores: `TASK_NOT_COMPLETED`, `COLUMN_LIMIT_REACHED`.

### Subtareas, comentarios y etiquetas
`POST /api/tasks/{id}/subtasks` `{ "title":"…" }` → `201 SubtaskDto`. Error: `SUBTASKS_LIMIT_REACHED`.
`PUT /api/subtasks/{id}` `{ "title":"…", "isDone":true }` → `200 SubtaskDto`.
`DELETE /api/subtasks/{id}` → `204`.
`GET /api/tasks/{id}/comments?page=0&size=20` → paginado de `CommentDto`, de más antiguo a más reciente.
`POST /api/tasks/{id}/comments` `{ "content":"…" }` → `201 CommentDto`. Una mención a alguien que no es miembro del tablero responde `VALIDATION_FAILED` con `errors[{ field:"content" }]`.
`PUT /api/comments/{id}` `{ "content":"…" }` → `200 CommentDto`; `DELETE /api/comments/{id}` → `204`.
`POST /api/boards/{id}/tags` `{ "name":"DATA", "color":"#0B6663" }` → `201 TagDto` (`TAG_DUPLICATE` si el nombre ya existe).
`GET /api/boards/{id}/tags` → lista de `TagDto`; `PUT /api/tags/{id}` → `200 TagDto`; `DELETE /api/tags/{id}` → `204`.

### Notificaciones
`GET /api/notifications?unread=true&page=0&size=20` → paginado de `NotificationDto`, de más reciente a más antigua. Por defecto **excluye** las `INVITATION_RECEIVED` cuya invitación sigue pendiente (se muestran en el bloque de invitaciones, `GET /api/users/me/invitations`); el `total` del feed no las cuenta, pero `unread-count` sí.
`GET /api/notifications/unread-count` → `200 { "unreadCount": 3 }`.
`PATCH /api/notifications/{id}/read` → `200 { "unreadCount": 2 }`.
`POST /api/notifications/read-all` → `200 { "unreadCount": 0 }`.
`DELETE /api/notifications/{id}` → `204`.

### Mis tareas y resumen
`GET /api/tasks?assigneeId=me&boardId=&priority=HIGH&isDone=false&dueFrom=2026-10-01&dueTo=2026-10-31&q=api&sort=dueDate,asc&page=0&size=20` → paginado de `TaskListItemDto`, cada uno con un campo `bucket` calculado por el servidor:

| `bucket` | Regla (se evalúa en este orden, solo tareas no completadas) |
|---|---|
| `NO_DATE` | No tiene `dueDate` (segunda sección de la vista) |
| `ON_TRACK` | Tiene `dueDate`, tiene subtareas y todas están hechas ("al día") |
| `OVERDUE` | `dueDate` anterior a hoy |
| `TODAY` | `dueDate` es hoy |
| `THIS_WEEK` | `dueDate` entre mañana y el domingo de esta semana |
| `LATER` | `dueDate` posterior al domingo de esta semana |
| `null` | Tarea completada (solo aparece con `isDone=true`) |

La vista tiene dos secciones: arriba las tareas con fecha límite (`OVERDUE`, `TODAY`, `THIS_WEEK`, `LATER`, `ON_TRACK`) y debajo, en su propia lista, las tareas sin fecha límite (`NO_DATE`). Con `sort=dueDate,asc` las tareas sin fecha quedan al final, ordenadas por prioridad (de `URGENT` a `LOW`), de modo que la paginación recorre primero la sección con fecha y luego la de sin fecha. Con `bucket` el cliente solo agrupa por clave; no calcula fechas ni zona horaria.
`GET /api/dashboard/summary?limit=6`
```json
{ "today":"2026-10-16", "assigned": 12, "dueToday": 3,
  "upcoming": [ { …TaskListItemDto, "bucket":"OVERDUE" } ] }
```
`assigned` son las tareas pendientes asignadas al usuario (incluye las "al día") y `dueToday` las que vencen hoy. `upcoming` trae hasta `limit` tareas asignadas pendientes (6 por defecto): primero las vencidas y luego por fecha límite, cada una con su `bucket`. Todas las cifras excluyen tareas completadas. Los tableros recientes del Inicio salen de `GET /api/boards` (arriba) y las notificaciones recientes de `GET /api/notifications?size=4`.

`GET /api/dashboard/calendar?month=2026-10` → `200 { "month":"2026-10", "days":[ { "date":"2026-10-16", "tasks":[ { "id":"…", "title":"…", "boardId":"…", "boardColor":"#4A3FD6" } ] } ] }`. Solo tareas asignadas al usuario, pendientes y con `dueDate` en ese mes (según `APP_TIMEZONE`); los días sin tareas se omiten. `month` inválido → `VALIDATION_FAILED`.

`GET /api/me/counters` → `200 { "openAssigned": 11, "unreadNotifications": 3 }`. `openAssigned` cuenta las tareas asignadas pendientes **sin** las "al día" (es el número de "Mis tareas" en el sidebar); `unreadNotifications` incluye las invitaciones pendientes y es el mismo valor de `unread-count`.

## 5. Eventos STOMP (envelope y payloads)

Envelope en `/topic/boards/{boardId}`:
```json
{ "eventId":"…", "type":"TaskMoved", "boardId":"…", "entityId":"…", "actorId":"…",
  "occurredAt":"2026-10-16T15:20:00Z", "payload": { … } }
```
`entityId` es el identificador de la entidad principal del evento (tarea, columna, comentario, etc.).

| Tipo | `payload` |
|---|---|
| `TaskCreated` | `{ "task": { …TaskCardDto } }` |
| `TaskUpdated` | `{ "task": { …TaskCardDto }, "version": 4 }` |
| `TaskDeleted` | `{ "taskId":"…", "columnId":"…o null" }` |
| `TaskMoved` | `{ "taskId":"…", "fromColumnId":"…", "toColumnId":"…", "position":1500, "order":["taskId1","taskId2"] }` (`position` es el valor almacenado; `order` es el orden final de la columna destino, ADR-001) |
| `TaskCompleted` | `{ "task": { …TaskCardDto }, "fromColumnId":"…" }` |
| `TaskPending` | `{ "task": { …TaskCardDto } }` (tarea reabierta, ya con su columna y posición) |
| `TaskAssigneeChanged` | `{ "taskId":"…", "assignee": { …UserRef o null } }` |
| `SubtaskCreated/Updated/Deleted` | `{ "taskId":"…", "subtask": { …o subtaskId }, "subtasksDone":1, "subtasksTotal":4 }` |
| `CommentCreated/Updated/Deleted` | `{ "taskId":"…", "comment": { …o commentId }, "commentsCount":3 }` |
| `ColumnCreated/Updated/Deleted` | `{ "column": { …ColumnDto o columnId } }` (`Updated` trae el `taskLimit` nuevo) |
| `ColumnReordered` | `{ "order":["colId1","colId2"] }` |
| `TagCreated/Updated` | `{ "tag": { … } }` |
| `TagDeleted` | `{ "tagId":"…", "affectedTaskIds":["…"] }` |
| `TaskTagChanged` | `{ "taskId":"…", "tags":[ { … } ] }` |
| `MemberAdded` | `{ "member": { …MemberDto } }` |
| `MemberRoleChanged` | `{ "userId":"…", "role":"ADMIN" }` |
| `MemberRemoved` / `MemberLeft` | `{ "userId":"…" }` |
| `InvitationCreated` / `InvitationCanceled` / `InvitationExpired` | `{ "invitation": { …InvitationDto } }` |
| `InvitationAccepted` / `InvitationRejected` | `{ "invitation": { …InvitationDto } }` (`Accepted` va seguido de `MemberAdded`) |
| `OwnershipTransferred` | `{ "fromUserId":"…", "toUserId":"…" }` |
| `BoardUpdated` | `{ "board": { …BoardSummary } }` |
| `BoardDeleted` | `{ "boardId":"…" }` |

**Cola personal** `/user/queue/notifications` (mismo envelope, sin `boardId`):

| Tipo | `payload` |
|---|---|
| `NotificationCreated` | `{ "notification": { …NotificationDto }, "unreadCount": 3 }` |
| `NotificationsRead` | `{ "unreadCount": 0 }` (sincroniza varias pestañas) |

Reglas:
- El cliente aplica el payload directamente (la UI no refetch); si el recurso no está en pantalla, se ignora.
- El autor de la acción también recibe su propio evento; aplicarlo debe ser idempotente (usar `eventId` o la `version`).
- Los eventos de un usuario que está editando el mismo `taskId` disparan el banner de conflicto en vez de sobrescribir el formulario.
- Cambiar etiquetas con `PUT /api/tasks/{id}` emite `TaskUpdated`; `TaskTagChanged` se emite además cuando el conjunto de etiquetas cambia por cualquier vía (incluido borrar una etiqueta). Aplicar ambos es idempotente.
- Al recibir `MemberRemoved`/`MemberLeft` con el propio `userId`, o `BoardDeleted`, el cliente se desuscribe del topic y sale del tablero.
- Los eventos solo se publican después de confirmar la transacción. Si la conexión se cae y se recupera, el cliente recarga el estado del tablero y el contador de notificaciones (no hay reenvío de eventos perdidos).
