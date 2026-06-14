# Informe de seguridad — App de Campamento TCCD

Auditoría del código actual (`campamento.html` + `supabase-schema.sql`) y guía paso a paso.
Lenguaje sin rodeos: qué está bien, qué arreglé, y qué te toca a ti.

---

## 0. Lo más importante primero: tu "API key" NO es un secreto

Tienes miedo de que al hacer **Ctrl + U** se vea tu llave de Supabase. La verdad técnica:

- La que va en el front es la **`anon key`**, y **está diseñada para ser pública**. Vivir en el HTML es lo normal y correcto. Verla en el código fuente **no es una vulnerabilidad**.
- Lo que protege tus datos **no es esconder esa llave**, sino las **políticas RLS** (Row Level Security) de la base de datos. Ya las tienes activadas.
- El secreto de verdad es la **`service_role key`**. Esa **NUNCA** va en el front. Si la tienes en el HTML, bórrala ya. (Revisé tu código: **no está**, bien.)

**Conclusión:** montar un backend solo para "esconder la anon key" sería esfuerzo perdido y mala ingeniería. No lo necesitas. El backend/serverless sí se justifica cuando manejes un **secreto real** (la `service_role`, o el token de una API de WhatsApp/correo). Ese caso lo cubro en el paso 5.

---

## 1. Hallazgos y severidad

| # | Hallazgo | Severidad | Estado |
|---|----------|-----------|--------|
| 1 | **XSS almacenado** en los PDF: el nombre/alergias/cabaña se inyectaban como HTML al imprimir | **Alta** | ✅ Corregido |
| 2 | El cliente decidía **precio, tier y código** al inscribirse (manipulable vía la API) | **Alta** | ✅ Corregido (servidor manda) |
| 3 | Funciones `security definer` sin `search_path` fijo (riesgo de secuestro) | Media | ✅ Corregido |
| 4 | Sin límites de longitud/formato en los datos que entran | Media | ✅ Corregido (constraints) |
| 5 | `anon key` visible en el front | Informativo | ✅ Es normal (ver paso 0) |
| 6 | Credenciales **demo** (`campamento26`) visibles en el código | Baja | ⚠️ Solo afectan al modo demo |
| 7 | Búsqueda por WhatsApp expone datos básicos a quien sepa el número | Media (privacidad) | ⚠️ Decisión de diseño |
| 8 | Babel-en-navegador obliga a una CSP débil (`unsafe-eval`) | Media | ⚠️ Se resuelve compilando (paso 6) |

---

## 2. SQL Injection — ¿estás expuesto? No, y aquí está el porqué

- Usas el cliente de Supabase (`.insert()`, `.eq()`, `.rpc()`). **Todas son consultas parametrizadas** (prepared statements) por debajo. No concatenas SQL con texto del usuario en ningún lado. Eso te protege de inyección SQL **por diseño**.
- Tus funciones RPC (`get_registration_by_code`, etc.) usan **parámetros** (`p_code`, `p_phone`), no pegan strings. Correcto.
- Endurecí las funciones `security definer` fijándoles `set search_path = pg_catalog, public`. Sin esto, un atacante con permiso de crear objetos podría "secuestrar" qué función `lower()` o `md5()` se ejecuta. Ahora quedan blindadas.

**Regla de oro:** mientras no escribas SQL armado con `+` y texto del usuario, sigues a salvo. Si algún día necesitas SQL dinámico en una función, usa `format()` con `%L` (literal) y `%I` (identificador), nunca concatenación.

---

## 3. XSS (Cross-Site Scripting) — corregido

- **React te protege solo** en la interfaz: todo lo que pintas con `{variable}` se escapa automáticamente. No usas `dangerouslySetInnerHTML`. Bien.
- **El hueco real** estaba en los PDF: construías el HTML pegando texto (`'<td>'+r.name+'</td>'`) y lo escribías con `document.write`. Si alguien se inscribía con el nombre `<img src=x onerror=...>`, ese código se **ejecutaba en el navegador del admin** al imprimir (XSS almacenado, el peor tipo).
- **Arreglo aplicado:** agregué una función `esc()` que convierte `< > & " '` en entidades HTML, y la apliqué a **todos** los campos del usuario en los tres generadores (`pdfList`, `cabinSection`, `printDoc`). Ahora un nombre con `<script>` se imprime como texto, no se ejecuta.

## 4. CSRF — no aplica (y por qué)

- CSRF ataca apps que autentican con **cookies de sesión** automáticas. Supabase autentica con un **token JWT que viaja en una cabecera** (`Authorization: Bearer`), guardado en `localStorage`. El navegador **no lo envía solo** en peticiones de otros sitios, así que el CSRF clásico no tiene por dónde entrar.
- No tienes endpoints propios con formularios+cookies. Si algún día agregas un backend con cookies de sesión, ahí sí tendrás que usar tokens anti-CSRF y `SameSite=Lax/Strict`.

## 5. Validación estricta — ahora la hace el servidor

El front validaba (edad, teléfono), pero **un atacante puede saltarse el front** y llamar la API directo con la anon key. Por eso moví la validación crítica a la base de datos:

