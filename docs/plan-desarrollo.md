# Plan de desarrollo — Backend TaskFlow

**Fecha:** 18 Oct 2026 · **Base:** `trd.md`, `esquema-backend.md`, `contratos-api.md`, `adrs.md` y `backlog.md` vigentes a esa fecha.
**Alcance:** solo backend (S0 y E1–E13). El frontend (E14) tiene su propio plan; aquí solo se indica qué historias de backend lo desbloquean.
**Cómo se usa:** las fases van en orden de dependencias técnicas. Dentro de cada fase, las historias van en el orden en que se ejecutan. Al terminar una historia se marca su casilla (`- [x]`). Los criterios de aceptación están en `backlog.md`: aquí solo hay notas técnicas y pruebas clave.

---

## 1. Decisiones de la entrevista

| Tema | Decisión |
|---|---|
| Orden de entrega | **Núcleo colaborativo primero:** acceso mínimo → tableros → kanban en vivo → miembros e invitaciones → Inicio y notificaciones programadas → cuenta completa → cierre. |
| Infraestructura transversal | Cada pieza entra completa **justo antes de su primer consumidor** (ver §2). |
| E3-1 ↔ E4-2 | E3-1 se implementa en F2 sin el lote de invitaciones (si llega no vacío, responde `VALIDATION_FAILED`). Su casilla se marca cuando E4-2 añade el lote reusando `InvitationService`. Es la **única dependencia hacia delante aceptada** (Hallazgo H-09). |
| Historias paraguas (E10-2, E12-2, E12-4, E13-4) | El mecanismo base va en la primera historia que lo necesita. Cada historia emite sus eventos y notificaciones y valida sus límites (lo exige la DoD). La casilla del paraguas es una historia de **cierre**: completa lo que no cubre ninguna otra y añade una prueba de cobertura. |
| Pruebas | Tres niveles: captura de eventos tras el commit en cada historia, STOMP real solo donde importa el transporte, y matriz de roles parametrizada (ver §3). |
| Seed (S0-5) | Seeder Java con perfil `dev` que escribe por repositorios (no dispara eventos, correos ni rate limits). Arranca en F2, crece por fase y se cierra en F6. |
| Reloj | Bean `java.time.Clock` en todo cálculo de "hoy", vencimientos y expiraciones. Se fija en las pruebas. En `dev` el seed usa fechas relativas a hoy, y `app.clock.fixed` (opcional, solo `dev`) reproduce las capturas del 16 OCT 2026. |
| Lint | Spotless con palantir-java-format; `spotless:check` corre en `verify`. |
| Repositorio | S0-1 empieza con `git init`. El commit inicial va directo a `main` (única excepción), después se crea `develop` y todo entra por PR. La protección de ramas la configuras tú (o se hace con `gh`, con tu autorización). |
| Historias de interfaz | E1-7, E10-3, E10-4 y E13-8 van en F9 con su soporte de backend y se cierran con E14-10. En el resto, la casilla cubre los AC de servidor; los de pantalla quedan para E14-10. |

## 2. Orden de lo transversal (por qué así)

Objetivo: que ningún servicio tenga que reabrirse para "enchufar" permisos, eventos o notificaciones.

1. **Reloj, límites y errores (F0: S0-6, S0-4).** Todo servicio lanza `ApiException(ErrorCode)` y lee "hoy" del `Clock` desde la primera línea. Introducirlos después obligaría a tocar cada servicio.
2. **Utilidad de posiciones ADR-001 (F2, en E3-1).** Código puro (anexar, insertar por índice destino, rebalancear) con pruebas unitarias. Entra en E3-1 porque `createDefaultColumns` ya la usa; después la reutilizan columnas (E5), tareas (E6) y subtareas (E7) sin cambios.
3. **Evaluador de permisos por tablero (F2, en E3-3).** Es el primer endpoint con rol de tablero. Lleva la matriz completa del TRD §3.2 desde el inicio (acciones como enum; no miembro → 404), así que las historias siguientes solo añaden la anotación y su prueba por rol.
4. **Publicador de eventos tras el commit (F2: E10-1 y luego E3-4).** E10-1 deja listo el transporte STOMP (CONNECT, suscripción) justo después de E3-3. E3-4 crea el `BoardEventPublisher` con el envelope y `@TransactionalEventListener(AFTER_COMMIT)`. Desde ahí cada historia que muta datos del tablero publica y prueba su evento en el mismo PR.
5. **Notificaciones (F3: E13-1, E13-2, E13-3).** Al inicio de F3, porque E6-1 es la primera historia que notifica. E13-2 sube con ellas porque E13-3 incluye `NotificationsRead`, que necesita los endpoints de lectura.
6. **Capacidad de columna con bloqueo de fila (F3, en E6-1).** `ColumnCapacityGuard` (`SELECT … FOR UPDATE` sobre la columna) lo reutilizan E6-3, E6-8 y E5-4.
7. **Scheduler (F5, en E4-5).** Es el primer job: base `@Scheduled`, protección contra solapamiento y uso del `Clock`. La reutilizan E13-5/6/7, E2-7 y el cierre E12-2.

