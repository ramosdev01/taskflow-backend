# Diseño de interfaz — cambios, decisiones y hallazgos

**Fecha:** 18 Oct 2026 · **Archivo:** `docs/diseño-interfaz.pen` · **Capturas:** `docs/exports/`

Rediseño completo de la interfaz de TaskFlow desde cero, sin código de frontend. El estilo anterior (neobrutalismo, acento amarillo, sombras 2×2, tinta `#141414`, "el mock") se descartó por completo. Las contradicciones y huecos están en **§5 Hallazgos** y los pasajes con el diseño anterior en **§6**. Estado al 18 Oct 2026: las decisiones se aplicaron a los documentos de `docs/` (ver `cambios-interfaz-para-plan.md`), de modo que muchos hallazgos y pasajes de §5 y §6 ya están resueltos; se conservan como historial.

---

## 1. Dirección elegida y por qué

Se compararon tres direcciones a partir de `inspiraciones/` (1.jpg lista agrupada, 2.webp detalle, 3.webp kanban, y `dashboard-inspiracion.webp` para el Inicio):

| Dirección | Idea | Resultado |
|---|---|---|
| **A · Lienzo sereno** | Fondo gris-azulado casi blanco, superficies blancas, bordes de 1 px, sombra solo en lo flotante, un acento índigo | **Elegida** |
| B · Cuaderno cálido | Papel marfil, títulos serif, acento terracota | Descartada: se aleja de la sensación de productividad densa y choca con los 8 colores de tablero |
| C · Tinta y señal | Casi monocromo, bordes de tinta, sin sombras | Descartada: deriva hacia lo duro/neobrutalista que se quería abandonar |

**Por qué A:** sirve mejor a un kanban con mucho dato; la sombra casi nula hace que el anillo de foco (2 px) destaque; cumple AA sin esfuerzo; los 8 colores de tablero y los 6 acentos de etiqueta caben bien sobre un fondo neutro frío.

### Decisiones de la entrevista
La skill `grill-me` no estaba disponible; la entrevista se llevó a mano, una pregunta por vez.
- Dirección A, **densidad media**.
- **Color de tablero** como punto + barra fina (no como relleno).
- Tipografía: **Plus Jakarta Sans** (títulos) + **Inter** (cuerpo y datos).
- Decoración **sobria con un toque** (halos y degradados suaves en acceso y en el Inicio).
- Sidebar de 288 px; columnas del kanban de 244 px (mínimo de la especificación: 240 px).

### Decisiones posteriores del usuario (aplicadas)
- **Inicio** rehecho a partir de `dashboard-inspiracion.webp`: bienvenida con imagen de fondo, "Mis tableros" dentro del hero (3 tableros), lista de tareas pendientes (sin formulario de alta), calendario del mes y las notificaciones más recientes. Se quitó el avatar del sidebar y se añadió "Cerrar sesión"; el avatar y un engranaje hacia Ajustes van arriba a la derecha.
- Pantallas de acceso con dos secciones (marca/información a la izquierda, formulario a la derecha).
- Listado de tableros: tarjetas de **igual tamaño**, sin botón "Crear tablero" en la esquina (la tarjeta punteada es la única entrada).
- Crear tablero: botón **"Invitar"** (no "Agregar"); se eliminó el diálogo de resultado de invitaciones.
- Todo modal oscurece el fondo con el mismo velo (`#14172B` al 45 %).
- Aviso de "Sin conexión": **flotante abajo**, sobrepuesto, sin ocupar espacio en la página.
- Cronograma: columna de tareas ancha y filas altas (64 px).
- Completadas: columna **Etiquetas** (1, 2 o 3).
- Eliminar columna no elimina las tareas completadas (no pertenecen a ninguna columna).
- Fuera de alcance por decisión del usuario: páginas públicas de Términos y Privacidad; variante Admin del diálogo de Miembros.

---

## 2. Sistema de diseño

**Colores** (variables en el `.pen`):

