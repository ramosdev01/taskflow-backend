# Documento de Requisitos Técnicos (TRD)
## Task Flow
### App colaborativa de gestión de tareas.

**Versión:** 1
**Fecha:** 16 Octubre 2026

---

## 1. Resumen del proyecto

Aplicación web colaborativa para gestión de tareas. Permite crear
tableros con columnas, tareas y subtareas, comentar sobre tareas, mencionar a otros miembros, e invitar a otros
usuarios a colaborar en tiempo real dentro de un tablero. Incluye un feed de notificaciones y recordatorios de vencimiento. La interfaz es web y está en español.

## 2. Objetivos

- Permitir a un usuario crear y administrar tableros de trabajo.
- Habilitar colaboración en tiempo real entre varios usuarios dentro de un mismo tablero.
- Ofrecer un sistema de roles y permisos claros para controlar quién puede hacer qué.
- Mantener informado al usuario mediante notificaciones dentro de la app (asignaciones, menciones, invitaciones, vencimientos).
- Construir el backend con Java 25 y Spring Boot 4.1.1, aprovechando el ecosistema moderno del framework.

## 3. Alcance funcional

### 3.1 Gestión de tableros
- Crear, editar y eliminar tableros. Editar y eliminar son acciones exclusivas del `Owner`; la eliminación pide confirmación y borra en cascada columnas, tareas, subtareas, comentarios, etiquetas, miembros e invitaciones.
- Un tablero tiene un único `Owner` (creador) y puede tener múltiples miembros. El Owner también figura como miembro con rol `OWNER`; ambas referencias deben coincidir siempre.
- Al crear un tablero el usuario puede marcar la opción de generar columnas por defecto (parámetro `createDefaultColumns`, por defecto `false`); si se marca se generan 4 columnas: **Backlog, Por hacer, En curso y Hecho**.
- Al crear un tablero se pueden definir **etiquetas iniciales** (nombre y color) y enviar **invitaciones iniciales** por lote: la petición incluye correos; cada correo debe pertenecer a un usuario existente y el servidor responde el resultado por correo (invitado / omitido con motivo: no encontrado, uno mismo, duplicado). La interfaz valida cada correo con la búsqueda exacta (§3.12) antes de añadirlo a la lista y, al crear el tablero, resume el resultado en un aviso breve (enviadas y no enviadas); no hay diálogo de resultado.
- El listado de tableros devuelve el rol del usuario en cada tablero y el conteo de tareas, con filtro `role=owner|member` (permite separar "Mis tableros" de "Invitado").
- **Transferir propiedad** (solo el Owner): el nuevo Owner debe ser un miembro activo (no una cuenta en eliminación); el Owner anterior pasa a **ADMIN**.
- **Salir del tablero**: un miembro puede salir; el Owner queda bloqueado hasta transferir la propiedad (si es el único miembro, salir equivale a eliminar el tablero). Al salir o ser removido, sus tareas asignadas quedan sin asignado y sus comentarios se conservan.
- No existe `boardType` (personal/colaborativo): cualquier tablero puede tener miembros.

### 3.2 Roles y permisos por tablero

| Acción | Owner | Admin | Miembro |
|---|---|---|---|
| Ver tablero, buscar, comentar cualquier tarea | ✔ | ✔ | ✔ |
| Editar o eliminar el tablero | ✔ | ✘ | ✘ |
| Transferir propiedad | ✔ | ✘ | ✘ |
| Cambiar roles (ADMIN ⇄ MEMBER) | ✔ | ✘ | ✘ |
| Invitar miembros y cancelar invitaciones | ✔ | ✔ | ✘ |
| Eliminar miembros | ✔ | ✔ (solo `MEMBER`) | ✘ |
| Salir del tablero | ✔ (tras transferir) | ✔ | ✔ |
| CRUD y reordenamiento de columnas | ✔ | ✔ | ✘ |
| Crear y eliminar tareas | ✔ | ✔ | ✘ |
| Editar tarea completa (título, descripción, fechas, prioridad, etiquetas) | ✔ | ✔ | Solo título, descripción y etiquetas, y solo en tareas asignadas a él |
| Mover o reordenar tareas, completar y reabrir | ✔ | ✔ | Solo tareas asignadas a él |
| Asignar o reasignar | ✔ | ✔ | Solo puede desasignarse de sus propias tareas; no asigna a otros |
| CRUD de subtareas | ✔ | ✔ | Solo en tareas asignadas a él |
| Editar comentario | Solo el propio | Solo el propio | Solo el propio |
| Eliminar comentario | Cualquiera | Cualquiera | Solo el propio |
| Crear, editar y eliminar etiquetas del tablero | ✔ | ✔ | ✔ |