## 3. Estrategia de pruebas

- **Integración por historia:** Testcontainers con **un solo contenedor PostgreSQL** compartido por toda la suite, y un constructor de datos de prueba común (usuarios, tablero, miembros por rol, columnas, tareas). Cada evento se verifica capturando lo que el publicador envía tras el commit (envelope + payload de `contratos-api.md` §5), y se comprueba que **no se publica nada si hay rollback**.
- **STOMP real** (cliente WebSocket de prueba) solo en E10-1, E10-5, E13-3 y una prueba de humo por familia de eventos (en E3-4 y en el cierre E10-2).
- **Permisos:** prueba parametrizada por rol en cada operación con permisos: OWNER, ADMIN, MEMBER asignado, MEMBER no asignado y no miembro (→ 404).
- **Concurrencia:** las pruebas de carrera (límites con `FOR UPDATE`) usan dos hilos con barrera y transacciones reales; nunca `@Transactional` en el test.
- **Correo:** un `JavaMailSender` de prueba que captura los mensajes. Mailpit solo para la verificación manual.
- **Jobs:** se invoca el método del job directamente con reloj fijo; se ejecuta dos veces para probar la idempotencia.

---

## 4. Fases

### F0 — Esqueleto (Sprint 0)
**Objetivo:** el proyecto compila, arranca contra Postgres con `V1` aplicado, responde errores RFC 7807 y publica Swagger; el CI está en verde.
**Depende de:** nada. **Leer:** TRD §5 y §7; esquema §1, §2, §7–§10; contratos §1–§2; ADR-004, 006, 010.

- [x] S0-1 — Repositorio, CI y dependencias compatibles con Boot 4.1.1
  - `git init`, commit inicial a `main`, rama `develop`. Workflow de GitHub Actions: `./mvnw verify` en cada PR.
  - Se añaden los starters del stack **verificando cada uno contra Boot 4.1.1** (nombres modularizados, Jackson 3, versiones de springdoc, Bucket4j y Testcontainers compatibles). Spotless + palantir.
  - Pruebas: el contexto arranca con Testcontainers.
- [x] S0-2 — Docker de desarrollo
  - `Dockerfile` (Java 25) y `docker-compose.yml` según esquema §8, con `.env.example`. El CI construye la imagen (TRD §7.4). La cookie sin `Secure` en local se configura en E1-3, cuando exista la cookie; las propiedades `app.*` las enlaza la historia que las usa.
- [ ] S0-3 — Paquetes de esquema §2 y `V1__init.sql`
  - Todas las tablas v1, `pg_trgm`, CHECK de ADR-011 y de `taskLimit`, únicas de posición **diferibles**, índices de §9, `CASCADE`/`SET NULL` según §1. Las entidades JPA se crean en la historia que las usa (no aquí).
  - Pruebas: Flyway aplica en limpio; intercambio de dos posiciones en una transacción (diferibilidad); CHECK de tarea completada.
- [ ] S0-6 — Zona horaria, límites y reloj
  - `@ConfigurationProperties` con `APP_TIMEZONE`, límites de ADR-010 y los configurables de ADR-004; bean `Clock`; `app.clock.fixed` solo en `dev`.
  - Pruebas: valores por defecto, valores sobrescritos por entorno, semana lunes–domingo en el borde de medianoche.
- [ ] S0-4 — Errores y convenciones de API
  - `ErrorCode` (= catálogo de contratos §2, con HTTP y campos extra), `@RestControllerAdvice` → `ProblemDetail` con `code` y `errors[]`, `PageResponse`, prefijo `/api`, `/swagger`, CORS limitado a `FRONTEND_URL` con credenciales, Bean Validation → `VALIDATION_FAILED`.
  - Pruebas: forma de 400/404/409; preflight de CORS.
- [ ] E12-3 — Observabilidad
  - Actuator (health, metrics), logs estructurados con `requestId` en MDC (cabecera `X-Request-Id`); filtro que nunca registra cuerpos de `/api/auth/**`.

**Salida demostrable:** PR con CI verde. `docker compose up -d` → `GET /actuator/health` = `UP`, `/swagger` carga y `GET /api/no-existe` responde RFC 7807 con `code`.
**Riesgos:** compatibilidad de dependencias con Boot 4 (se resuelve en S0-1, no después). `V1` es definitiva una vez cerrada S0-3: revisarla contra esquema §1 y §9 antes del merge. Testcontainers necesita Docker Desktop encendido.

