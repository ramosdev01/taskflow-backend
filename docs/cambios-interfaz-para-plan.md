# Cambios que pide la interfaz — qué falta en el plan para alinear front y back

**Fecha:** 18 Oct 2026 · **Origen:** el rediseño de `docs/diseño-interfaz.pen` (58 pantallas) comparado contra `trd.md`, `contratos-api.md`, `esquema-backend.md`, `especificaciones-interaccion.md` y `backlog.md`.
**Alcance:** lista lo que faltaba o cambiaba. Las decisiones se aplicaron el 18 Oct 2026 a `trd.md`, `contratos-api.md`, `esquema-backend.md`, `adrs.md` (ADR-015 a 018), `backlog.md` (incluida la épica E14), `especificaciones-interaccion.md` y `CLAUDE.md`. Este archivo queda como registro de lo decidido; `plan-desarrollo.md` lo creará el usuario por aparte.
**Nota:** `docs/plan-desarrollo.md` (citado en `CLAUDE.md`) no existe todavía; ver §7.

**Prioridad:** 🔴 bloquea el contrato o el front no puede construir la pantalla · 🟡 conviene resolverlo antes de implementar · 🟢 aclaración menor.

---

## 0. Decisiones ya tomadas (18 Oct 2026)

| Punto | Decisión | Consecuencia para el plan |
|---|---|---|
| **B-01** Qué muestra el Inicio | **Se actualiza el TRD al diseño.** El Inicio queda como está diseñado | `GET /api/dashboard/summary` se recorta a lo que se usa: tareas pendientes, vencen hoy, lista de tareas, tableros recientes y calendario. Se retiran del contrato `overdue`, `assignedBoardCount`, `boards`, `todayProgress` y la barra de progreso de `myBoards`. Reescribir TRD §3.15 y E11-1 |
| **E14-0** Stack del frontend | **React + Vite + TypeScript** | Sugeridos (no obligatorios): TanStack Query, `@stomp/stompjs`, dnd-kit, Tailwind con los tokens del `.pen`. Proxy en desarrollo para la cookie de refresh. Actualizar "Pendientes conocidos" de `CLAUDE.md` |
| **A-07** Guardado del color | **Hex, con lista fija validada** en el servidor | Se conserva el modelo actual. Validar contra los 8 hex de tablero y los 6 acentos de etiqueta nuevos; el fondo de la etiqueta lo deriva el frontend |
| **A-01** Calendario del Inicio | **Endpoint propio por mes** | `GET /api/dashboard/calendar?month=YYYY-MM` → días con tareas asignadas (`id`, `title`, `boardId`, `boardColor`), calculado con `APP_TIMEZONE`. Se añade a E11-2; el resumen no crece |
| **A-02 / A-04** Tableros recientes (hero y sidebar) | **Reusar `GET /api/boards`** | `GET /api/boards?sort=lastActivityAt,desc&size=4` para ambos. Documentar los campos de `sort` permitidos (`lastActivityAt`, `name`, `updatedAt`). El número del sidebar es `taskCount` del tablero (todas las pendientes, no solo las mías). `summary.myBoards` desaparece (ver B-01) |
| **A-03** Contador de "Mis tareas" | **Endpoint de contadores** | `GET /api/me/counters` → `{ openAssigned, unreadNotifications }`. `openAssigned` excluye completadas y "al día". Se mantiene con los eventos de asignación/completar y se recarga al reconectar. Historias: E11-1, E13-2 |
| **A-05, A-06, A-08, A-09, A-15, A-16, A-17, A-18** (propuestas por defecto, aceptadas) | **Aceptadas tal como se propusieron** | A-05: `summary.upcoming` con `limit` (6 por defecto), vencidas primero y `bucket` en cada fila. A-06: el saludo usa la hora local del navegador. A-08: `lookup` añade `SELF`, `role` en `ALREADY_MEMBER` e `invitation.expiresAt` en `ALREADY_INVITED`. A-09: etiquetas de la búsqueda con `taskCount`. A-15: transferir maneja `TRANSFER_TARGET_INVALID` sin `accountState`. A-16: "Verificar correo" con sesión y sin cuerpo, límite 3 por 10 min. A-17, A-18: sin cambios de contrato |
| **A-11** Invitaciones en el feed | **Solo en su bloque** | `GET /api/notifications` excluye por defecto las `INVITATION_RECEIVED` mientras la invitación esté pendiente; `unread-count` sí las cuenta. Al resolverse la invitación su notificación pasa a leída y entra al feed. Historias: E13-2, E13-8 |
| **A-12** Reloj para tiempos relativos | **Reloj del navegador, solo para mostrar** | Vencimientos, "hoy" y "esta semana" siguen del servidor (`today`, `bucket`). Registrar un ADR corto. Sin cambios de API |
| **A-13** Permisos en la interfaz | **Los deriva el cliente** | A partir de `myRole` y el asignado, con la matriz del TRD §3.2 documentada en el plan del front (E14-7). El servidor sigue rechazando lo no permitido. Sin `permissions` en los DTO |
| **A-14** Fecha en "Eliminar cuenta" | **Texto de 30 días en el diálogo** | El diálogo dice "tendrás 30 días" y la fecha exacta (`recoveryDeadline`) se muestra en la vista de recuperación y en el correo. Texto de la pantalla «Eliminar cuenta · Confirmación» ya actualizado en el `.pen` |
| **B-02** Ajustes y campana en el sidebar | **Aceptar el diseño** | Ajustes se abre con el engranaje de la barra superior; el contador de no leídas vive solo en «Notificaciones» del sidebar. Corregir `especificaciones-interaccion.md` §6 y §13 (menciones a la campana) |
| **B-03** Invitaciones al crear tablero | **Validar al añadir + toast resumen** | El botón «Invitar» del formulario consulta `GET /api/users/lookup?email=` (sin `boardId`; 10/min) y solo añade el chip si el estado es `FOUND`. Al crear, toast «Tablero creado · N invitaciones enviadas» y, si el servidor omitió alguna, «M no se pudieron enviar». Sin diálogo de resultado. Corregir E3-1 y el TRD §3.1 |
| **B-04** Invitaciones pendientes en el feed | Ya resuelto con A-11 | — |
| **B-05** Columna "Hecho" frente a "Completadas" | **Dejarlo como está** | Se conserva el cuarteto del TRD. Documentar en el plan y en la ayuda de la interfaz que una tarea en «Hecho» sigue pendiente (cuenta en el límite) y una completada sale del kanban |
| **B-06** Aviso "Sin conexión" | Decidido antes por el usuario | Flotante abajo, superpuesto. Corregir `especificaciones-interaccion.md` §7 (hoy dice banner superior) |
| **B-07** Eliminar tablero | Sin decisión nueva | El backlog E3-5 ya dice «diálogo de confirmación con checkbox»; el diseño lo cumple. Solo corregir el hallazgo |
| **B-08** Cuentas en eliminación en la búsqueda por correo | Sin decisión nueva | El backlog E4-2 ya las trata como `NOT_FOUND`; la interfaz muestra el mismo mensaje que «no encontrado» |
| **B-09** "Al día" atenuado | **Atenuar sin bajar el texto** (✅ aplicado en el `.pen`) | Título y fecha conservan el color normal; se atenúan el fondo de la fila y los indicadores (progreso, punto del tablero); la etiqueta «Al día» queda en verde. Cumple AA. Corregir `especificaciones-interaccion.md` §16 y la fila en el diseño de Mis tareas |
| **B-10** Contraseñas | **Mostrar/ocultar en todos y un solo campo** (✅ aplicado: componente `Campo/Contraseña`) | Icono de ojo en login, registro, restablecer y Ajustes; sin campo de confirmación. Añadir al diseño de acceso y documentar |
| **B-11** Cronograma | **Aceptar navegación de rango y leyenda** | Las flechas desplazan `from/to`; «Hoy» vuelve a la semana actual; la leyenda explica prioridad (color + icono). Añadir a E11-4 y al TRD §3.16 |
| **C-02** Dónde se gestionan las etiquetas | **Diálogo «Etiquetas» desde el menú ⋯ del tablero, visible para todos los roles** | Corrige la regla de visibilidad de la especificación §8 («el Miembro no ve menús de tablero salvo Salir»): el Miembro ve el menú con «Etiquetas» y «Salir del tablero». Actualizar §8 y E9-1. En la confirmación de eliminar etiqueta se muestra a cuántas tareas afecta (`TagDto.taskCount`) |
| **A-10** Cronograma | **`bucket` en cada ítem** | El servidor calcula `bucket` (`OVERDUE`, `TODAY`, `THIS_WEEK`, `LATER`, `ON_TRACK`) como en Mis tareas. Rango por defecto: 4 semanas desde el lunes de la semana en curso; máximo 92 días por consulta. Historia: E11-4 |