| Grupo | Valores |
|---|---|
| Base | lienzo `#F4F5F9` · superficie `#FFFFFF` · superficie suave `#F8F9FC` · borde `#E3E5EC` · borde fuerte `#C4C8D6` |
| Texto | `#14172B` · secundario `#5B6075` · deshabilitado `#8A8FA3` |
| Acento | `#4A3FD6` (hover `#3C32B8`, presionado `#2F2799`, suave `#EEEDFC`, texto sobre suave `#3B30B0`) |
| Semánticos | peligro `#C0283A` / texto `#A3182B` · aviso `#B26A00` / texto `#8A5200` · éxito `#1C7A4F` / texto `#16623F` · info texto `#1B4DB0` |
| **8 colores de tablero** | `#4A3FD6` `#2563EB` `#0E8F8F` `#2E9E5B` `#D98A00` `#E5622B` `#D6336C` `#5B6075` |
| **6 acentos de etiqueta** (fondo / texto) | violeta `#EEEDFC`/`#3B30B0` · azul `#E3EEFF`/`#1B4DB0` · verde azulado `#DDF4F1`/`#0B6663` · verde `#E2F5E9`/`#1A6B3F` · ámbar `#FFF1D6`/`#8A5200` · rosa `#FDE6EE`/`#A3214F` |

**Componentes reutilizables** (a la izquierda del lienzo): botones (primario, secundario, fantasma, destructivo × normal/hover/presionado/deshabilitado/foco); prioridades (Baja, Media, Alta, Urgente, siempre con icono y texto); etiquetas; roles (Owner, Admin, Miembro); estados de tarea (Vencida, Hoy, Al día, Completada); chips de conexión (EN VIVO, RECONECTANDO…, SIN CONEXIÓN); avatares; campos (normal, foco, error, deshabilitado); casillas; toasts (éxito, error, con acción); banners (conflicto, sin conexión); tarjeta de tarea (normal, vencida, arrastrando, origen al 40 %); encabezado de columna (normal, 80 %, llena); diálogo de confirmación destructivo; estados vacío, error y cargando; sidebar; barra de usuario.

**Accesibilidad aplicada:** foco con anillo de 2 px siempre visible; estados que no dependen solo del color (texto + icono: "Vencida", "Hoy", "Al día", "LLENA", prioridades, "Pendiente", "No verificado"); no leídas = punto + negrita + tinte; acciones no permitidas por rol **ocultas** (salvo "Salir del tablero" del Owner, bloqueado con la ruta de transferencia); solo español, solo tema claro, escritorio ≥ 1280 px (referencia 1440).

---

## 3. Pantallas diseñadas (58)

El lienzo está ordenado en filas por flujo; las variantes de cada pantalla quedan a su derecha.

| Fila | Pantallas |
|---|---|
| 1 · Acceso | Login · Login con error y espera por límite · Registro · Registro sin aceptar términos · Revisa tu correo · Enlace expirado · Olvidé mi contraseña · Enlace enviado · Restablecer contraseña · Enlace inválido o vencido · Error de proveedor · Recuperación de cuenta |
| 2 · Inicio | Inicio |
| 3 · Mis tareas | Mis tareas |
| 4 · Tableros | Listado · Listado vacío · Crear tablero |
| 5 · Tablero | Kanban (Owner) · Arrastrando a columna llena · Tarea completada con "Deshacer" · Menú de columna y límite · Eliminar columna · Sin columnas |
| 6 · Búsqueda | Con resultados · Sin resultados |
| 7 · Roles y gestión | Kanban (Miembro) · Kanban (Admin) con menú · Menú del tablero (Owner) · Transferir propiedad · Salir del tablero · Eliminar tablero · Menú del tablero (Miembro) · Editar tablero · Editar tablero con conflicto de versión · Etiquetas del tablero · Eliminar etiqueta |
| 8 · Miembros | Miembros (Owner) · Invitar (usuario encontrado) · Estados de búsqueda por correo (no encontrado, ya miembro, ya invitado, uno mismo, límite de frecuencia) · Quitar miembro |
| 9 · Detalle de tarea | Owner · Comentarios y menciones · Menciones (autocompletado) · Conflicto de versión · Miembro (tarea asignada) |
| 10 | Completadas · Reabrir con selector de columna · Cronograma |
| 11 | Notificaciones (invitaciones pendientes + feed por tipo) |
| 12 · Ajustes | Perfil · Perfil con errores · Cuenta (correo y contraseña) · Cuenta con Google · Eliminar cuenta con tableros bloqueantes · Eliminar cuenta (confirmación) |
| 13 · Errores | 404 · Sin conexión · Listado con aviso de acceso perdido |

Variantes de rol: Owner (kanban y detalle completos), Admin (igual que Owner salvo menú del tablero: solo "Salir"), Miembro (sin Miembros, Invitar, Agregar tarea/columna ni menús de columna; en el detalle, prioridad/fechas/asignado en solo lectura y sin eliminar).