### F1 — Acceso mínimo
**Objetivo:** registrarse, verificar el correo, entrar, renovar y cerrar sesión, y ver y editar el perfil. El frontend ya puede construir el shell.
**Depende de:** F0. **Leer:** TRD §3.9–3.10; esquema §1 (Users y tokens), §5; contratos §3 (`UserMe`), §4 Auth/Users; ADR-002, 003, 007; `plantillas-correo.md`.

- [ ] E12-1 — Correo SMTP y las 4 plantillas
  - `MailService` con las 4 plantillas y enlaces basados en `FRONTEND_URL`. Se envía en `AFTER_COMMIT`; un fallo solo se registra en el log.
  - Pruebas: render de cada plantilla; un fallo SMTP no revierte la operación.
- [ ] E1-1 — Registro LOCAL con verificación (**resolver H-02 antes**)
  - Entidad `User`, bcrypt 12, política de 8 caracteres a 72 bytes con un número; token de 24 h guardado solo como hash SHA-256.
  - Pruebas: contraseña de 72 bytes con caracteres multibyte, 409 por duplicado, token guardado con hash, correo tras el commit.
- [ ] E1-2 — Verificación de correo sin bloqueo
  - Pruebas: token válido, usado y expirado (reloj fijo).
- [ ] E1-3 — Login, refresh persistido y logout
  - `JwtService`, `JwtAuthFilter`, Security sin estado y sin roles globales; cookie `refresh_token` con `Path=/api/auth`; familia de rotación con `replacedById`.
  - Pruebas: rotación; reuso → 401 `TOKEN_ALREADY_USED` y todas las sesiones revocadas; atributos de la cookie; access token expirado → `UNAUTHENTICATED`.
- [ ] E1-6 — Rate limiting
  - Bucket4j en memoria con las 3 políticas de ADR-002 definidas aquí; se aplican a login y al reenvío de verificación. E4-2 y E1-5 aplican las de lookup y correo a sus endpoints.
  - Pruebas: el 6.º login → 429 con `Retry-After`; cada política con reloj controlado.
- [ ] E2-1 — Ver y editar perfil (**resolver H-06 antes**)
  - Pruebas: cambio de correo (queda sin verificar y se envía el correo), `EMAIL_ALREADY_REGISTERED`, límites de ADR-004.

**Salida demostrable:** con Swagger o curl: registro → correo en Mailpit (`:8025`) → verificar → login → refresh (la cookie rota) → reusar la cookie vieja da 401 y luego falla también la sesión nueva → 6 logins seguidos dan 429.
**Riesgos:** configuración de Spring Security 7; cookie `Secure` sobre HTTP en local; H-02.

### F2 — Tableros, permisos y tiempo real base
**Objetivo:** CRUD de tableros con permisos por rol y los primeros eventos STOMP publicados tras el commit.
**Depende de:** F1 (JWT). **Leer:** TRD §3.1, §3.2, §3.8; esquema §1 (Board, BoardMember, BoardColumn, Tag), §3 Boards, §4; contratos §3 (BoardSummary, BoardDetail), §4 Boards, §5; ADR-001, 012, 016.

- [ ] E3-1 — Crear tablero (la casilla se marca con E4-2)
  - `Board` y `BoardMember` OWNER en la misma transacción; paleta de 8 colores; `createDefaultColumns`; etiquetas iniciales (paleta de 6, únicas sin distinguir mayúsculas). **Introduce la utilidad de posiciones de ADR-001.**
  - Pruebas: unitarias de la utilidad (punto medio, rebalanceo cuando el hueco baja de 1); color fuera de paleta → 400; lote de invitaciones no vacío → 400 hasta E4-2.
- [ ] E3-3 — Detalle de tablero
  - **Introduce el evaluador de permisos** (§2.3). `today` sale del `Clock`; columnas con `taskCount`; tareas pendientes (en las pruebas se crean por repositorio hasta F3).
  - Pruebas: por rol; no miembro e inexistente → 404; sin N+1 (número de consultas acotado).
- [ ] E3-2 — Listar tableros
  - Orden limitado a `lastActivityAt`, `updatedAt` y `name`; los contadores excluyen completadas.
  - Pruebas: filtro `role`, orden, campo de orden no permitido → 400.
- [ ] E4-1 — Listar miembros
- [ ] E10-1 — STOMP autenticado por tablero
  - `/ws`; JWT en CONNECT; `Principal` = `userId`; rechaza tokens con claim `recovery` (la prueba acuña uno; E2-5 lo emite después); SUBSCRIBE validado con el evaluador.
  - Pruebas (STOMP real): sin token, token expirado o de recuperación → rechazo; suscripción a un tablero ajeno → rechazo.