---

## 1. Resumen

| Bloque | Cantidad | Qué es |
|---|---|---|
| A. Cambios de API / contrato | 18 | Campos o endpoints que la pantalla necesita y el contrato no trae |
| B. Decisiones de producto pendientes | 11 | Dudas que hay que resolver antes de cerrar el contrato |
| C. Pantallas sin diseño | 4 | Historias del backlog sin pantalla |
| D. Correcciones en documentos existentes | 8 | Texto o valores del diseño viejo que contradicen el nuevo |
| E. Trabajo solo de frontend que el plan debe incluir | 14 | Historias nuevas sin backend |
| F. Semillas y datos de ejemplo | 3 | Para que front y back prueben con los mismos datos |

---

## 2. A · Cambios de API / contrato

Cada fila indica la pantalla que lo exige, qué dice hoy el contrato y qué se propone. Las historias son las de `backlog.md`.

| ID | Pri. | Pantalla | Hoy | Propuesta | Historia |
|---|---|---|---|---|---|
| A-01 | 🔴 | **Inicio · calendario del mes** (con puntos por día y navegación mes a mes) | `GET /api/dashboard/summary` solo trae `week` (semana en curso) | Endpoint nuevo, por ejemplo `GET /api/dashboard/calendar?month=2026-10` → días con `tasks[{id,title,boardId,boardColor}]`, calculado en la zona `APP_TIMEZONE`; o parámetros `from/to` en el resumen | E11-2 (ampliar) |
| A-02 | 🔴 | **Inicio · "Mis tableros"** (2–4 más recientes, con pendientes y "hace 2 h") | `summary.myBoards` trae rol y subtareas, sin `taskCount` ni `lastActivityAt`; no define orden ni límite | Definir `GET /api/boards?sort=lastActivityAt,desc&size=4` como fuente (ya tiene `taskCount` y `lastActivityAt`) y documentar los campos de `sort` permitidos en `/api/boards`; o ampliar `myBoards`. Hoy `esquema-backend.md` no lista los campos ordenables | E3-2, E11-1 |
| A-03 | 🔴 | **Sidebar · contador de "Mis tareas"** | La especificación (§6) pide asignadas **sin completadas ni "al día"**; ningún campo lo devuelve (`summary.assigned` no aclara si cuenta "al día") | Añadir un contador ligero, por ejemplo `GET /api/me/counters` → `{ openAssigned, unreadNotifications }`, o un campo en `summary`. Aclarar que `assigned` incluye o no las "al día" | E11-1, E13-2 |
| A-04 | 🟡 | **Sidebar · "TABLEROS"** (4 recientes con su número de pendientes) | Ningún documento dice cuántos ni con qué criterio | Fijar: los 4 más recientes por `lastActivityAt` (mismo origen que A-02) y que el número es `taskCount` del tablero (todas las pendientes, no solo las mías) | E3-2 |
| A-05 | 🟡 | **Inicio · "Tareas pendientes"** (6 filas: vencidas, hoy, con fecha) | `summary.upcoming` sin límite definido, sin `bucket` en cada fila | Definir cantidad (parámetro `limit`), orden (vencidas primero, luego por fecha) y añadir `bucket` a los `TaskListItemDto` de `upcoming` para pintar "Vencida / Hoy / fecha" sin calcular fechas en el cliente | E11-1 |
| A-06 | 🟡 | **Inicio · saludo** ("Buenos días, Jorge") | El resumen trae `today` (fecha), no la hora | Decidir: el cliente usa su hora local solo para el saludo, o el resumen añade `now` (Instant) para que el saludo use `APP_TIMEZONE` (ADR-006) | E11-1 |
| A-07 | 🔴 | **Paletas de color** | `esquema-backend.md` valida 8 colores de tablero y 6 de etiqueta, con los hex del diseño viejo (`#FFD43B`, `#BFF05A`, `#7FE3F2`) | Sustituir por los nuevos: tablero `#4A3FD6 #2563EB #0E8F8F #2E9E5B #D98A00 #E5622B #D6336C #5B6075`; etiqueta (texto/acento) `#3B30B0 #1B4DB0 #0B6663 #1A6B3F #8A5200 #A3214F`. Decidir si se guarda el hex o una clave (`violet`, `blue`…) y que el fondo de la etiqueta lo derive el front | E3-1, E9-1 |
| A-08 | 🟡 | **Invitar por correo** (5 estados) | `lookup` devuelve `FOUND`, `NOT_FOUND`, `ALREADY_MEMBER`, `ALREADY_INVITED`; el diseño también muestra **uno mismo** | Añadir el estado `SELF` al `lookup` (o fijar que el cliente compara con su propio correo). Para la tarjeta de "ya es miembro" añadir `role`; para "ya invitado" añadir `invitation.expiresAt` | E4-2 |
| A-09 | 🟡 | **Búsqueda en el tablero** | Resultado de etiquetas: `{id,name,color}` | La fila de etiqueta muestra "5 tareas": añadir `taskCount` a cada etiqueta del resultado | E3-6 |
| A-10 | 🔴 | **Cronograma** | Cada ítem trae `taskId, title, priority, startDate, dueDate, columnId, assignee` | La lista izquierda muestra "Vencida · 12 OCT / Hoy / Al día · 18 OCT": añadir `bucket` (o `subtasksDone/subtasksTotal`) a cada ítem. Definir el rango por defecto (el diseño muestra 4 semanas, 12 OCT–8 NOV), el máximo permitido para `from/to` y qué hace el cliente con tareas que empiezan antes del rango | E11-4 |
| A-11 | 🟡 | **Notificaciones · invitaciones vs feed** | Las invitaciones pendientes generan una notificación `INVITATION_RECEIVED` y cuentan en el contador de no leídas, pero el diseño las muestra en un bloque aparte | Fijar la regla: o `GET /api/notifications` las excluye mientras estén pendientes (parámetro o filtro del servidor), o el cliente las filtra. Mantener coherentes `unread-count`, el "n sin leer" del encabezado y el total del feed ("Mostrando 11 de 26") | E13-2, E13-8 |
| A-12 | 🟡 | **Tiempos relativos** ("hace 12 min", "Ayer", "expira en 4 días") | La especificación §10 prohíbe usar la fecha del cliente para decidir vencimientos, pero no dice nada de tiempos relativos | ADR corto: o el cliente usa su reloj para mostrarlos, o el servidor envía `serverNow` (cabecera `Date` o campo) y el cliente calcula contra ese valor | E13-8, E4-3 |
| A-13 | 🟡 | **Permisos en la interfaz** | La matriz vive en el TRD §3.2 y el cliente la reimplementa a partir de `myRole` + `assignee` | Considerar un objeto `permissions` en `BoardDetail` y `TaskDetailDto` (`canEditDates`, `canDelete`, `canAssign`, `canComplete`, `canMove`) para no duplicar reglas en el front. Si no, dejar escrito qué deriva el cliente | E6-7, E3-3 |
| A-14 | 🟡 | **Eliminar cuenta · confirmación** | El diálogo muestra la fecha límite ("hasta el 15 NOV 2026") antes de confirmar, pero `recoveryDeadline` solo llega en la respuesta del `DELETE` | Decidir: el diálogo dice "30 días" y la fecha exacta se muestra después, o un endpoint de vista previa. No debe calcularla el cliente con su fecha | E2-4 |
| A-15 | 🟢 | **Transferir propiedad · candidatos** | `MemberDto` no trae el estado de la cuenta; el TRD §3.1 dice que el nuevo Owner no puede ser una cuenta en eliminación | Aceptar el error `TRANSFER_TARGET_INVALID` en la interfaz, o añadir `accountState` a `MemberDto` para filtrar antes | E4-9 |
| A-16 | 🟢 | **Ajustes · "Verificar correo"** | `POST /api/auth/verify-email/resend` existe pero no dice si exige sesión | Aclarar que, desde Ajustes, se llama con la sesión (sin cuerpo) y limita 3 por 10 min | E1-2 |
| A-17 | 🟢 | **Completadas** | Paginado con `total` (ya está en la convención) | Solo confirmar que el contador de la pestaña usa `completedTaskCount` y que la lista muestra `completedAt` en formato relativo ("Hoy · 09:40") | E6-9 |
| A-18 | 🟢 | **Tablero · columnas** | `ColumnDto` ya trae `taskLimit` y `taskCount` | Sin cambio. Anotar que la alerta al 80 % y el estado "llena" los calcula el cliente; y que el selector de "Reabrir" necesita los conteos actuales (los eventos `ColumnUpdated` lo mantienen al día) | E5-4, E6-8 |

