# Especificaciones de interacción — Task Flow v1

**Fecha:** 16 Oct 2026 (actualizada el 18 Oct 2026 tras el rediseño de la interfaz) · Complemento de `trd.md`, `contratos-api.md`, `adrs.md` y el diseño (`diseño-interfaz.pen`). Aquí se cierran los comportamientos que el diseño no especifica.

## 1. Tema y apariencia
- **Solo tema claro en v1.** Se retiró el toggle sol/luna del sidebar; el tema oscuro queda como fase posterior.
- Acento fijo (índigo `#4A3FD6`) como en el diseño; sin selector de acento en v1.

## 2. Breakpoints web
- **Ancho soportado v1: ≥ 1280 px.** La referencia de diseño es 1440 px.
- Estructura: sidebar fijo 288 px + contenido flexible; el contenido usa el espacio disponible (no se re-centra).
- Kanban: columnas de mínimo **240 px**; si no caben todas, el área de columnas hace scroll horizontal (no se comprimen las tarjetas).
- Lista de tareas, cronograma y ajustes: anchos flexibles; las filas conservan sus columnas (título elástico).
- < 1280 px: comportamiento degradado (no prioritario): sin garantía de diseño; documentar como limitación conocida.
- Móvil/tablet: fuera de alcance (no se diseñan en el `.pen`).

## 3. Drag & drop
**Tareas (kanban y lista agrupada):**
1. Arranque tras 150 ms de arrastre (evita clics accidentales); la tarjeta original queda en 40 % de opacidad y un "fantasma" sigue al puntero en ángulo 2°.
2. Zonas de destino: cualquier columna **que no esté llena**; el hueco de inserción (línea de 2 px del acento índigo) indica la posición exacta. Una columna llena no muestra hueco de inserción y se atenúa con el aviso "Columna llena (N/N)".
3. Al soltar: **actualización optimista** (la tarjeta se coloca al instante) + `PATCH /api/tasks/{id}/move {columnId, position}`, donde `position` es el índice destino dentro de la columna.
4. Respuesta OK → se descarta el fantasma; llega `TaskMoved` → se aplica el orden autoritativo (`order[]`); si difiere de lo mostrado, se corrige sin animación.
5. Error 403/404 → se revierte la posición con animación y se muestra toast de error. Error 409 `COLUMN_LIMIT_REACHED` (otra persona llenó la columna mientras se arrastraba) → se revierte igual y el toast dice "La columna está llena".
6. Regla de concurrencia: "última escritura persiste"; mover y reordenar no generan 409 por versión (solo por límite de columna).
7. Un **Miembro** solo puede arrastrar las tarjetas que tiene asignadas; las demás no muestran el cursor de arrastre.
8. Fuera de alcance v1: arrastrar entre tableros y arrastrar o reordenar subtareas.

**Columnas:** mismo patrón con `PATCH /api/columns/{id}/position`; el borde de inserción va entre columnas; el evento `ColumnReordered` reconcilia el orden completo. Solo Owner y Admin pueden reordenar.

## 4. Guardado y conflicto (formularios)
- El detalle de tarea y editar tablero guardan con el botón explícito **"Guardar cambios"**.
- Toda edición por formulario envía `version`. Si el servidor responde **409 `TASK_VERSION_CONFLICT`** (o `BOARD_VERSION_CONFLICT` al editar el tablero) → aparece el banner del diseño ("Alguien más guardó cambios…") con:
  - **Recargar**: usa la versión actual que ya viene en la respuesta 409 (`current`) y descarta los cambios locales (con confirmación si hay campos modificados).
  - **Sobrescribir**: reenvía los cambios con la versión nueva (`currentVersion`), sin perder lo escrito.
- Si llega un evento `TaskUpdated` (o `BoardUpdated`) del recurso abierto mientras hay cambios sin guardar → se muestra el mismo banner (sin descartar nada).
- Mover, reordenar, asignar, completar y reabrir **no** cambian la versión, así que no disparan el banner.
- Guardado OK → toast "Cambios guardados" y el banner desaparece.
- Salir con cambios sin guardar → confirmación "Descartar cambios".