- [ ] E3-4 — Editar tablero
  - **Introduce `BoardEventPublisher`** (envelope y `AFTER_COMMIT`). Solo `PUT` incrementa `version`; 409 con `currentVersion` y `current`.
  - Pruebas: conflicto, solo Owner, evento capturado tras el commit y ninguno en rollback; humo STOMP de `BoardUpdated`.
- [ ] E3-5 — Eliminar tablero
  - Cascada en BD y `BoardDeleted` (el corte del topic llega con E10-5).

**Seed:** S0-5 arranca aquí con usuarios del diseño, 4 tableros, membresías y columnas.
**Salida demostrable:** login como Jorge (seed) → crear tablero con columnas por defecto → detalle → editar desde dos sesiones y ver el 409 → un cliente STOMP suscrito recibe `BoardUpdated` → un usuario que no es miembro recibe 404.
**Riesgos:** orden de interceptores de STOMP con Spring Security 7; el evaluador debe servir igual desde `@PreAuthorize` en REST y en STOMP.

### F3 — Columnas, etiquetas y tareas en vivo
**Objetivo:** kanban usable en tiempo real: columnas, etiquetas y tareas (crear, editar, mover, asignar) con límites y notificación de asignación.
**Depende de:** F2. **Leer:** TRD §3.3, §3.4, §3.7, §3.17; esquema §1 (BoardColumn, Task, Tag, TaskTag, Notification), §3 Columns/Tasks/Tags y reglas por operación; contratos §3–§5; ADR-001, 008, 010, 011, 012.

- [ ] E13-1 — Modelo y servicio de notificaciones
  - `NotificationService` se ejecuta dentro de la transacción del caso de uso; excluye al actor, a no miembros y a cuentas no `ACTIVE`; el `payload` lleva una copia de los textos; admite `dedupeKey`.
  - Pruebas: cada exclusión; si el caso de uso hace rollback, no queda notificación.
- [ ] E13-2 — Feed y contador
  - Por defecto el feed excluye las `INVITATION_RECEIVED` pendientes, y `unread-count` sí las cuenta (en las pruebas, la invitación se crea por repositorio).
  - Pruebas: cada usuario solo ve las suyas (las ajenas → 404); paginación; leer todas.
- [ ] E13-3 — Entrega en tiempo real
  - `convertAndSendToUser` tras el commit, con `unreadCount`; `NotificationsRead` al leer.
  - Pruebas (STOMP real): dos sesiones del mismo usuario reciben ambos eventos; otro usuario no recibe nada.
- [ ] E5-1 — CRUD de columnas
  - Máximo 12 con `FOR UPDATE` sobre el tablero; posición al final. **Introduce la actualización de `lastActivityAt` por consulta directa** (ADR-012) para toda mutación hija.
  - Pruebas: por rol; la 13.ª columna → 409; la `version` del tablero no cambia.
- [ ] E5-2 — Reordenar columnas
  - Pruebas: mover al inicio, en medio y al final; rebalanceo forzado; `order[]` del evento.
- [ ] E9-1 — CRUD de etiquetas del tablero
  - Pruebas: los 3 roles pueden; `TAG_DUPLICATE` aunque cambien las mayúsculas; `taskCount`.
- [ ] E6-1 — Crear tarea (**resolver H-07 antes**)
  - **Introduce `ColumnCapacityGuard`.** Notifica `TASK_ASSIGNED` (no a uno mismo); `TaskCreated`.
  - Pruebas: por rol; columna llena → 409 con `columnId` y `taskLimit`; `DATE_RANGE_INVALID`; el asignado recibe la notificación y el autor no.
- [ ] E6-7 — Detalle de tarea
  - `TaskDetailDto`; va antes de E6-2 porque el 409 devuelve `current`.
- [ ] E6-2 — Editar tarea con control optimista
  - Pruebas: 409 con `currentVersion` y `current`; MEMBER asignado frente a no asignado; `TASK_FIELD_FORBIDDEN` con `fields[]`.
- [ ] E6-6 — Etiquetas de la tarea
  - `TaskTagChanged` solo si el conjunto cambia, además de `TaskUpdated`.
- [ ] E6-3 — Mover y reordenar tareas
  - Las columnas se bloquean en orden de id para evitar interbloqueos; no toca `version`; una tarea completada (creada por repositorio) → `TASK_ALREADY_COMPLETED`.
  - Pruebas: mover a una columna llena → 409; MEMBER solo mueve las suyas; `order[]`; la `version` no cambia.
- [ ] E6-4 — Asignar tarea
  - Pruebas: `ASSIGNEE_NOT_MEMBER`; un MEMBER solo se desasigna a sí mismo; no se notifica la autoasignación; la `version` no cambia.