---

## 3. B · Decisiones de producto pendientes (bloquean el contrato)

| ID | Pri. | Decisión | Contexto | Opciones |
|---|---|---|---|---|
| B-01 | 🔴 | **Qué muestra el Inicio** | El TRD §3.15 define cinco métricas (VENCEN HOY, VENCIDAS, ASIGNADAS A MÍ, TABLEROS, avance de hoy), PRÓXIMAS TAREAS, MIS TABLEROS con barra de progreso y VENCEN ESTA SEMANA. El Inicio pedido muestra bienvenida + Mis tableros + tareas + calendario + notificaciones, sin las tarjetas de métricas ni la barra de progreso | Actualizar el TRD al diseño nuevo (y recortar `summary` a lo que se usa), o volver a añadir las métricas al diseño |
| B-02 | 🟡 | Ajustes y campana en el sidebar | La especificación (§6) cita sidebar con Ajustes y campana. El diseño no tiene ítem de Ajustes (se entra por el engranaje de la esquina) ni campana | Aceptar el diseño y corregir la especificación, o añadir los elementos |
| B-03 | 🟡 | Resultado de invitaciones al crear tablero | `POST /api/boards` devuelve `invitations[]` con `INVITED` o `SKIPPED` + motivo, pero se quitó el diálogo de resultado | Definir cómo se avisa (resumen en un toast, o mantener el diálogo) |
| B-04 | 🟡 | Invitaciones pendientes en el feed | Ver A-11 | Bloque aparte (diseño actual) o también en el feed |
| B-05 | 🟡 | Columna "Hecho" frente a "Completadas" | El tablero crea por defecto una columna **Hecho** y además existe la sección **Completadas**; una tarea en "Hecho" no está completada y puede confundir | Renombrar la columna por defecto, o explicarlo en la interfaz |
| B-06 | 🟡 | Aviso "Sin conexión" | La especificación dice banner rojo superior; el diseño lo muestra flotante abajo | Corregir la especificación |
| B-07 | 🟡 | Confirmación de eliminar tablero | El documento pide "confirmación explícita"; el diseño usa una casilla | Casilla (actual) o escribir el nombre del tablero |
| B-08 | 🟡 | Cuentas en eliminación en la búsqueda por correo | Se tratan como `NOT_FOUND` (backlog E4-2) | Confirmar que el mensaje al usuario es el mismo que "no encontrado" |
| B-09 | 🟢 | "Al día" atenuado al 60 % | Lo pide la especificación; el texto atenuado queda por debajo del contraste AA | Otra forma de atenuar (por ejemplo, solo la fila sin bajar el texto) |
| B-10 | 🟢 | Contraseña | Los campos de Ajustes tienen icono mostrar/ocultar; ningún documento lo define. En Restablecer solo hay un campo | Confirmar ambas cosas |
| B-11 | 🟢 | Cronograma | Se añadieron navegación de rango (`‹ ›`, "Hoy") y leyenda de prioridades; no están en el TRD §3.16 | Confirmar o quitar |