- **Cambiar rol** (solo Owner): de ADMIN a MEMBER y viceversa; no aplica al propio Owner.
- Si un Miembro intenta modificar campos que no le corresponden (fechas, prioridad), el servidor responde 403.

### 3.3 Columnas
- CRUD de columnas dentro de un tablero.
- Reordenamiento de columnas (drag & drop) sincronizado en tiempo real.
- **Límite de columnas por tablero**: máximo 12. Al intentar crear una más el servidor responde 409 `BOARD_COLUMNS_LIMIT_REACHED`; la interfaz deshabilita el botón de agregar columna.
- **Límite de tareas por columna** (`taskLimit`): cada columna tiene un máximo de tareas pendientes, configurable por el Owner o un Admin entre 1 y 100 (por defecto 50, también en las columnas generadas por defecto). Se puede bajar para usarlo como límite de trabajo en curso (por ejemplo, 5 en "En curso"). No se puede fijar un valor menor que las tareas que la columna ya tiene (409 `COLUMN_LIMIT_BELOW_CURRENT`). Las tareas completadas no cuentan, porque salen del kanban. El cambio de límite se propaga con el evento `ColumnUpdated`.
- En la interfaz el encabezado de la columna muestra el contador (por ejemplo `7/50`), con color de alerta al llegar al 80%; cuando está llena no permite soltar tarjetas ni agregar tareas.
- **Eliminar columna**: borrado en cascada; la confirmación indica cuántas tareas (con sus subtareas y comentarios) se eliminarán.
- El color de la columna es una convención de interfaz derivada por posición; no se persiste.

### 3.4 Tareas
- CRUD de tareas dentro de una columna.
- Campos: título, descripción, fecha de inicio (`startDate`, nullable), fecha límite (`dueDate`, nullable), prioridad (**LOW/MEDIUM/HIGH/URGENT**, por defecto MEDIUM), etiquetas (**máximo 3 por tarea**), `assigneeId` (un solo usuario, debe ser miembro del tablero; la tarea puede crearse sin asignado).
- Validación: `startDate <= dueDate`.
- Un usuario puede tener asignadas varias tareas dentro de un tablero.
- Reordenamiento y cambio de columna (drag & drop) sincronizado en tiempo real; el contrato de `move` incluye `columnId` y `position`.
- **Límite de la columna destino**: crear una tarea, moverla a otra columna o reabrir una tarea completada hacia una columna que ya alcanzó su `taskLimit` se rechaza con 409 `COLUMN_LIMIT_REACHED`. Reordenar dentro de la misma columna no cambia el conteo y no se bloquea. La validación se hace bloqueando la columna para que dos movimientos simultáneos no superen el límite; si un arrastre falla, el cliente devuelve la tarjeta a su lugar. El selector de columna al reabrir muestra las columnas llenas deshabilitadas.
- **Concurrencia optimista**: `Task.version`; las ediciones por formulario (`PUT`) envían la versión y el servidor responde **409** si otra persona guardó primero. La respuesta incluye la versión y el estado actuales; en la interfaz se muestra el estado de conflicto (recargar o sobrescribir: sobrescribir es reenviar el `PUT` con la versión actual recibida). Las operaciones en vivo (mover, reordenar, asignar, completar, reabrir) no incrementan `version` y siguen la regla de "última escritura persistida gana"; el cliente reconcilia con el evento recibido.
- **Selector de asignado** disponible en el detalle de la tarea y en el formulario de crear tarea (`PATCH /api/tasks/{id}/assignee` con los permisos de la sección 3.2).
- **Completar y reabrir**:
  - Una tarea se marca como completada (`isDone = true`, con `completedAt`) y sale del kanban: deja de pertenecer a una columna y pasa a la sección de tareas completadas del tablero.
  - Al **reabrirla** el usuario elige la columna de destino; la tarea vuelve al kanban como pendiente.
  - Las tareas completadas no cuentan como vencidas, no generan recordatorios y no aparecen en el cronograma.