**Salida demostrable:** dos clientes STOMP (Jorge, Owner, y Marco, Member, del seed) en el mismo tablero. Jorge crea una tarea asignada a Marco → Marco recibe `TaskCreated` y `NotificationCreated`. Marco mueve su tarea → Jorge recibe `TaskMoved` con `order[]`. Una edición simultánea produce 409 con `current`. Mover a "En curso" (límite 4, llena) → 409.
**Riesgos:** fase grande; pruebas de carrera inestables; únicas diferibles y orden de flush de Hibernate al rebalancear.

### F4 — Ciclo de la tarea, subtareas, comentarios y búsqueda
**Objetivo:** completar y reabrir, subtareas, comentarios con menciones, cascadas y búsqueda.
**Depende de:** F3. **Leer:** TRD §3.4–3.7, §3.13; esquema §1 (Subtask, Comment, CommentMention), §3, §9; contratos §3–§5; ADR-001, 004, 010, 011, 013.

- [ ] E6-5 — Eliminar tarea
- [ ] E6-8 — Completar y reabrir tarea
  - Al completar no se renumera la columna; reabrir pasa por el guard de capacidad.
  - Pruebas: CHECK de BD; reabrir hacia una columna llena → 409; `TASK_ALREADY_COMPLETED` y `TASK_NOT_COMPLETED`; la `version` no cambia.
- [ ] E5-4 — Límite de tareas por columna
  - Va después de E6-8 porque su AC incluye reabrir.
  - Pruebas: `COLUMN_LIMIT_BELOW_CURRENT` con `taskCount`; **carrera de dos movimientos hacia una columna con un solo hueco** (uno termina en 409).
- [ ] E6-9 — Tareas completadas del tablero
- [ ] E9-2 — Eliminar etiqueta
  - `affectedTaskIds` se calcula antes de borrar; `TaskTagChanged` por cada tarea afectada.
- [ ] E7-1 — CRUD de subtareas
  - Máximo 30 con `FOR UPDATE` sobre la tarea; posición `max + 1000`.
- [ ] E7-2 — Marcar subtarea hecha o pendiente
- [ ] E8-1 — Comentar
- [ ] E8-2 — Editar y eliminar comentarios
  - Pruebas: `canEdit` y `canDelete` por rol.
- [ ] E8-3 — Menciones
  - Parser de `@[Nombre](userId)`; los 2000 caracteres se cuentan como texto visible; al editar solo notifican las menciones nuevas.
- [ ] E5-3 — Eliminar columna en cascada
  - Pruebas: cascada columna → tareas → subtareas → comentarios → menciones; las notificaciones quedan con `taskId` nulo (`SET NULL`).
- [ ] E3-6 — Búsqueda en el tablero
  - Pruebas: coincidencia parcial sin distinguir mayúsculas; 20 resultados por tipo; `q` < 2 → 400; solo tableros propios.

**Salida demostrable:** completar una tarea la saca del kanban y la muestra en Completadas; reabrirla hacia una columna llena da 409; mencionar a Ana le entrega `NotificationCreated`; eliminar una columna borra todo en cascada; buscar «lanz» devuelve tareas, etiquetas y comentarios.
**Riesgos:** conteo del texto visible con menciones; rendimiento de `ILIKE '%q%'` (comprobar que usa el índice GIN).

### F5 — Miembros e invitaciones (colaboración completa)
**Objetivo:** invitar, aceptar, cambiar roles, quitar, salir y transferir, con eventos, notificaciones y corte del topic.
**Depende de:** F4 (desasignar tareas y comentarios). **Leer:** TRD §3.1, §3.2, §3.12, §3.17; esquema §1 (BoardMember, BoardInvitation), §3 Members/Invitations, §4, §6; contratos §3–§5; ADR-005, 008.

- [ ] E4-2 — Invitar por correo exacto (**y cerrar E3-1**; resolver H-01 antes)
  - Lookup con 5 estados y `boardId` opcional, política de lookup de E1-6, correo de aviso, `INVITATION_RECEIVED`. Añade el lote de `POST /api/boards` con `InvitationService` → marcar E3-1.
  - Pruebas: cada estado del lookup y cada error; volver a invitar tras un rechazo o una cancelación; lote mixto; el 11.º lookup → 429.
- [ ] E4-3 — Bandeja y respuesta a invitaciones
  - Pruebas: un tercero recibe 404; aceptar dos veces → `INVITATION_NOT_PENDING`; vencida antes de que corra el job → `INVITATION_EXPIRED`; `INVITATION_RECEIVED` pasa a leída.
- [ ] E4-4 — Cancelar invitación
- [ ] E4-6 — Cambiar rol
- [ ] E4-7 — Eliminar miembro
  - Pruebas: un Admin solo quita a un MEMBER; un `TaskAssigneeChanged` por cada tarea desasignada.
- [ ] E4-8 — Salir del tablero
  - Si es el único miembro, reutiliza la eliminación de E3-5.