---

## 4. C · Pantallas sin diseño (historias del backlog sin pantalla)

| ID | Pri. | Falta | Historia | Nota |
|---|---|---|---|---|
| C-01 | ✅ | **Editar tablero** (nombre, descripción, color; conflicto de versión) | E3-4 | **Diseñado (18 Oct):** diálogo «Editar tablero» y variante con el banner de `BOARD_VERSION_CONFLICT` (Recargar / Sobrescribir). Se abre desde el menú ⋯ del Owner |
| C-02 | ✅ | **Gestión de etiquetas del tablero** (crear, editar, eliminar, conteo de uso) | E9-1, E9-2 | **Diseñado (18 Oct):** diálogo «Etiquetas» (lista con conteo de tareas, editar, eliminar, formulario de nueva etiqueta con error `TAG_DUPLICATE` y los 6 acentos) y su confirmación de eliminar. Se abre desde el menú ⋯ del tablero, que ahora lo ven **todos los roles** (el Miembro solo tiene «Etiquetas» y «Salir del tablero») |
| C-03 | 🟡 | **Páginas públicas de Términos y Privacidad** | E1-7 | Excluidas por decisión del usuario; sigue en el plan |
| C-04 | 🟢 | Variante **Admin** del diálogo de Miembros (sin selector de rol, "quitar" solo en Miembros) | E4-6, E4-7 | Excluida por decisión del usuario; el comportamiento sigue en el TRD |