**Capturas** (29 pantallas principales numeradas por flujo) en `docs/exports/01-…` a `29-…`.

**Revisión:** cada lote se revisó en captura a tamaño real (contraste, foco, estados). La skill Impeccable no pudo correr completa (pide `PRODUCT.md`, navegador y subagentes, y está pensada para código), así que la crítica se hizo manualmente. No se pasó ningún detector automático de contraste.

---

## 4. Datos de ejemplo
Coherentes con `contratos-api.md`: Jorge Díaz (usuario actual, `jorge@taskflow.app`, "Diseñador de producto"), Marco Ruiz, Ana Kim, Lucía Pérez; tableros Lanzamiento del producto (Owner), Rediseño del sitio (Admin), Operaciones Q4 (Owner), Contenido y blog (Miembro); "hoy" = viernes 16 OCT 2026; límite de columna "En curso" = 4 para mostrar el estado lleno.

---

## 5. Hallazgos (contradicciones y huecos — no resueltos)

### Entorno y documentación
1. No existía `inspiraciones/notas.md` ni `docs/diseño-interfaz.pen`; el estilo salió de las imágenes. El `.pen` se creó de cero (y se guardó en `docs/`).
2. `docs/CLAUDE.md` cita `docs/plan-desarrollo.md`, que no existe.
3. `contratos-api.md` usa colores de ejemplo del diseño anterior (`#FFD43B`, `#BFF05A`, `#7FE3F2`); no pertenecen a las paletas nuevas (ver §6).
4. `especificaciones-interaccion.md` conserva reglas del estilo anterior (sombra 2×2 en hover, anillo `#141414`, "acento amarillo"); ver §6.
5. `especificaciones-interaccion.md` §18 (pantallas pendientes) quedó casi cubierto; solo falta Términos y Privacidad, excluidas por decisión del usuario.

### Contradicciones entre el diseño pedido y los documentos
6. **Inicio:** el TRD §3.15 define cinco métricas (VENCEN HOY, VENCIDAS, ASIGNADAS A MÍ, TABLEROS, avance de hoy), PRÓXIMAS TAREAS, MIS TABLEROS con barra de progreso de subtareas y VENCEN ESTA SEMANA por día. El Inicio pedido por el usuario no muestra las métricas como tarjetas (solo "12 tareas pendientes · 3 vencen hoy" en la bienvenida), no muestra barra de progreso en "Mis tableros" (muestra pendientes y última actividad) y el calendario mensual necesita más datos que `GET /api/dashboard/summary` (solo semana actual).
7. **Sidebar:** la especificación incluye "Ajustes" y la campana; el diseño no tiene ítem Ajustes en el sidebar (se entra por el engranaje de la esquina) ni campana (el contador está en "Notificaciones").
8. **Aviso "Sin conexión":** la especificación dice banner rojo superior; el diseño lo muestra flotante abajo (decisión del usuario).
9. **Resultado de invitaciones al crear tablero:** el backlog (E3-1) y el TRD §3.1 devuelven el resultado por correo (invitado / omitido con motivo), pero se eliminó el diálogo y no hay otra pantalla que lo muestre.
10. **Arrastre:** la especificación pide el fantasma a 2°; el diseño lo inclina −2° (antihorario, convención de Pencil).