- **Trigger `reg_guard`** (nuevo): cuando entra una inscripción, **el servidor** fija el `tier`, el `total` (precio) y genera el `código`. Aunque alguien mande `total: 0` o `tier: "gratis"`, **se ignora**. El precio ya no se puede manipular.
- **Constraints** (nuevos): largo de nombre (2–80), formato de teléfono, límites de correo/alergias/notas, y monto de transferencia tope (evita reportes absurdos).
- **Control compensatorio que ya tenías y es oro:** ningún pago se acredita solo. El campista solo *reporta*; un admin **verifica contra el banco** y aprueba. Eso neutraliza los reportes falsos.

> Pendiente tuyo: en el panel de Supabase → Storage → bucket `vouchers`, pon **límite de 5 MB** y **MIME types** `image/png, image/jpeg, image/webp`. Así nadie sube ejecutables ni archivos gigantes.

---

## 6. Variables de entorno (`.env`) — paso a paso

El HTML de una sola pieza con Babel no usa `.env` (no hay paso de compilación). Para usar `.env` **de verdad** y de paso endurecer la CSP, conviene migrar a **Vite** (es rápido, 15 min):

1. Instala Node y crea el proyecto:
   ```bash
   npm create vite@latest campamento -- --template react
   cd campamento && npm install @supabase/supabase-js
   ```
2. Crea un archivo **`.env`** en la raíz (este archivo NO se sube a git):
   ```
   VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
   VITE_SUPABASE_ANON_KEY=tu_anon_key
   ```
3. Crea **`.gitignore`** con (como mínimo):
   ```
   .env
   .env.local
   node_modules
   dist
   ```
4. En el código lees las variables así:
   ```js
   const url = import.meta.env.VITE_SUPABASE_URL;
   const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
   ```
5. En **Netlify → Site settings → Environment variables**, agrega las mismas `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`. Netlify las inyecta al compilar.
6. Build command `npm run build`, publish directory `dist`.

> Ojo: como `VITE_*` termina en el bundle del navegador, **la anon key seguirá siendo visible** (y está bien, ver paso 0). El `.env` aquí sirve para **no hardcodear** y manejar distinto dev/prod, no para "ocultar" la anon key.

**Beneficio extra:** con Vite el JSX se **compila antes**, así que puedes **borrar Babel Standalone** y quitar `'unsafe-eval'` y `'unsafe-inline'` de la CSP → seguridad mucho más fuerte.

---

## 7. ¿Cuándo SÍ necesitas backend/serverless? (con secreto real)

Cuando manejes algo que **sí es secreto** y no puede ver el cliente. Ejemplo típico para ti: enviar recordatorios automáticos por una **API de WhatsApp/correo** que requiere un token privado, o hacer tareas con la `service_role`.

Eso va en una **Netlify Function**, donde el secreto vive en variables de entorno del servidor y **nunca** baja al navegador. Te dejé un ejemplo en `netlify/functions/enviar-recordatorios.js` y el `.env.example`. El secreto (`SUPABASE_SERVICE_ROLE`, `WHATSAPP_TOKEN`) se configura en Netlify y jamás aparece en Ctrl + U.

---

## 8. Cabeceras de seguridad HTTP — listas para usar

Te dejé el archivo **`netlify.toml`** (ponlo en la raíz del repo). Incluye:

- **Strict-Transport-Security (HSTS):** obliga HTTPS.
- **X-Content-Type-Options: nosniff:** el navegador no adivina tipos.
- **X-Frame-Options / frame-ancestors:** nadie incrusta tu web en un iframe ajeno (anti-clickjacking, "anti-clonado" visual).
- **Referrer-Policy / Permissions-Policy:** menos fugas de info y APIs apagadas.
- **Content-Security-Policy (CSP):** define de dónde se pueden cargar scripts/estilos/conexiones. Hoy permite unpkg, jsdelivr, Google Fonts y tu proyecto Supabase. Como Babel necesita `eval`, lleva `unsafe-eval`; cuando migres a Vite (paso 6), quítalo y la CSP queda fuerte.

Verifica tus cabeceras tras desplegar en: `https://securityheaders.com`.

---

## 9. Checklist final antes de lanzar

- [ ] Reemplazar `SUPABASE_URL` y `SUPABASE_KEY` por tu proyecto real (anon key, no service_role).
- [ ] Quitar/ignorar el bloque `DEMO_ADMINS` en producción (en prod ya se usa Supabase Auth, pero mejor no dejar las claves demo en el código).
- [ ] Confirmar que **RLS está activo** en las 4 tablas (el schema lo hace).
- [ ] Storage `vouchers`: privado + límite 5 MB + solo imágenes.
- [ ] Subir `netlify.toml` a la raíz del repo.
- [ ] Crear admins reales en Supabase Auth y en la tabla `admins`.
- [ ] (Recomendado) Activar CAPTCHA/anti-abuso en Supabase para el insert público.
- [ ] (Recomendado) Migrar a Vite para `.env` real y CSP fuerte sin `unsafe-eval`.
- [ ] Probar en `https://securityheaders.com` y revisar la consola del navegador.

---

### Resumen de una línea
Tu mayor riesgo real era el **XSS en los PDF** (ya corregido) y **confiar en el cliente para el precio** (ya pasado al servidor). La anon key visible **no es el problema**; tu escudo es **RLS + validación en el servidor + cabeceras HTTP**, y eso ya quedó montado.