## 5. Campos de fecha
- `startDate` y `dueDate` usan **selector nativo de fecha** (`input type=date`), formato de presentación `dd MMM` (p. ej. "15 OCT").
- Validación en línea: si `startDate > dueDate`, el campo due se marca en rojo con el mensaje "La fecha límite debe ser igual o posterior al inicio" (`DATE_RANGE_INVALID`).
- Vacío = sin fecha (nullable); limpiar el campo es válido. Una tarea sin fecha límite aparece en la sección "SIN FECHA" de Mis tareas.

## 6. Badges y contadores (v1)
- **Sidebar · Mis tareas**: cantidad de tareas asignadas al usuario, sin completadas ni "al día" (`openAssigned` de `GET /api/me/counters`).
- **Sidebar · Notificaciones**: número de **notificaciones sin leer** (`unreadNotifications` de `GET /api/me/counters`, igual que `GET /api/notifications/unread-count`), que incluye las invitaciones recibidas pendientes. Se actualiza en vivo con `NotificationCreated` y `NotificationsRead`. Sin notificaciones sin leer no se muestra el número.
- Columnas: contador `n/límite` (por ejemplo `7/50`) con color de alerta al llegar al 80 %; "Mis tableros": nº de tareas pendientes; pestaña Comentarios: total de comentarios.

## 7. Feedback de acciones
- Toasts (esquina inferior derecha, 4 s): éxito ("Cambios guardados", "Invitación enviada"), error (con código si aplica).
- Botones: hover → fondo más oscuro del mismo color (`accent-hover`); presionado → más oscuro aún (`accent-pressed`); deshabilitado → fondo gris claro, texto `#8A8FA3` y sin puntero. Sin sombras ni desplazamientos.
- Foco visible siempre: anillo de 2 px índigo `#4A3FD6` con offset 2 px (nunca se elimina).
- Toda acción destructiva (eliminar tablero/columna/tarea/cuenta, salir) pide confirmación explícita.
- Errores de red: aviso rojo "Sin conexión a TaskFlow. Reintentando…" **flotante**, centrado en la parte inferior del contenido y superpuesto (no ocupa espacio en la página) + reintento automático con backoff (el LiveChip refleja el estado). Al volver a EN VIVO el cliente recarga el tablero abierto y el contador de notificaciones.
- Límite de frecuencia (`RATE_LIMITED`): toast con el tiempo de espera (`Retry-After`) y el botón afectado queda deshabilitado hasta entonces.

## 8. Permisos en la UI (vista Owner de referencia)
- El diseño está en vista Owner; al implementar, las acciones se ajustan al rol:
  - **MEMBER**: no crea ni elimina tareas (sin botón "Agregar tarea"); en las tareas que tiene asignadas edita título, descripción y etiquetas, gestiona subtareas, las mueve, las completa/reabre y puede desasignarse; no cambia fechas ni prioridad; puede comentar cualquier tarea y gestionar las etiquetas del tablero; no ve los menús de miembros ni las acciones de editar o eliminar el tablero; el menú ⋯ del tablero le muestra solo "Etiquetas" y "Salir del tablero".
  - **ADMIN**: todo excepto editar o eliminar el tablero, cambiar roles y transferir propiedad. Puede invitar, cancelar invitaciones y quitar solo a Miembros.
  - **OWNER**: todo.
- Regla general: lo no permitido se **oculta** (no se deshabilita), excepto "Salir del tablero" siendo Owner que se muestra bloqueado con la ruta de transferencia.

## 9. Accesibilidad mínima
- Contraste: texto `#14172B` sobre fondos claros y blanco sobre el acento `#4A3FD6` (AA o superior); `#5B6075` solo para texto secundario. Excepción documentada: el texto deshabilitado.
- Todos los controles con etiqueta visible (no solo placeholder); iconos decorativos `aria-hidden`; botones icono con `aria-label`.
- Navegación por teclado en diálogos: foco atrapado, `Esc` cierra, `Enter` confirma.
- Estados no solo por color: "al día", "vencido" y "columna llena" además del color llevan texto/estilo.

## 10. Fechas y zona horaria
- La aplicación usa una **zona horaria única** (`APP_TIMEZONE`, ADR-006). "HOY", "vence mañana", "esta semana" y los grupos de Mis tareas los calcula el servidor; el cliente no usa la fecha del navegador para decidir vencimientos.
- Las respuestas de detalle de tablero, cronograma y resumen incluyen `today`; con ese valor se pintan las tarjetas vencidas y la línea de HOY del cronograma.
- Si el navegador está en otra zona, la interfaz muestra el día de la aplicación, no el del dispositivo.