- [ ] E10-5 — Cierre de acceso al tablero
  - Registro de suscripciones (usuario, tablero, sesión) e interceptor de salida: el afectado recibe su `MemberRemoved`, `MemberLeft` o `BoardDeleted` y después nada más.
  - Pruebas (STOMP real): después del corte no llega ningún evento; el resto de miembros sigue recibiendo.
- [ ] E4-9 — Transferir propiedad
  - El índice único parcial de OWNER no es diferible: primero se degrada al Owner actual y después se promueve al nuevo, en la misma transacción.
- [ ] E4-5 — Expiración de invitaciones
  - **Introduce la base del scheduler** (§2.7).
  - Pruebas: dos ejecuciones dan el mismo resultado.
- [ ] E13-4 — Notificaciones de tablero (cierre)
  - Prueba de cobertura: cada tipo de tablero de TRD §3.17 se genera, y `INVITATION_RECEIVED` pasa a leída en las 4 salidas (aceptar, rechazar, cancelar, expirar).
- [ ] E10-2 — Catálogo de eventos (cierre)
  - El enum de tipos coincide con contratos §5 y cada tipo tiene al menos una prueba de publicación; humo STOMP por familia.

**Salida demostrable:** Jorge invita a Lucía → aviso en Mailpit → Lucía ve en vivo la invitación y su notificación → acepta → Jorge recibe `MemberAdded` e `INVITATION_ACCEPTED` → Jorge la quita → Lucía recibe `MemberRemoved` y deja de recibir eventos. Después de transferir la propiedad, Jorge queda como Admin.
**Riesgos:** corte de suscripciones con el broker simple; ráfaga de eventos al desasignar muchas tareas.

### F6 — Inicio, Mis tareas, cronograma y notificaciones programadas
**Objetivo:** las vistas personales calculadas en el servidor y los jobs de recordatorios.
**Depende de:** F5. **Leer:** TRD §3.14–3.17; esquema §3 Dashboard, §6; contratos §3–§4 (Mis tareas y resumen, Notificaciones); ADR-005, 006, 008, 011, 015.

- [ ] E11-3 — Mis tareas
  - **Introduce un único cálculo de `bucket`**, reutilizado en E11-1 y E11-4.
  - Pruebas: los 5 grupos con reloj fijo en lunes, en domingo y en el borde de medianoche de `APP_TIMEZONE`; "sin fecha" al final, por prioridad; nunca tareas de tableros ajenos.
- [ ] E11-1 — Resumen del Inicio y contadores
- [ ] E11-2 — Calendario del mes
- [ ] E11-4 — Cronograma
  - Pruebas: rango por defecto de 4 semanas desde el lunes; más de 92 días → 400.
- ~~E11-5~~ — Retirada el 18 Oct 2026; no hay trabajo.
- [ ] E13-5 — Recordatorios de vencimiento
  - Pruebas: dos ejecuciones el mismo día no duplican; cambiar `dueDate` vuelve a notificar; excluye tareas completadas, "al día" y cuentas no `ACTIVE`.
- [ ] E13-6 — Resumen semanal
- [ ] E13-7 — Retención de notificaciones
- [ ] S0-5 — Seed de datos de prueba (cierre: ya hay notificaciones de todos los tipos)

**Salida demostrable:** con el seed y `app.clock.fixed=2026-10-16`, el Inicio, el calendario, Mis tareas y el cronograma coinciden con las capturas del diseño. Ejecutar el job de recordatorios dos veces deja una sola notificación por tarea.
**Riesgos:** diferencias de un día en los bordes de semana o zona horaria si algún endpoint no usa el cálculo único.

### F7 — Cuenta completa
**Objetivo:** restablecer y cambiar la contraseña, avatar, Google y el ciclo de eliminación y recuperación de cuenta.
**Depende de:** F6 (la purga elimina notificaciones y usa el scheduler). **Leer:** TRD §3.9–3.11; esquema §1 Users/tokens, §5, §6; contratos §4 Auth/Users; ADR-003, 007, 009, 014; `plantillas-correo.md`.

- [ ] E1-5 — Olvidé mi contraseña y restablecer
  - Pruebas: respuesta idéntica exista o no la cuenta; token de 60 min; revoca todas las sesiones; funciona en `PENDING_DELETION`.
- [ ] E2-2 — Cambiar contraseña (solo LOCAL)
- [ ] E2-3 — Avatar
  - `AvatarStorage` con implementación local; validación por contenido real del archivo, no solo `Content-Type`; nombre aleatorio; se borra el archivo anterior.
- [ ] E1-4 — OAuth2 con Google (**resolver H-03 y H-04 antes**)
  - Pruebas con `oauth2Login()` de Spring Security Test, sin credenciales reales en CI.
- [ ] E2-4 — Solicitar eliminación de cuenta
- [ ] E2-5 — Sesión y vista de recuperación
  - Login, Google y `refresh` emiten el claim `recovery`; el filtro permite solo los 4 endpoints (el WebSocket ya lo rechaza desde E10-1).