- El progreso de una tarea se mide por **subtareas hechas / total**. "Al día" (definición derivada, sección 3.14) es un concepto distinto de `isDone`: una tarea puede estar al día sin estar completada.

### 3.5 Subtareas
- CRUD de subtareas dentro de una tarea.
- Marcar como completada/pendiente (`isDone`).
- Tienen orden propio (`position`): las nuevas se agregan al final; reordenarlas queda fuera de la v1.
- **Límite**: máximo 30 subtareas por tarea; al superarlo el servidor responde 409 `SUBTASKS_LIMIT_REACHED` y la interfaz deshabilita el botón de agregar.

### 3.6 Comentarios
- Los usuarios que pertenezcan al tablero pueden comentar cualquier tarea.
- Edición y eliminación del propio comentario; el Owner y los Admins pueden eliminar comentarios de otros usuarios (no editarlos).
- **Menciones (@)**: en el texto se puede mencionar a miembros del tablero; solo se aceptan menciones de miembros actuales y cada mención genera una notificación (sección 3.17). Al editar un comentario solo notifican las menciones nuevas.
- El listado de comentarios de una tarea es paginado.

### 3.7 Etiquetas (labels)
- Definidas a nivel de tablero (nombre + color). El nombre es único por tablero.
- Una etiqueta puede asignarse a múltiples tareas (reutilizable) y solo a tareas del mismo tablero.
- Máximo 3 etiquetas por tarea.
- En la interfaz se gestionan desde el menú del tablero (ícono ⋯), que ven **todos los roles**; el color es uno de los 6 acentos de la paleta fija.
- El listado de etiquetas incluye su conteo de uso; al eliminar una etiqueta se desvincula en cascada de sus tareas.

### 3.8 Colaboración en tiempo real
- Cambios en columnas, tareas, subtareas, comentarios, etiquetas y miembros se propagan en vivo a todos los usuarios conectados al mismo tablero.
- **Catálogo de eventos** publicados al topic `/topic/boards/{boardId}`: `BoardUpdated`, `BoardDeleted`, `ColumnCreated/Updated/Deleted/Reordered`, `TaskCreated/Updated/Deleted/Moved/Completed/Pending/AssigneeChanged`, `SubtaskCreated/Updated/Deleted`, `CommentCreated/Updated/Deleted`, `TagCreated/Updated/Deleted`, `TaskTagChanged`, `MemberAdded/RoleChanged/Removed/Left`, `InvitationCreated/Accepted/Rejected/Canceled/Expired`, `OwnershipTransferred`.
- **Formato común de evento**: `eventId`, `type`, `boardId`, `entityId`, `actorId`, `occurredAt` y `payload` (las formas exactas por tipo están en `contratos-api.md`). Los eventos se publican solo después de confirmar la transacción.
- Eventos personales del usuario (notificaciones) por la cola `/user/queue/notifications` (sección 3.17).
- Cuando un usuario es removido, sale del tablero o el tablero se elimina, el servidor deja de enviarle los eventos de ese topic y el cliente se desuscribe.
- La interfaz muestra el estado de conexión con 3 variantes: **EN VIVO** (conectado), **RECONECTANDO…** y **SIN CONEXIÓN**. Es un indicador de conexión STOMP, no de presencia. Al recuperar la conexión el cliente recarga el estado del tablero, porque no hay reenvío de eventos perdidos.