## 11. Límites en la interfaz
- Campos con límite de caracteres (ADR-004): contador visible en descripción y comentario al llegar al 90 %; el resto bloquea al llegar al máximo.
- Botón "Agregar columna" deshabilitado al llegar a 12 columnas, con tooltip "Máximo 12 columnas".
- Botón "Agregar subtarea" deshabilitado al llegar a 30, con tooltip.
- Configurar el límite de una columna: campo numérico (1 a 100) en el menú de la columna, solo Owner y Admin; si el valor es menor que las tareas actuales muestra el error en línea (`COLUMN_LIMIT_BELOW_CURRENT`).
- En una columna llena: el botón "Agregar tarea" se deshabilita y no admite soltar tarjetas.

## 12. Completar y reabrir tareas
- El detalle de tarea tiene el botón **"Marcar como completada"**. Al completarla sale del kanban con toast "Tarea completada" (con acción "Deshacer", que la reabre en su columna anterior si aún tiene espacio).
- Las tareas completadas se ven en la sección **"Completadas"** del tablero (lista paginada, más recientes primero), con el botón **"Reabrir"**.
- "Reabrir" abre un selector con las columnas del tablero; las columnas llenas aparecen deshabilitadas con su contador. Tras elegir, la tarea vuelve al final de esa columna como pendiente.
- Un Miembro solo completa y reabre las tareas que tiene asignadas.

## 13. Notificaciones
- La pantalla **Notificaciones** tiene dos bloques: arriba las **invitaciones pendientes** (con Aceptar/Rechazar y tiempo restante) y debajo el **feed** de notificaciones, de más reciente a más antigua, con paginación.
- Cada notificación muestra actor, texto, tablero y hora; las no leídas se destacan. Abrir una notificación la marca como leída y navega al recurso (tarea, tablero o invitaciones); si el recurso ya no existe, muestra "Ya no está disponible".
- Acciones: "Marcar todas como leídas" y descartar una notificación.
- Tiempo real: al llegar `NotificationCreated` se actualiza el contador y, si el usuario está en la pantalla de Notificaciones, la notificación se inserta arriba; en otras pantallas aparece un toast breve.
- Aceptar o rechazar una invitación actualiza el bloque de invitaciones y marca su notificación como leída.
- Mientras una invitación está pendiente, su notificación no aparece en el feed (se ve en el bloque de invitaciones) pero sí cuenta en el contador de no leídas; al resolverla pasa a leída y entra al feed.
- Los tiempos relativos ("hace 12 min", "Ayer") usan el reloj del navegador solo para mostrar (ADR-015).
- Tipos que se muestran: asignación, mención, invitación recibida/aceptada/rechazada, cambio de rol, remoción, transferencia de propiedad, recordatorios de vencimiento y resumen semanal. No hay preferencias configurables en v1.

## 14. Menciones en comentarios
- Al escribir `@` en un comentario se abre una lista de **miembros del tablero** filtrable por nombre; seleccionar inserta la mención.
- La mención se muestra como chip con el nombre; el límite de 2 000 caracteres cuenta cada mención como `@Nombre`.
- Al editar un comentario, solo las menciones nuevas generan notificación.
- Si se intenta mencionar a alguien que dejó el tablero, el servidor rechaza el comentario y la interfaz muestra el error en el campo.

## 15. Cuenta, avatar y recuperación
- **Registro**: casilla obligatoria "Acepto los Términos y la Política de Privacidad" con enlaces a las páginas públicas; el botón de registro se habilita al marcarla. El acceso con Google muestra los mismos enlaces.
- **Avatar** (Ajustes > Perfil): botón "Cambiar foto" (PNG/JPG/WebP, máx. 2 MB) y "Quitar foto". Los errores de tipo o tamaño se muestran en línea (`AVATAR_INVALID`). Si no hay foto se muestran las iniciales.
- **Cambiar correo** (solo cuentas LOCAL): al guardarlo la cuenta queda sin verificar y se muestra el aviso en Ajustes > Cuenta.
- **Eliminar cuenta**: si es Owner de tableros con otros miembros se muestra la lista de tableros bloqueantes con "Transferir"; si no, la confirmación explícita y, al aceptar, se cierra la sesión, se vuelve al login y se envía un correo con la fecha límite de recuperación.
- **Vista de recuperación**: al iniciar sesión con una cuenta pendiente de eliminación, el usuario no entra a la aplicación; ve la fecha límite, el botón **"Recuperar cuenta"** y "Cerrar sesión". Al recuperarla pasa a la aplicación con una sesión normal. Pasados los 30 días el botón desaparece y el login falla como una cuenta inexistente.

