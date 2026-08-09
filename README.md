# 📱 Guía Telefónica Colaborativa

App Flutter (Android) para gestión colaborativa de contactos con sincronización en la nube, sistema de reportes y bot de Telegram. Parte del **ROOT Ecosystem**.

## ⬇️ Descargar

[Última versión (APK)](https://github.com/YoandryF/guia-telefonica-root-app/releases/latest)

## 🤖 Bot Telegram

[@GuiaTelefonicaRootBot](https://t.me/GuiaTelefonicaRootBot) — [Repo](https://github.com/YoandryF/guia-telefonica-root-bot)

## ✨ Funcionalidades

**Usuario:**
- Lista offline-first + sincronización automática
- Búsqueda por texto y voz
- Filtro por categorías + Lista Negra
- Detalle: llamar, SMS, WhatsApp, mapa, QR, compartir
- Favoritos, notas privadas, contactos recientes
- Escanear agenda (detectar riesgos)
- Identificador de llamadas (sync con agenda nativa)
- Avalar y reclamar contactos reportados
- Onboarding, tema oscuro/claro, auto-update

**Admin:**
- Dashboard métricas
- Aprobar/rechazar con botones
- Exportar CSV/JSON/PDF, importar CSV/JSON
- Reportes agrupados + filtros + 2 niveles (🟡/🔴)
- Gestión: categorías, admins, auditoría, configuración
- Banear reportadores, verificar contactos (✅)

**Seguridad:**
- Rate-limit reportes (configurable)
- Trust score + auto-aprobación
- Detección ataques coordinados
- Expiración automática (cron)

## 🛠️ Stack

Flutter 3.22 | SQLite | Supabase | Render.com | GitHub Actions

## 🔧 Build

```bash
flutter pub get
flutter build apk --release
```

## 📁 Estructura

```
lib/
├── config/     # Supabase config
├── models/     # Contacto
├── providers/  # Theme
├── services/   # DB local, Supabase, export, update, sync
└── screens/    # 20+ pantallas
```

## 📄 Licencia

MIT — [Yoandry Freire](https://github.com/YoandryF) / ROOT Ecosystem