---

## 5. D · Correcciones en documentos existentes (referencias al diseño viejo)

| ID | Documento | Pasaje | Cambio |
|---|---|---|---|
| D-01 | `especificaciones-interaccion.md` | L3 "el mock", L10 "El mock es 1440 px", L15 "componentes en el .pen" | Sustituir "mock" por `diseño-interfaz.pen` |
| D-02 | `especificaciones-interaccion.md` | L7 "Acento fijo (amarillo de marca)" | Acento índigo `#4A3FD6` |
| D-03 | `especificaciones-interaccion.md` | L52 hover/presionado "sombra 2×2" | Reescribir con los estados del sistema nuevo (sin sombras desplazadas) |
| D-04 | `especificaciones-interaccion.md` | L53 anillo `#141414`; L66 texto `#141414` y `#5F5A50` | Foco índigo de 2 px; texto `#14172B`, secundario `#5B6075` |
| D-05 | `especificaciones-interaccion.md` | L20 "línea de 2 px del acento"; L23 fantasma a "2°" | Revisar color del acento; el diseño inclina −2° (convención de Pencil) |
| D-06 | `especificaciones-interaccion.md` | §18 (pantallas pendientes) | Casi todo ya está diseñado; dejar solo Términos/Privacidad, Editar tablero y etiquetas |
| D-07 | `contratos-api.md` | Ejemplos con `#FFD43B`, `#BFF05A`, `#7FE3F2` (L90, 112, 122, 127, 147, 221, 222, 292, 322, 323) | Usar los hex nuevos (A-07) |
| D-08 | `backlog.md` L3 y L162; `CLAUDE.md` L37 y L105 | Referencias a `diseño-interfaz.pen` y "faltan pantallas" | Actualizar cuando se cierren C-01 a C-03 |

