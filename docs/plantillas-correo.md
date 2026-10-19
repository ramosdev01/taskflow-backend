# Plantillas de correo — Task Flow v1

**Fecha:** 16 Oct 2026 · Correos transaccionales de v1 (SMTP). Remitente: `TaskFlow <no-reply@taskflow.app>`. Texto plano con enlaces; en producción se puede envolver en la plantilla HTML de marca. Complemento de `trd.md` (§3.9, §3.11, §3.12 y §3.17) y `esquema-backend.md`.

Los correos de v1 son solo estos cuatro. Las notificaciones de la app (asignaciones, menciones, vencimientos, resumen semanal, etc.) **no se envían por correo**: viven dentro de la aplicación (ADR-008).

## 1. Verificación de correo
- **Cuándo se envía:** al registrarse (cuenta LOCAL), al reenviar la verificación y cuando una cuenta LOCAL cambia su correo (el mensaje va a la **dirección nueva**).
- **Asunto:** `Verifica tu correo para activar TaskFlow`
- **Cuerpo:**
```
Hola {nombre}:

Confirma que este correo es tuyo para terminar de configurar tu cuenta.

Verifica mi correo → {enlace}
(El enlace vence en 24 horas.)

Si no creaste una cuenta en TaskFlow, ignora este mensaje.

— El equipo de TaskFlow
```
- Reenvío: mismo correo con asunto `Tu nuevo enlace de verificación` y una línea extra: "Pediste un enlace nuevo; el anterior dejó de ser válido."

## 2. Restablecer contraseña
- **Cuándo se envía:** al solicitar "Olvidé mi contraseña". La solicitud responde igual exista o no la cuenta; el correo solo se envía si la cuenta existe (incluidas las cuentas en eliminación pendiente, para que puedan recuperarlas).
- **Asunto:** `Restablece tu contraseña de TaskFlow`
- **Cuerpo:**
```
Hola {nombre}:

Recibimos una solicitud para restablecer tu contraseña.

Crear contraseña nueva → {enlace}
(El enlace vence en 60 minutos. Al cambiarla, se cerrarán todas tus sesiones abiertas.)

Si no lo solicitaste, no hace falta que hagas nada: tu contraseña actual sigue vigente.

— El equipo de TaskFlow
```

## 3. Invitación a un tablero
- **Cuándo se envía:** al crear una invitación (también las iniciales al crear un tablero). Solo se invita a usuarios que ya tienen cuenta.
- **Asunto:** `{invitador} te invitó al tablero «{tablero}» en TaskFlow`
- **Cuerpo:**
```
Hola {nombre}:

{invitador} te invitó a colaborar en el tablero «{tablero}».

Abre TaskFlow para aceptar o rechazar la invitación → {enlace}
(La invitación vence en 5 días.)

Recuerda: las invitaciones se aceptan únicamente dentro de la app, en Notificaciones.

— El equipo de TaskFlow
```
> El enlace abre la app (no acepta la invitación por sí solo). La invitación también aparece como notificación dentro de la app.

## 4. Eliminación de cuenta programada
- **Cuándo se envía:** al solicitar la eliminación de la cuenta (`DELETE /api/users/me`), una vez confirmada la solicitud. `{fecha_limite}` es `recoveryDeadline` (solicitud + 30 días), mostrada en la zona horaria de la aplicación.
- **Asunto:** `Tu cuenta de TaskFlow se eliminará en 30 días`
- **Cuerpo:**
```
Hola {nombre}:

Programaste la eliminación de tu cuenta. Su acceso quedó pausado y permanecerá en "eliminación pendiente" hasta el {fecha_limite}.

Si cambias de opinión, inicia sesión en TaskFlow antes de esa fecha y elige "Recuperar cuenta".

Inicia sesión → {enlace}

Después del {fecha_limite}, tu cuenta y tus datos personales se eliminarán de forma definitiva y ya no podrás recuperarlos.

Si no fuiste tú quien lo solicitó, inicia sesión, recupera tu cuenta y cambia tu contraseña.

— El equipo de TaskFlow
```
> Durante el periodo de gracia el usuario no entra a la aplicación: al iniciar sesión solo ve la vista de recuperación (TRD §3.11).

## 5. Notas de implementación
- Los tokens van solo en la URL (nunca en el asunto ni en el cuerpo visible). El token en claro solo viaja en el correo; en la base de datos se guarda su hash SHA-256.
- Los enlaces se construyen con `FRONTEND_URL`.
- Los correos de verificación y restablecimiento y sus reenvíos están sujetos al límite de 3 envíos por cada 10 minutos (ADR-002); superado el límite se responde 429 `RATE_LIMITED`.
- Fallos de envío no revierten la operación principal (se registran y se reportan en observabilidad).
- En local, Mailpit captura todos los correos (SMTP en el puerto 1025, interfaz web en el 8025).
- Variables de reemplazo: `{nombre}`, `{enlace}`, `{invitador}`, `{tablero}`, `{fecha_limite}`.
