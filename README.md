# Campamento TCCD — Registro y Pagos

Sistema web para gestionar la inscripción y los pagos del campamento de jóvenes de **Templo Comunitario Casa de Dios (TCCD)**, Baní, RD. Sin pasarelas de pago: la gente transfiere desde su banco o paga en efectivo, reporta su comprobante, y el equipo lo verifica y administra.

![Estado](https://img.shields.io/badge/estado-listo%20para%20producci%C3%B3n-2f6dff)
![Frontend](https://img.shields.io/badge/frontend-React%2018-2f6dff)
![Backend](https://img.shields.io/badge/datos-Supabase-3ecf8e)
![Deploy](https://img.shields.io/badge/deploy-Netlify-05bdba)
![Licencia](https://img.shields.io/badge/licencia-MIT-555)

---

## ✨ Características

- **Inscripción pública** con clasificación automática por edad (precio según tier).
- **Portal del campista** (sin login): consulta tu saldo con tu **código** o recuperándolo con tu **WhatsApp**. Ve tus abonos, el estado de tus transferencias y tu **cabaña asignada**.
- **Reporte de transferencias** con referencia y/o captura del comprobante.
- **Panel de administración** con:
  - Resumen animado (anillo de progreso, barras por banco, estado de pagos).
  - Lista filtrable + búsqueda + exportación **CSV** e impresión en **PDF** (con logo).
  - Cola de **verificación** de transferencias (aprobar/rechazar).
  - Registro de pagos en **efectivo**.
  - **Alertas de cobro** con recordatorio por WhatsApp.
  - **Cabañas**: asignación, capacidad e impresión por cabaña (con columna de firma).
  - **Check-in** de asistencia y **notas internas** por persona.

---

## 🧱 Stack

- **Frontend:** React 18 (HTML autocontenido, JSX compilado en el navegador con Babel Standalone).
- **Datos / Auth / Storage:** [Supabase](https://supabase.com) (PostgreSQL + RLS).
- **Hosting:** [Netlify](https://www.netlify.com) (sitio estático + Functions).

> La app funciona en **modo demo** (datos de prueba en memoria) hasta que configures Supabase.

---

## 📁 Estructura del repositorio

```
campamento-tccd/
├── public/
│   └── index.html                 # La aplicación (todo en un archivo)
├── supabase/
│   └── schema.sql                 # Tablas, RLS, RPC, triggers y validaciones
├── netlify/
│   └── functions/
│       └── enviar-recordatorios.js # Ejemplo de función con secreto (service_role)
├── docs/
│   └── SEGURIDAD.md               # Informe e instrucciones de seguridad
├── .github/
│   ├── workflows/codeql.yml       # Análisis de seguridad automático (CodeQL)
│   └── dependabot.yml             # Vigilancia de dependencias
├── netlify.toml                   # Deploy + cabeceras de seguridad (CSP, HSTS…)
├── .env.example                   # Plantilla de variables de entorno
├── package.json
├── LICENSE
└── README.md
```

---

## 🚀 Puesta en marcha

### 1. Probar localmente (modo demo)
Abre `public/index.html` en el navegador. Funciona con datos de prueba.
Admin demo: `jhonfrer@tccd.do` / `campamento26`.

### 2. Conectar Supabase
1. Crea un proyecto en [supabase.com](https://supabase.com).
2. En **SQL Editor**, pega y ejecuta `supabase/schema.sql`.
3. En **Storage**, confirma el bucket privado `vouchers` (límite 5 MB, solo imágenes).
4. Crea tus admins en **Authentication** y agrégalos a la tabla `admins`.
5. En `public/index.html`, reemplaza `SUPABASE_URL` y `SUPABASE_KEY` por tu **URL** y tu **anon key** (la anon key es pública por diseño).

### 3. Desplegar en Netlify
1. Conecta este repo a Netlify.
2. Netlify lee `netlify.toml` (publish `public/`, functions `netlify/functions/`, cabeceras de seguridad).
3. Si usas la función de recordatorios, agrega las variables **secretas** en *Site settings → Environment variables* (ver `.env.example`).

---

## 🔐 Seguridad

Este proyecto pasó una auditoría documentada en **[`docs/SEGURIDAD.md`](docs/SEGURIDAD.md)**. Resumen:

- Sin SQL Injection (consultas parametrizadas vía Supabase) ni CSRF (auth por token, no cookies).
- XSS de generación de PDF **mitigado** con escape de HTML.
- Precio/tier/código se calculan en el **servidor** (trigger), no se confía en el cliente.
- Funciones `security definer` con `search_path` fijo; validaciones por `CHECK`.
- Cabeceras HTTP de seguridad (CSP, HSTS, nosniff, anti-clickjacking) en `netlify.toml`.

### Hallazgos conocidos (esperados al escanear)
Un analizador probablemente marcará estos puntos; son **conocidos y documentados**:
- **`unsafe-eval` / `unsafe-inline` en la CSP** y uso de **Babel Standalone por CDN**: necesarios porque el JSX se compila en el navegador. Mitigación: migrar a Vite (build) y removerlos (ver `docs/SEGURIDAD.md` §6).
- **`anon key` visible en el front**: es **pública por diseño**; no es una fuga. El secreto real (`service_role`) nunca está en el cliente.
- **Credenciales demo** (`campamento26`): solo aplican al modo demo; en producción se usa Supabase Auth.

---

## 🤖 Análisis automático

Al subir a GitHub se activan:
- **CodeQL** (`.github/workflows/codeql.yml`): escaneo de seguridad en cada push/PR y semanal. Resultados en la pestaña **Security → Code scanning**.
- **Dependabot** (`.github/dependabot.yml`): alertas y PRs de actualización de dependencias.

Para activar CodeQL: en GitHub → **Settings → Code security and analysis** → habilita *Code scanning*.

---

## 📦 Subir a GitHub (rápido)

```bash
git init
git add .
git commit -m "Campamento TCCD: app de registro y pagos"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/campamento-tccd.git
git push -u origin main
```

> El `.gitignore` ya excluye `.env` y `node_modules`. **Nunca** subas tu `.env` real ni la `service_role`.

---

## 📄 Licencia

MIT — ver [`LICENSE`](LICENSE). Cámbiala si prefieres otra.