## 16. Mis tareas
- La vista tiene **dos secciones**: arriba las tareas con fecha límite, agrupadas en VENCIDAS · HOY · ESTA SEMANA · MÁS ADELANTE · AL DÍA, y debajo la lista **SIN FECHA**.
- Los grupos vienen del servidor (`bucket`); el cliente solo agrupa por clave. Las tareas "al día" se atenúan sin bajar el contraste del texto: título y fecha conservan su color; se atenúan el fondo de la fila y los indicadores (progreso, punto del tablero) y la etiqueta "Al día" va en verde. Solo se listan tareas pendientes.

## 17. Perder acceso a un tablero
- Si el usuario es removido, sale del tablero o el tablero se elimina mientras lo tiene abierto, la interfaz se desuscribe, vuelve al listado de tableros y muestra un toast ("Ya no tienes acceso a este tablero" o "El tablero fue eliminado").
- Quien no es miembro y abre un enlace a un tablero recibe la pantalla de "No encontrado" (el servidor responde 404).

## 18. Pantallas pendientes de diseño
El diseño (`diseño-interfaz.pen`, rediseño del 18 Oct 2026) cubre todas las pantallas de v1 salvo:
- Páginas públicas de Términos y Privacidad (historia E1-7).
- Variante Admin del diálogo de Miembros (sin selector de rol y con "quitar" solo en Miembros): el comportamiento está en `trd.md` §3.2.

## 19. Inicio y navegación
- **Inicio**: bienvenida con imagen de fondo (saludo según la hora del navegador), "Mis tableros" (2 a 4 más recientes, de `GET /api/boards?sort=lastActivityAt,desc&size=4`), lista de tareas pendientes (`summary.upcoming`), calendario del mes con cambio de mes (`GET /api/dashboard/calendar?month=`) y las notificaciones más recientes.
- **Ajustes**: se abre con el engranaje de la barra superior (junto al avatar); no hay ítem de Ajustes en el sidebar ni campana: el contador de no leídas vive en "Notificaciones" del sidebar.
- **Sidebar**: Inicio, Mis tareas (con contador), Tableros, Notificaciones (con contador), los 4 tableros más recientes con su número de pendientes (todas las del tablero, no solo las del usuario) y "Cerrar sesión".

## 20. Tablero: menú ⋯, etiquetas y edición
- El menú ⋯ del tablero depende del rol: **Owner** → Editar tablero, Etiquetas, Transferir propiedad, Eliminar tablero y Salir del tablero (bloqueado hasta transferir); **Admin y Miembro** → Etiquetas y Salir del tablero.
- **Editar tablero** (solo Owner): nombre, descripción y color; ante `BOARD_VERSION_CONFLICT` aparece el banner Recargar / Sobrescribir (sección 4).
- **Etiquetas**: diálogo con la lista (nombre, color, número de tareas), editar, eliminar (la confirmación indica a cuántas tareas afecta) y formulario de nueva etiqueta con el error `TAG_DUPLICATE` en línea. Lo usan todos los roles.
- **Cronograma**: flechas para desplazar el rango, botón "Hoy" y leyenda de prioridades (color e icono).
- Una tarea en la columna "Hecho" sigue pendiente (cuenta en el límite de la columna); una tarea completada sale del kanban y se ve en "Completadas".

## 21. Formularios: contraseñas e invitaciones iniciales
- Todos los campos de contraseña (acceso, registro, restablecer y Ajustes) llevan un icono de mostrar/ocultar; no hay campo de confirmación.
- Al eliminar la cuenta, el diálogo dice "tendrás 30 días para recuperarla"; la fecha exacta (`recoveryDeadline`) se muestra en la vista de recuperación y en el correo.
- Crear tablero, invitaciones iniciales: el botón "Invitar" valida el correo con `GET /api/users/lookup` y solo añade el chip si es `FOUND`; al crear, un aviso resume cuántas invitaciones se enviaron y cuántas no.