### 3.9 Autenticación
- **Registro** (LOCAL): nombre, correo, contraseña (mínimo 8 caracteres con al menos un número y máximo 72 bytes, almacenada con bcrypt costo 12). Se envía un **correo de verificación** (SMTP) con token de 24 horas; el usuario puede reenviarlo y ve el estado "enlace expirado". La verificación es **informativa y no bloquea el acceso**; el estado se muestra en Ajustes > Cuenta (con botón "Verificar correo" si falta). Las cuentas Google nacen con el correo verificado.
- **Términos y privacidad**: el formulario de registro exige aceptar los Términos y la Política de Privacidad (casilla obligatoria con enlaces a las páginas públicas de `terminos-privacidad.md`); el acceso con Google muestra los mismos enlaces.
- **Login**: JWT de vida corta (access token, 15 minutos) + refresh token **persistido** (tabla `refresh_token`, revocable, 7 días, con rotación en cada renovación). `POST /api/auth/refresh` renueva; `POST /api/auth/logout` revoca la sesión actual y el cambio de contraseña revoca todas las sesiones. Si se presenta un refresh token ya rotado o revocado, se revocan todas las sesiones del usuario. Ambos tiempos son configurables.
- **Entrega de tokens**: el refresh token viaja en una cookie `HttpOnly` (`Secure`, `SameSite`); el access token lo mantiene el cliente en memoria. CORS permite únicamente el origen del frontend con credenciales.
- **OAuth2 Google**: flujo estándar; al primer login se crea/vincula el `User`. Al terminar, el backend deja la cookie de refresh y redirige al frontend, que llama a `POST /api/auth/refresh` para obtener el access token (nunca viaja un token en la URL).
- Si un correo ya existe con otro proveedor, el login falla con el error **"esta cuenta está registrada con otro proveedor"** y se indica el proveedor correcto. No se vinculan cuentas.
- **Cuenta en eliminación**: el login (LOCAL o Google) de una cuenta `PENDING_DELETION` no abre sesión normal; devuelve una sesión de recuperación (sin acceso a la aplicación) y el cliente muestra la vista de recuperación (sección 3.11). Una cuenta ya `DELETED` no puede iniciar sesión.
- **Olvidé mi contraseña**: solicitud por correo (respuesta uniforme exista o no la cuenta) + restablecimiento con token de 60 minutos; pantallas para token inválido/expirado.
- Límites de frecuencia: login, solicitudes de correo y consulta de usuarios por correo exacto (valores en el esquema de backend).

### 3.10 Usuario actual
- `GET /api/users/me` y `PUT /api/users/me`: nombre, correo (solo cuentas con proveedor LOCAL) y **título o profesión** (`jobTitle`). El perfil incluye el **estado de verificación del correo**. Si una cuenta LOCAL cambia su correo, queda sin verificar y se envía un nuevo correo de verificación.
- `PUT /api/users/me/password`: solo cuentas LOCAL (las cuentas Google no ven esta opción).
- **Avatar**: subida (`POST /api/users/me/avatar`, imágenes PNG/JPG/WebP de hasta 2 MB) y eliminación. Se guarda en almacenamiento local del servidor (volumen) detrás de una abstracción para poder migrar a un almacenamiento externo. Las cuentas Google arrancan con la foto de Google.

### 3.11 Ciclo de vida de la cuenta
- Estados: `ACTIVE`, `PENDING_DELETION`, `DELETED`.
- `DELETE /api/users/me` solicita la eliminación (solo si no hay bloqueo) → `PENDING_DELETION`, con un periodo de gracia de 30 días contados desde la solicitud (`deletionRequestedAt`). Al solicitarla se **cierran todas sus sesiones**, el cliente vuelve a la pantalla de login y se envía un correo con la fecha límite de recuperación (plantilla en `plantillas-correo.md`).
- **Inicio de sesión durante la gracia**: el usuario **no entra a la aplicación**. Si se autentica correctamente (correo y contraseña o Google), el sistema le da una **sesión de recuperación**, que solo sirve para ver su estado y recuperar la cuenta, y el cliente lo lleva a la **vista de recuperación**. Cualquier otro endpoint, y la conexión WebSocket, responde 403 `ACCOUNT_PENDING_DELETION`.
- **Vista de recuperación**: muestra que la cuenta está programada para eliminarse, la fecha límite para recuperarla y el botón **"Recuperar cuenta"**; también permite cerrar sesión. La opción existe únicamente mientras no hayan pasado los 30 días.
- **Recuperar cuenta** (`POST /api/users/me/restore`): vuelve a `ACTIVE`, borra la solicitud y el cliente obtiene una sesión normal. Si ya pasaron los 30 días responde 409 `RECOVERY_PERIOD_EXPIRED`, aunque la purga aún no se haya ejecutado. Quien olvidó su contraseña puede usar "Olvidé mi contraseña" y luego recuperar la cuenta.
- **Mientras la cuenta está pendiente**: no recibe notificaciones, recordatorios ni resumen semanal; no se le puede invitar ni transferir propiedad; sus membresías y tareas asignadas se conservan hasta la purga.
- **Bloqueo**: si el usuario es Owner de tableros con otros miembros, la eliminación se bloquea y se ofrece transferir la propiedad de cada tablero, uno por uno (el usuario decide a quién transfiere cada uno). Hay un endpoint para listar los tableros que bloquean. Una cuenta en `PENDING_DELETION` no puede recibir propiedad ni invitaciones.
- **Purga programada** (job diario) → `DELETED` + `deletedAt`, y limpieza: se revocan sesiones, se eliminan notificaciones, se cancelan invitaciones pendientes, se quitan sus membresías y asignaciones, se eliminan los tableros donde era el único miembro y se **anonimizan** sus datos personales (nombre, correo, avatar, identificadores) conservando sus comentarios.