---

## 6. E · Trabajo solo de frontend que el plan debe incluir

El backlog es casi todo de backend (el frontend "no tiene stack definido"). Para que ambos avancen juntos faltan historias de frontend. Propuesta de épica **E14 — Frontend**:

| ID | Historia propuesta | Depende de |
|---|---|---|
| E14-0 | **Elegir el stack del frontend** (framework, estado, cliente STOMP, librería de arrastre) | — (bloquea todo lo demás) |
| E14-1 | Tokens del diseño como tema (62 variables del `.pen`: colores, espaciado, radios, fuentes) y tipografías **Plus Jakarta Sans** + **Inter** | E14-0 |
| E14-2 | Biblioteca de componentes del sistema (botones, campos, casillas, insignias, etiquetas, avatares, toasts, banners, diálogos, tarjeta, columna, estados vacío/error/cargando) con foco visible de 2 px | E14-1 |
| E14-3 | Shell de la app: sidebar de 288 px, barra de usuario, chip de conexión, rutas públicas y privadas, 404 | E14-2, E1-3 |
| E14-4 | Cliente HTTP con access token en memoria, refresh serializado, mapeo `code` → mensaje en español (catálogo de errores) y manejo de `RATE_LIMITED` con cuenta regresiva | E1-3, S0-4 |
| E14-5 | Cliente STOMP y reconciliación idempotente (estados EN VIVO / RECONECTANDO / SIN CONEXIÓN, recarga al reconectar) | E10-1..E10-4 |
| E14-6 | Arrastrar y soltar de tareas y columnas (150 ms de arranque, original al 40 %, hueco de inserción, columna llena atenuada, reversión con toast) | E5-2, E6-3 |
| E14-7 | Renderizado según rol (ocultar, no deshabilitar; "Salir del tablero" bloqueado para el Owner) | A-13 |
| E14-8 | Formato de fechas y tiempos en español (`dd MMM`, "hace 12 min", "Ayer") sin usar la fecha del cliente para vencimientos | A-12 |
| E14-9 | Accesibilidad: etiquetas accesibles en botones de icono (por ejemplo "Agregar columna" es solo "+"), diálogos con foco atrapado y `Esc`, estados con texto además de color | E14-2 |
| E14-10 | Pantallas por épica (acceso, Inicio, Mis tareas, tableros, kanban, detalle, completadas, cronograma, miembros, notificaciones, ajustes) | E14-3 y la historia de backend de cada una |
| E14-11 | Comportamiento por debajo de 1280 px (degradado, documentado como limitación) | E14-3 |
| E14-12 | Carga de avatar (validación de tipo y 2 MB en cliente además del servidor) | E2-3 |
| E14-13 | Pruebas de extremo a extremo de los flujos críticos (login, crear tablero, mover tarea, conflicto de versión, invitar) | E14-10 |

