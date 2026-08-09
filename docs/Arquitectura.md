# Arquitectura

## Diagrama

```
┌────────────────────────────────────────────────────┐
│           USUARIO (Android)                        │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐   │
│  │ SQLite   │  │ Supabase │  │ Admin Panel   │   │
│  │ (offline)│◄─┤ Client   │  │ (autenticado) │   │
│  └──────────┘  └──────────┘  └───────────────┘   │
└────────────────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────┐
│              SUPABASE (Nube)                        │
│  PostgreSQL + Auth + RLS + Storage + RPC           │
└────────────────────────────────────────────────────┘
                      │
                      ▼
┌────────────────────────────────────────────────────┐
│         BOT TELEGRAM (Render.com)                   │
│  Python + Flask health + Polling                   │
│  UptimeRobot → /health cada 5 min                 │
└────────────────────────────────────────────────────┘
```

## Flujo de datos

1. Usuario consulta → SQLite local (instantáneo)
2. Sincronización → descarga nuevos aprobados de Supabase
3. Registro → envía a Supabase como "pendiente"
4. Admin aprueba → Supabase actualiza → sync actualiza SQLite
5. Reportes → RPC con rate-limit + trust score

## Tablas Supabase

| Tabla | Propósito |
|---|---|
| contactos | Directorio principal |
| admins | Usuarios administradores |
| historial | Log de auditoría |
| reportes | Reportes de riesgo |
| categorias | Clasificación |
| usuarios_telegram | Usuarios del bot |
| avales | Contra-reportes positivos |
| reclamos | Derecho a réplica |
| configuracion | Valores dinámicos |
| usuarios_baneados | Reportadores bloqueados |
| valoraciones | Estrellas por contacto |

## Decisiones técnicas

| Decisión | Razón |
|---|---|
| Polling (no webhook) | Bot necesita main thread para señales |
| SQLite offline-first | Instantáneo sin internet |
| RPC SECURITY DEFINER | Bypass RLS para funciones públicas |
| Account Authenticator | Cuenta visible en Ajustes Android |
| GitHub Releases | Distribución sin Play Store |
| Configuración dinámica | Cambiar valores sin redesplegar |