### 3.12 Invitaciones
- Invitar miembros existentes buscando por correo **exacto** (sin autocompletar).
- Estados del modal: usuario encontrado, no encontrado, ya miembro (con su rol), ya invitado (con la expiración de la invitación pendiente) y uno mismo (la búsqueda recibe el tablero para calcular el estado). Además, límite de frecuencia con cuenta regresiva.
- `POST /api/boards/{id}/invitations`; listado por tablero (pendientes) y listado propio (`GET /api/users/me/invitations`).
- No se puede invitar a quien ya es miembro ni a uno mismo; se puede volver a invitar si la anterior fue rechazada, cancelada o expiró.
- Cancelar invitación (`DELETE /api/invitations/{id}` → estado `CANCELED`), solo Owner o Admin.
- Aceptar/rechazar solo lo hace el invitado; al aceptar se crea `BoardMember` con rol **MEMBER** (el Owner puede cambiarlo después).
- Expiración a los 5 días (job programado: PENDING → EXPIRED).
- Duplicados: si existe una invitación PENDING al mismo usuario en el tablero, `POST` responde **409** ("ya invitado").
- Al invitar se envía un **correo de aviso** al invitado; la aceptación o rechazo ocurre **solo dentro de la app**, nunca desde el correo.
- **Bandeja de invitaciones pendientes (v1)**: visible dentro de la pantalla de Notificaciones, con Aceptar/Rechazar y expiración. La invitación es la fuente de verdad de la bandeja; además genera una notificación (sección 3.17).

### 3.13 Búsqueda en el tablero
- `GET /api/boards/{id}/search?q=` — alcance: títulos y descripciones de tareas, nombres de etiquetas y comentarios; disponible para **todos los miembros** del tablero. Búsqueda por coincidencia parcial, sin distinguir mayúsculas.
- La interfaz muestra "sin resultados" con sugerencias y el resultado se muestra en un desplegable.

### 3.14 Mis tareas
- `GET /api/tasks` con filtros: asignado (`assigneeId=me`), tablero, prioridad, rango de vencimiento, completadas (`isDone`) y texto (`q`); orden por vencimiento; paginación. Solo devuelve tareas de tableros donde el usuario es miembro.
- La vista se muestra en **dos secciones** (solo tareas no completadas): arriba las tareas **con fecha límite**, agrupadas en **VENCIDAS · HOY · ESTA SEMANA · MÁS ADELANTE · AL DÍA**, y debajo, en su propia lista, las tareas **sin fecha límite** (**SIN FECHA**). El servidor calcula el grupo de cada tarea y, al ordenar por vencimiento, las tareas sin fecha quedan al final, ordenadas por prioridad.
- Definiciones derivadas:
  - "Al día" = tiene fecha límite, 1 o más subtareas y todas están hechas.
  - "Más adelante" = fecha límite posterior al domingo de la semana en curso.
  - "Sin fecha" = no tiene fecha límite (aunque tenga subtareas).
  - "Vencidas" = `dueDate < hoy` y no está "al día".
  - Las tareas "al día" se muestran en estilo atenuado.