---

## 7. F · Semillas y plan de trabajo

| ID | Pri. | Qué | Detalle |
|---|---|---|---|
| F-01 | 🟡 | **Semilla de datos (S0-5) alineada con el diseño** | Usar los mismos nombres y cifras de las capturas: Jorge Díaz (Owner), Marco Ruiz, Ana Kim, Lucía Pérez; 4 tableros (Lanzamiento del producto, Rediseño del sitio, Operaciones Q4, Contenido y blog); columna "En curso" con límite 4 y 4 tareas; "hoy" = 16 OCT 2026; incluir una tarea completada, comentarios con mención, invitaciones pendientes y una notificación de cada tipo |
| F-02 | 🟡 | **Corregir incoherencias de datos del diseño antes de usarlo como referencia** | "Maquetar página de precios" figura asignada a Ana Kim en el tablero pero como tarea del usuario en el Inicio; el sidebar de "sin columnas" conserva el 10 de pendientes (ver `diseno-cambios.md` §5) |
| F-03 | 🔴 | **Crear `docs/plan-desarrollo.md`** | `CLAUDE.md` lo cita para marcar historias terminadas, pero no existe. Sugerencia de fases: 0 fundaciones (S0) → 1 acceso y cuenta (E1, E2) → 2 tableros y miembros (E3, E4) → 3 kanban y tareas (E5–E9) → 4 tiempo real (E10) → 5 Inicio, Mis tareas, cronograma y notificaciones (E11, E13) → 6 calidad (E12). El frontend (E14) corre en paralelo: E14-0 a E14-5 junto con las fases 0–1, y E14-10 pantalla por pantalla a medida que cada historia de backend termina |

### Orden sugerido para cerrar el contrato antes de programar

1. Decidir **B-01** (Inicio), **A-07** (paletas) y **E14-0** (stack del frontend): bloquean el resto.
2. Cerrar los 🔴 de §2 (A-01, A-02, A-03, A-10) y escribirlos en `contratos-api.md` y en las historias E11-1, E11-2, E11-4 y E13-2.
3. Diseñar **C-01** y **C-02** (Editar tablero y etiquetas) para destrabar E3-4 y E9.
4. Resolver los 🟡 en una pasada y registrar los que sean decisiones técnicas como ADR (A-12, A-06).
5. Aplicar las correcciones de §5 en un solo cambio de documentos.