### Huecos en la especificación
11. **Etiquetas del tablero:** el backlog (E9) da CRUD a todos los miembros, pero ninguna pantalla decía dónde se gestionan. **Resuelto el 18 Oct:** diálogo «Etiquetas» desde el menú ⋯ del tablero, visible para todos los roles (5 pantallas nuevas en total con Editar tablero).
12. **Editar tablero** (solo Owner, con `BOARD_VERSION_CONFLICT`): **diseñado el 18 Oct** (diálogo y variante con conflicto de versión).
13. **Búsqueda:** el endpoint devuelve resultados agrupados (tareas, etiquetas, comentarios); se diseñó como desplegable. No hay especificación visual.
14. **Cronograma:** no define controles; se añadieron "‹ ›" y "Hoy" como navegación de rango, y una leyenda de prioridades. Las tareas sin fecha de inicio se dibujan como barra de un día.
15. **Contraseña:** ningún documento define botón mostrar/ocultar; el diseño usa un icono de ojo en los campos de Ajustes. En Restablecer contraseña solo hay un campo (no se menciona confirmación).
16. **Sidebar "TABLEROS":** ningún documento dice cuántos tableros recientes muestra ni con qué criterio.
17. **Mis tareas:** sin selector de orden (el TRD solo dice orden por vencimiento).
18. **Eliminar tablero:** el documento solo pide "confirmación explícita"; se usó una casilla, no escribir el nombre.
19. **Cuentas en eliminación:** la búsqueda por correo no dice qué estado mostrar (solo que no se puede invitar).
20. **Hecho vs. Completadas:** el tablero crea por defecto una columna "Hecho" y además existe la sección "Completadas"; una tarea en "Hecho" no está completada. Puede confundir.
21. **Invitaciones en el feed:** las invitaciones pendientes cuentan en el contador de no leídas y generan notificación, pero se muestran en el bloque superior, no en el feed; hay que decidir si aparecen en ambos.
22. **"Al día" atenuado al 60 %** (según la especificación) queda por debajo del contraste AA; el estado se entiende por el texto, pero conviene otra forma de atenuar.
23. **Confirmación de eliminar cuenta:** la pantalla supone que no hay tableros bloqueantes; en el mismo estado, el usuario de ejemplo sí los tiene (el flujo real pasa por la pantalla de bloqueo).
24. **Columna `Encabezado llena`:** el componente maestro dice "5/5"; las instancias usan "4/4".

### Datos de ejemplo
25. **Avance de hoy / vencen hoy:** una tarea con fecha de hoy ya "al día" cae en AL DÍA y no en HOY, así que "vencen hoy" (3) cuenta tareas de dos grupos (2 en HOY, 1 en AL DÍA). Conviene aclararlo en `docs/`.
26. **"Maquetar página de precios":** en el kanban figura asignada a Ana Kim, pero el Inicio y las notificaciones la tratan como tarea del usuario actual.
27. **Pantalla "sin columnas":** el sidebar conserva el contador 10 del tablero, que no cuadra con un tablero sin columnas.
28. **Notificaciones:** el Inicio y la pantalla de Notificaciones comparten los mismos avisos recientes; el feed completo muestra 11 de los 12 tipos (la invitación recibida está en el bloque superior).

### Pendientes de confirmar
29. El botón "Continuar con Google" no lleva logo (no se dibujan marcas de terceros); usar el botón oficial al implementar.
30. "Agregar columna" del kanban es un botón de solo "+" (244 px no alcanzan para texto); necesita `aria-label`.
31. (Resuelto) Había en la raíz `diseño-ui.pen` (315 B, vacío) y `generated.png`. Resuelto: se borró `diseño-ui.pen` y la imagen del hero se movió a `docs/assets/hero-inicio.png` (el `.pen` la referencia como `./assets/hero-inicio.png`).

---

## 6. Pasajes de `docs/` que mencionan el diseño anterior (a reescribir)

- `especificaciones-interaccion.md`
  - L3: "el diseño (`diseño-interfaz.pen`). Aquí se cierran los comportamientos que el mock no especifica".
  - L7: "Acento fijo (amarillo de marca) como en el diseño".
  - L10: "El mock es 1440 px de referencia".
  - L15: "sus componentes en el .pen no se actualizan".
  - L20: "línea de 2 px del acento" (revisar el color).
  - L52: "hover → sombra 2×2; presionado → sin sombra y desplazado 2 px; deshabilitado → … sin sombra".
  - L53: "anillo de 2 px `#141414`" (el foco nuevo es índigo `#4A3FD6`).
  - L66: "texto `#141414` sobre acentos…; `#5F5A50` solo para texto secundario" (ahora `#14172B` y `#5B6075`).
  - L119: "El `.pen` actual no incluye estos elementos" (casi todos ya están diseñados; ver §5.5).
- `contratos-api.md`: colores de ejemplo del diseño anterior en L90, 112, 122, 127, 147, 221, 222, 292, 322 y 323 (`#FFD43B`, `#BFF05A`, `#7FE3F2`).
- `esquema-backend.md` L77 y L188: "paleta fija de 8 colores" (tablero) y "6 acentos" (etiqueta): el número coincide con el diseño nuevo, pero los hex del diseño anterior ya no son válidos.
- `backlog.md` L3 y L162: referencias a `diseño-interfaz.pen` y a lo "que aún falta diseñar".
- `CLAUDE.md` L37 y L105: `diseño-interfaz.pen` y "Faltan pantallas en `diseño-interfaz.pen`".