- "Hoy" y "esta semana" (lunes a domingo) se calculan con la zona horaria de la aplicación (sección 4).

### 3.15 Resumen del Inicio
- **Bienvenida**: saludo con el nombre y una línea con el número de tareas pendientes asignadas y cuántas **vencen hoy** ("vencen hoy" = `dueDate = hoy` en tareas asignadas al usuario, no completadas). El saludo (buenos días / tardes / noches) usa la hora local del navegador.
- **MIS TABLEROS**: los 2 a 4 tableros más recientes por actividad (`lastActivityAt`), con su número de tareas pendientes y la última actividad. Se obtienen del listado de tableros (`GET /api/boards`), no del resumen.
- **TAREAS PENDIENTES**: tareas asignadas no completadas, vencidas primero y luego por fecha límite, con tablero, estado (vencida / hoy / fecha) y progreso de subtareas.
- **Calendario del mes**: puntos por día para las tareas asignadas con `dueDate` en ese mes, con el color del tablero; se puede cambiar de mes. Los datos salen de un endpoint propio (`GET /api/dashboard/calendar?month=`).
- **Notificaciones recientes**: las más recientes del feed (§3.17), con "Ver todas".
- `GET /api/dashboard/summary` devuelve el saludo (`today`), el número de pendientes asignadas, las que vencen hoy y las tareas pendientes. No hay tarjetas de métricas adicionales (vencidas, tableros propios e invitados, avance de hoy ni barra de progreso por tablero): se retiraron del diseño.
- **Contadores del sidebar**: `GET /api/me/counters` devuelve el número de tareas asignadas abiertas (sin completadas ni "al día") y el de notificaciones sin leer.

### 3.16 Cronograma
- Muestra solo tareas del tablero con `dueDate` que no estén completadas.
- Barra de `startDate` a `dueDate`; si no hay `startDate`, un marcador de un solo día en `dueDate`.
- Validación `startDate <= dueDate` (sección 3.4).
- Cada tarea muestra su estado (vencida, hoy, esta semana, más adelante, al día) calculado por el servidor, con el mismo criterio de §3.14.
- La vista cubre por defecto 4 semanas desde el lunes de la semana en curso; el usuario puede desplazar el rango (flechas) y volver a la semana actual ("Hoy"). El rango máximo por consulta es de 92 días. Incluye una leyenda de prioridades (color e icono).
- Endpoint: `GET /api/boards/{id}/timeline`.

### 3.17 Notificaciones
- **Feed de notificaciones** dentro de la app, con contador de no leídas, marcar una o todas como leídas y paginación. Preferencias de comportamiento fijo (sin tabla ni opciones de configuración en v1).
- **Tipos**:
  - Asignación de tarea (a ti).
  - Mención (@) en un comentario.
  - Invitación recibida; invitación aceptada o rechazada (al que invitó).
  - Cambio de tu rol, haber sido removido de un tablero, transferencia de propiedad.
  - Recordatorios de vencimiento: vence mañana, vence hoy, venció.
  - Resumen semanal.
- **Reglas**:
  - No se notifica al propio autor de una acción ni las asignaciones a uno mismo.
  - Solo se notifica a miembros vigentes del tablero con cuenta activa (no a cuentas en eliminación).
  - Los recordatorios aplican a tareas asignadas, con fecha límite y no completadas ni "al día", y se envían una sola vez por tarea y fecha.
  - La notificación de invitación recibida se marca como leída cuando la invitación deja de estar pendiente.
  - Mientras la invitación está pendiente, su notificación **no aparece en el feed** (la invitación se muestra en el bloque de invitaciones de la pantalla), pero **sí cuenta** en el contador de no leídas. Al resolverse la invitación, su notificación pasa a leída y entra al feed.
- **Recordatorios y resumen semanal**: jobs programados con la zona horaria de la aplicación. El resumen semanal (lunes) es **solo una notificación dentro de la app** con contadores de la semana; no se envía por correo.
- **Tiempo real**: cada notificación nueva se entrega por `/user/queue/notifications`, junto con el contador actualizado de no leídas.
- Retención: se eliminan automáticamente las notificaciones leídas con más de 90 días y cualquier notificación con más de 180.
- Los correos del sistema siguen limitados a verificación, restablecimiento, aviso de invitación y aviso de eliminación de cuenta.