- [ ] E2-6 — Recuperar cuenta
- [ ] E2-7 — Purga programada (**resolver H-08 antes**)
  - Pruebas: con el reloj adelantado 31 días, anonimiza, conserva los comentarios, elimina los tableros de un solo miembro y es idempotente.

**Salida demostrable:** solicitar la eliminación → el login da sesión de recuperación (solo `/me`; el resto 403) → recuperar → `refresh` da sesión normal. Con el reloj adelantado 31 días, `restore` responde 409 y la purga anonimiza la cuenta.
**Riesgos:** la purga toca muchas tablas; probar el login con Google a mano requiere credenciales.

### F8 — Cierre de calidad
**Objetivo:** cerrar los paraguas restantes y auditar.
**Depende de:** F7. **Leer:** ADR-004, ADR-005; esquema §6.

- [ ] E12-2 — Jobs programados (cierre)
  - Añade la limpieza de tokens (esquema §6) y revisa los 6 jobs: horario, zona horaria, sin solapamiento, idempotencia y pruebas.
- [ ] E12-4 — Validación de límites de campos (cierre)
  - Prueba parametrizada para cada campo de ADR-004: el valor en el límite se acepta y uno más da `VALIDATION_FAILED`.

**Salida demostrable:** `./mvnw clean verify` en verde; OpenAPI revisado contra `contratos-api.md`; todas las casillas de F0–F7 marcadas.

### F9 — Historias de interfaz (soporte de backend; se cierran con E14-10)
- [ ] E1-7 — Términos y privacidad. Backend: nada hasta resolver H-05.
- [ ] E10-3 — Estados de conexión (LiveChip). Backend: E10-1.
- [ ] E10-4 — Reconciliación de la UI. Backend: el autor recibe su propio evento, `eventId` es único, `TaskUpdated` trae `version` y `GET /api/boards/{id}` permite recargar al reconectar.
- [ ] E13-8 — Pantalla de Notificaciones. Backend: E13-2 y E4-3; el `payload` permite mostrar "Ya no está disponible".

---

## 5. Trazabilidad (historia → fase)

| Épica | Historias |
|---|---|
| S0 | S0-1 F0 · S0-2 F0 · S0-3 F0 · S0-4 F0 · S0-5 F6 · S0-6 F0 |
| E1 | E1-1 F1 · E1-2 F1 · E1-3 F1 · E1-4 F7 · E1-5 F7 · E1-6 F1 · E1-7 F9 |
| E2 | E2-1 F1 · E2-2 F7 · E2-3 F7 · E2-4 F7 · E2-5 F7 · E2-6 F7 · E2-7 F7 |
| E3 | E3-1 F2 (se cierra con E4-2) · E3-2 F2 · E3-3 F2 · E3-4 F2 · E3-5 F2 · E3-6 F4 |
| E4 | E4-1 F2 · E4-2 F5 · E4-3 F5 · E4-4 F5 · E4-5 F5 · E4-6 F5 · E4-7 F5 · E4-8 F5 · E4-9 F5 |
| E5 | E5-1 F3 · E5-2 F3 · E5-3 F4 · E5-4 F4 |
| E6 | E6-1 F3 · E6-2 F3 · E6-3 F3 · E6-4 F3 · E6-5 F4 · E6-6 F3 · E6-7 F3 · E6-8 F4 · E6-9 F4 |
| E7 | E7-1 F4 · E7-2 F4 |
| E8 | E8-1 F4 · E8-2 F4 · E8-3 F4 |
| E9 | E9-1 F3 · E9-2 F4 |
| E10 | E10-1 F2 · E10-2 F5 · E10-3 F9 · E10-4 F9 · E10-5 F5 |
| E11 | E11-1 F6 · E11-2 F6 · E11-3 F6 · E11-4 F6 · E11-5 retirada |
| E12 | E12-1 F1 · E12-2 F8 · E12-3 F0 · E12-4 F8 |
| E13 | E13-1 F3 · E13-2 F3 · E13-3 F3 · E13-4 F5 · E13-5 F6 · E13-6 F6 · E13-7 F6 · E13-8 F9 |

## 6. Protocolo de ejecución por historia

1. Antes de empezar, revisa en §7 si un hallazgo la bloquea. Si es así, resuélvelo contigo primero.
2. Sigue "Cómo trabajar una historia" de `CLAUDE.md` (rama desde `develop`, modo plan, pruebas, DoD, PR con squash). Lee solo las secciones del **Leer** de la fase y el AC del backlog.
3. Si la historia introduce una pieza de §2, esa pieza y sus pruebas van primero en el PR.
4. Cada operación con permisos lleva su prueba por rol, y cada mutación de tablero su prueba de evento (§3).
5. Al hacer el merge, marca la casilla aquí. Si cambió un contrato, los documentos se actualizan en el mismo PR.