## 4. Requisitos no funcionales

- **Seguridad**: autenticación obligatoria en todos los endpoints salvo login/registro/OAuth2/verificación/restablecimiento y la lectura de avatares (archivos con nombre no adivinable); autorización a nivel de método según rol de tablero. Política de contraseña: mínimo 8 caracteres con al menos un número y máximo 72 bytes, bcrypt costo 12. Límites de frecuencia en autenticación y en la búsqueda de usuarios por correo. Sesiones revocables mediante refresh tokens persistidos.
- **Consistencia y concurrencia**: las operaciones en vivo (mover, reordenar, asignar, completar) usan "última escritura persistida gana; el cliente reconcilia con el evento recibido". Los formularios de edición (tarea y tablero) usan **control optimista por `version`** y responden **409** ante conflicto.
- **Zona horaria**: la aplicación usa una zona horaria única, configurable con la variable de entorno `APP_TIMEZONE` (zona IANA, por defecto `UTC`). Define "hoy", "esta semana" y el horario de los jobs. Las marcas de tiempo (`Instant`) se guardan en UTC.
- **Escalabilidad**: el diseño de mensajería en tiempo real debe permitir, a futuro, escalar horizontalmente el backend (broker externo tipo RabbitMQ/Redis para STOMP en vez del broker simple en memoria).
- **Disponibilidad de datos**: persistencia transaccional en PostgreSQL, migraciones versionadas.
- **Observabilidad**: logging estructurado y métricas básicas (Spring Boot Actuator).
- **Portabilidad**: entorno reproducible vía Docker/docker-compose. En local, el correo usa Mailpit.
- **Convenciones de API**: prefijo `/api` en todos los endpoints; errores con formato RFC 7807 y campo `code` (catálogo en el esquema de backend, por ejemplo `BOARD_LOAD_FAILED`); la interfaz traduce el `code`; paginación estándar `page`/`size`/`sort`; fechas ISO-8601.
- **Idioma**: la interfaz de usuario está en español. (SUPUESTO)

## 5. Stack tecnológico

| Capa | Tecnología |
|---|---|
| Lenguaje / runtime | Java 25 |
| Framework | Spring Boot 4.1.1 (Spring Web, Spring Data JPA, Spring Security, Spring WebSocket, Spring Mail, Validation, Scheduling, Actuator) |
| Base de datos | PostgreSQL (con extensión `pg_trgm` para la búsqueda) |
| Tiempo real | WebSocket + STOMP (`spring-boot-starter-websocket`) |
| Autenticación | JWT (login propio) + OAuth2 (Google) vía Spring Security OAuth2 Client; verificación y restablecimiento por correo (SMTP) |
| Límite de frecuencia | Bucket4j (en memoria en la fase inicial) |
| Documentación de API | springdoc-openapi |
| Migraciones de BD | Flyway |
| Pruebas | JUnit 5, Testcontainers (PostgreSQL), Spring Security Test |
| Contenerización | Docker + docker-compose (backend, postgres, Mailpit en local) |
| CI | GitHub Actions |
| Build | Maven |

Todas las dependencias deben usar versiones compatibles con Spring Boot 4.1.1.

## 6. Arquitectura de alto nivel

Arquitectura en capas dentro de un monolito modular:

```
Cliente (SPA) ⇄ REST API (HTTP) ⇄ Capa de servicio ⇄ Repositorios (Spring Data JPA) ⇄ PostgreSQL
Cliente (SPA) ⇄ STOMP sobre WebSocket ⇄ Capa de mensajería ⇄ Capa de servicio (mismos casos de uso)
```

- Los endpoints REST manejan operaciones CRUD estándar y devuelven el estado persistido.
- Toda mutación relevante (crear/mover/editar/borrar tarea, columna, comentario, subtarea, etiqueta, miembro) además
  de persistir vía REST, publica un evento a un topic STOMP `/topic/boards/{boardId}`
  para notificar a todos los clientes suscritos a ese tablero. La publicación ocurre después de confirmar la transacción.
- Las notificaciones personales se generan a partir de los mismos casos de uso y se entregan por `/user/queue/notifications`.
- La capa de servicio es el único punto de entrada a las reglas de negocio y permisos,
  compartida entre el controlador REST y el manejador de mensajes STOMP.
- Los trabajos programados (expiración de invitaciones, purga de cuentas, recordatorios, resumen semanal y limpieza de notificaciones) viven en el propio monolito.

## 7. Estrategia de Git y flujo de trabajo en GitHub

### 7.1 Modelo de ramas

- `main`: rama estable, siempre desplegable. Protegida.
- `develop`: rama de integración del desarrollo en conjunto. Protegida.
- `feature/<descripcion-corta>`: nuevas funcionalidades (ej. `feature/board-invitations`).
- `fix/<descripcion-corta>`: corrección de bugs (ej. `fix/task-position-race-condition`).
- `chore/<descripcion-corta>`: tareas de mantenimiento (dependencias, CI, config).
- Flujo: `feature`/`fix`/`chore` → PR a `develop` → PR de `develop` a `main` cuando hay una versión lista.

### 7.2 Protección de ramas (`main` y `develop`)

- Prohibir *push* directo; solo se integra vía Pull Request.
- Requerir que los checks de CI (build + tests + lint) pasen en verde.
- En `main`: requerir que la rama esté actualizada antes de mergear.
- Prohibir *force-push* y borrado de ambas ramas.
- (Opcional) Firma de commits (`Require signed commits`).

### 7.3 Convenciones de commits y PRs

- Se recomienda [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`,
  `chore:`, `refactor:`, `docs:`, `test:`) para mantener un historial legible y habilitar
  generación automática de changelogs.
- Cada PR debe describir el cambio, enlazar el issue/tarea relacionada y pasar la plantilla
  de PR del repositorio (checklist de pruebas, migraciones, breaking changes).
- Squash merge para los PR hacia `develop`; merge commit para `develop` → `main`, de modo que `develop` no pierda su historial.

### 7.4 CI/CD (GitHub Actions)

- **CI en cada PR** (alcance v1): compilar, correr tests unitarios e integración (Testcontainers con
  PostgreSQL), linter/formatter, y construir la imagen Docker del backend para validar el `Dockerfile`.
- **CD** (fase posterior, fuera de la v1): build de imagen, push a registry y despliegue automático
  (o manual con aprobación) al entorno correspondiente.

## 8. Fases

**Versión 1 (alcance de este documento):** autenticación completa (JWT + Google + verificación/restablecimiento por correo), usuarios (`/users/me`, avatar, ciclo de vida de la cuenta), tableros con roles, invitaciones (incluida la bandeja de pendientes), columnas, tareas (prioridad, fechas, asignado, completar/reabrir, concurrencia optimista), subtareas, comentarios con menciones, etiquetas, tiempo real del tablero, búsqueda, notificaciones (feed, menciones, recordatorios y resumen semanal in-app), Mis tareas, resumen del Inicio, cronograma y observabilidad/CI base.

**Fuera de alcance de la v1:** despliegue y CD, adjuntos en tareas, notificaciones por correo (salvo el aviso de invitación y el de eliminación de cuenta), preferencias configurables de notificación, indicador de presencia y escalado horizontal del backend.

## 9. Riesgos y supuestos

- Se asume un solo nodo de backend en la fase inicial; el broker STOMP en memoria, el límite de frecuencia en memoria, los jobs programados y el almacenamiento local de avatares no son aptos para múltiples instancias sin broker externo (RabbitMQ/Redis), almacenamiento compartido y un mecanismo de bloqueo de jobs.
- El control de concurrencia optimista (`version` + 409) aplica a los formularios de edición; las operaciones en vivo siguen "última escritura gana".
- El envío de correo (verificación, restablecimiento, aviso de invitación, aviso de eliminación de cuenta) requiere SMTP configurado; sin él no hay registro LOCAL completo.
- La expiración de invitaciones, la purga de cuentas, los recordatorios y el resumen semanal dependen de jobs programados del backend y de una zona horaria configurada correctamente.
- Durante una caída de conexión STOMP se pierden eventos; el cliente debe recargar el estado al reconectar.