## 7. Hallazgos (pendientes de tu decisión; no se resolvieron en silencio)

| ID | Hallazgo | Propuesta | Bloquea |
|---|---|---|---|
| H-01 | `esquema-backend.md` §3 dice que `lookup` devuelve 4 estados con `boardId`. `contratos-api.md` §4, TRD §3.12 y E4-2 añaden `SELF` y hacen `boardId` opcional. | Alinear esquema §3 con contratos (manda el TRD). | E4-2 |
| H-02 | `POST /api/auth/verify-email/resend` no tiene cuerpo y A-16 lo define con sesión. Pero E1-1 pide reenviar desde "revisa tu correo", y el registro no abre sesión: sin sesión no se sabe a quién reenviar. | Aceptar también `{ "email" }` sin sesión, con respuesta uniforme (como `forgot-password`) y el límite de 3 por 10 min. | E1-1 |
| H-03 | `ACCOUNT_PROVIDER_MISMATCH` es un 409 JSON, pero el login con Google es una redirección del navegador. No está definido cómo recibe el error el frontend. | Redirigir a `FRONTEND_URL/login?error=ACCOUNT_PROVIDER_MISMATCH&provider=LOCAL` (sin tokens en la URL) y documentarlo en contratos §4. | E1-4 |
| H-04 | Esquema §5 y E1-4 dicen "crea/vincula el usuario por `googleId`/email", y TRD §3.9 y `CLAUDE.md` dicen "no se vinculan cuentas". | Redactar: se busca por `googleId`; si el correo ya existe con LOCAL → `ACCOUNT_PROVIDER_MISMATCH`. | E1-4 |
| H-05 | TRD §3.9 exige aceptar los términos, pero `POST /api/auth/register` no tiene ningún campo para ello y está pendiente decidir si se guarda la aceptación. | Decidir si el servidor exige `acceptedTerms: true` y si guarda la fecha de aceptación (implicaría una columna en `users`). | E1-7 (y el contrato de E1-1 si se añade) |
| H-06 | No está definido qué responde el servidor si una cuenta GOOGLE envía `email` en `PUT /api/users/me` o llama a `PUT /api/users/me/password`. | `FORBIDDEN` en ambos casos (o ignorar `email`), documentado en contratos. | E2-1, E2-2 |
| H-07 | No está definido el código de error para un `tagId` de otro tablero (o inexistente) en una tarea. | `VALIDATION_FAILED` con `errors[{field:"tagIds"}]`. | E6-1 |
| H-08 | La purga quita membresías y asignaciones y cancela invitaciones, pero no dice si emite eventos (`MemberRemoved`, `TaskAssigneeChanged`, `InvitationCanceled`) ni qué pasa con las notificaciones de otros. | Emitir los mismos eventos que E4-7 y E4-4, sin notificaciones. | E2-7 |
| H-09 | E3-1 incluye el lote de invitaciones, que depende de E4-2 (dependencia circular). Ya se decidió cerrar E3-1 con E4-2. | Mover ese AC de E3-1 a E4-2 en `backlog.md` (necesita tu permiso). | — |
| H-10 | E10-2, E12-2, E12-4 y E13-4 repiten AC de otras historias. La limpieza de tokens solo existe dentro de E12-2. | Reescribir sus AC como historias de cierre o auditoría, como en este plan. | — |
| H-11 | S0-5 fija "hoy = 16 OCT 2026", y ADR-006 hace que "hoy" lo calcule el servidor. Ya se decidió usar fechas relativas y un reloj fijo opcional en `dev`. | Reescribir el AC de S0-5 en esos términos. | — |
| H-12 | `cambios-interfaz-para-plan.md` (A-18) dice que `ColumnUpdated` mantiene los conteos al día, pero TRD §3.3 y contratos §5 solo lo emiten al cambiar `taskLimit`. | Aclarar en contratos §5 que el cliente deriva `taskCount` de los eventos de tarea (o emitir `ColumnUpdated` también al mover, completar y reabrir). | E10-4 |
| H-13 | Esquema §2 nombra la clase principal `TaskFlowAppApplication`, y el repositorio tiene `TaskflowBackendApplication`. | Conservar la del repositorio y corregir el esquema. | — |
| H-14 | `cambios-interfaz-para-plan.md` no figura en la tabla de documentos de `CLAUDE.md` y dice que este plan "lo creará el usuario por aparte". | Añadirlo a la tabla como registro histórico o moverlo a `docs/archivo/`. | — |
| H-15 | La petición de este plan decía que el stack del frontend no estaba definido, pero ADR-017 ya lo fija (React + Vite + TypeScript). | Solo informativo; no afecta al backend. | — |
