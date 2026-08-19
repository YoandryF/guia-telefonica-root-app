package com.rootecosystem.guia_telefonica

import android.accounts.Account
import android.accounts.AccountManager
import android.app.Activity
import android.app.ActivityManager
import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Settings
import android.speech.RecognizerIntent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val INSTALLER_CHANNEL = "guia_telefonica/installer"
    private val CONTACTS_CHANNEL = "guia_telefonica/contacts"
    private val SPEECH_CHANNEL = "guia_telefonica/speech"
    private val SYNC_CHANNEL = "guia_telefonica/sync"          // Control sync
    private val SYNC_EVENTS_CHANNEL = "guia_telefonica/sync_events"  // Progreso sync

    private val SPEECH_REQUEST_CODE = 7777
    private var speechResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Canal de control de sync (iniciar / cancelar / estado) ──────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startSync" -> {
                    SyncForegroundService.cancelRequested = false
                    val intent = Intent(this, SyncForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "cancelSync" -> {
                    SyncForegroundService.cancelRequested = true
                    val intent = Intent(this, SyncForegroundService::class.java).apply {
                        action = SyncForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "isRunning" -> {
                    // Verificar si el servicio está corriendo
                    val manager = getSystemService(android.app.ActivityManager::class.java)
                    @Suppress("DEPRECATION")
                    val running = manager.getRunningServices(Integer.MAX_VALUE)
                        .any { it.service.className == SyncForegroundService::class.java.name }
                    result.success(running)
                }
                "updateNotification" -> {
                    val texto = call.argument<String>("texto") ?: ""
                    // Encontrar el servicio activo y actualizar su notificación
                    // (Se hace via broadcast o directo si el servicio tiene referencia)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // ── EventChannel para recibir progreso del servicio en Flutter ──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SyncForegroundService.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    SyncForegroundService.eventSink = null
                }
            })

        // Canal de instalación APK
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path != null) result.success(installApk(path)) else result.error("INVALID_PATH", "Path is null", null)
                }
                "canInstallApk" -> result.success(canInstallApk())
                "requestInstallPermission" -> { requestInstallPermission(); result.success(true) }
                else -> result.notImplemented()
            }
        }

        // Canal de reconocimiento de voz (Intent nativo)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPEECH_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "recognize" -> {
                    val locale = call.argument<String>("locale") ?: "es"
                    val prompt = call.argument<String>("prompt") ?: "Habla ahora..."
                    startSpeechRecognition(locale, prompt, result)
                }
                "isAvailable" -> {
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    val available = intent.resolveActivity(packageManager) != null
                    result.success(available)
                }
                else -> result.notImplemented()
            }
        }

        // Canal de contactos
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTACTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncContact" -> {
                    val nombre = call.argument<String>("nombre") ?: ""
                    val apellido = call.argument<String>("apellido") ?: ""
                    val telefono = call.argument<String>("telefono") ?: ""
                    val reportado = call.argument<Boolean>("reportado") ?: false
                    CoroutineScope(Dispatchers.IO).launch {
                        val res = syncContact(nombre, apellido, telefono, reportado)
                        withContext(Dispatchers.Main) { result.success(res) }
                    }
                }
                "removeGuiaContacts" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val count = removeGuiaContacts()
                        withContext(Dispatchers.Main) { result.success(count) }
                    }
                }
                "removeContact" -> {
                    val telefono = call.argument<String>("telefono") ?: ""
                    CoroutineScope(Dispatchers.IO).launch {
                        val removed = removeContactByPhone(telefono)
                        withContext(Dispatchers.Main) { result.success(removed) }
                    }
                }
                "getPhoneContacts" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val contacts = getPhoneContacts()
                        withContext(Dispatchers.Main) { result.success(contacts) }
                    }
                }
                "getGuiaContactsInAgenda" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val contacts = getGuiaContactsInAgenda()
                        withContext(Dispatchers.Main) { result.success(contacts) }
                    }
                }
                "openContact" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    openContactByPhone(phone)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // === CONTACTOS ===

    private fun ensureAccount() {
        val am = AccountManager.get(this)
        val account = Account("Guía Telefónica", "com.rootecosystem.guia_telefonica")
        val accounts = am.getAccountsByType("com.rootecosystem.guia_telefonica")
        if (accounts.isEmpty()) {
            am.addAccountExplicitly(account, null, null)
        }
    }

    private fun syncContact(nombre: String, apellido: String, telefono: String, reportado: Boolean): String {
        ensureAccount()
        val cr = contentResolver
        val displayName = if (reportado) "⚠️ $nombre $apellido (Reportado)" else "$nombre $apellido"
        val cleanPhone = telefono.replace("-", "").replace(" ", "")

        // 1. Buscar si el teléfono ya existe en la agenda
        val existsByPhone = findContactByPhone(cr, cleanPhone)
        if (existsByPhone != null) {
            return "exists" // Ya tiene este número
        }

        // 2. Buscar por nombre similar
        val existsByName = findContactByName(cr, nombre, apellido)
        if (existsByName != null) {
            // Agregar número al contacto existente
            addPhoneToContact(cr, existsByName, cleanPhone)
            return "updated"
        }

        // 3. Crear contacto nuevo
        createContact(cr, displayName, nombre, apellido, cleanPhone)
        return "created"
    }

    private fun findContactByPhone(cr: ContentResolver, phone: String): Long? {
        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(phone))
        val cursor: Cursor? = cr.query(uri, arrayOf(ContactsContract.PhoneLookup._ID), null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                return it.getLong(0)
            }
        }
        return null
    }

    private fun findContactByName(cr: ContentResolver, nombre: String, apellido: String): Long? {
        val fullName = "$nombre $apellido"
        val cursor: Cursor? = cr.query(
            ContactsContract.Contacts.CONTENT_URI,
            arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME),
            "${ContactsContract.Contacts.DISPLAY_NAME} LIKE ?",
            arrayOf("%$fullName%"),
            null
        )
        cursor?.use {
            if (it.moveToFirst()) {
                return it.getLong(0)
            }
        }
        return null
    }

    private fun addPhoneToContact(cr: ContentResolver, contactId: Long, phone: String) {
        // Obtener rawContactId
        val cursor = cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts._ID),
            "${ContactsContract.RawContacts.CONTACT_ID} = ?",
            arrayOf(contactId.toString()),
            null
        )
        val rawContactId = cursor?.use {
            if (it.moveToFirst()) it.getLong(0) else null
        } ?: return

        val ops = ArrayList<ContentProviderOperation>()
        ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
            .withValue(ContactsContract.Data.RAW_CONTACT_ID, rawContactId)
            .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
            .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone)
            .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
            .withValue(ContactsContract.CommonDataKinds.Phone.LABEL, "Guía Telefónica")
            .build())
        cr.applyBatch(ContactsContract.AUTHORITY, ops)
    }

    private fun createContact(cr: ContentResolver, displayName: String, nombre: String, apellido: String, phone: String) {
        val ops = ArrayList<ContentProviderOperation>()

        // Crear raw contact
        ops.add(ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
            .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, "com.rootecosystem.guia_telefonica")
            .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, "Guía Telefónica")
            .build())

        // Nombre
        ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
            .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
            .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, displayName)
            .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, nombre)
            .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, apellido)
            .build())

        // Teléfono
        ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
            .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
            .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone)
            .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
            .build())

        // Nota: "Desde Guía Telefónica"
        ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
            .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Note.CONTENT_ITEM_TYPE)
            .withValue(ContactsContract.CommonDataKinds.Note.NOTE, "Contacto de Guía Telefónica")
            .build())

        cr.applyBatch(ContactsContract.AUTHORITY, ops)
    }

    private fun removeGuiaContacts(): Int {
        val cr = contentResolver
        // Batch delete: una sola operación SQL, sin loop
        val count = cr.delete(
            ContactsContract.RawContacts.CONTENT_URI,
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?",
            arrayOf("com.rootecosystem.guia_telefonica")
        )
        return count
    }

    private fun removeContactByPhone(phone: String): Boolean {
        val cr = contentResolver
        val cleanPhone = phone.replace("-", "").replace(" ", "")

        // Buscar el contacto por teléfono usando PhoneLookup (indexado, rápido)
        val lookupUri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(cleanPhone)
        )
        val cursor = cr.query(
            lookupUri,
            arrayOf(ContactsContract.PhoneLookup._ID),
            null, null, null
        )

        cursor?.use {
            while (it.moveToNext()) {
                val contactId = it.getLong(0)
                // Buscar el raw contact de NUESTRA cuenta para este contacto
                val rawCursor = cr.query(
                    ContactsContract.RawContacts.CONTENT_URI,
                    arrayOf(ContactsContract.RawContacts._ID),
                    "${ContactsContract.RawContacts.CONTACT_ID} = ? AND ${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?",
                    arrayOf(contactId.toString(), "com.rootecosystem.guia_telefonica"),
                    null
                )
                rawCursor?.use { rc ->
                    if (rc.moveToFirst()) {
                        val rawId = rc.getLong(0)
                        cr.delete(
                            ContactsContract.RawContacts.CONTENT_URI,
                            "${ContactsContract.RawContacts._ID} = ?",
                            arrayOf(rawId.toString())
                        )
                        return true
                    }
                }
            }
        }
        return false
    }

    private fun openContactByPhone(phone: String) {
        val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(phone))
        val cursor = contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup._ID), null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val contactId = it.getLong(0)
                val intent = Intent(Intent.ACTION_VIEW)
                intent.data = Uri.withAppendedPath(ContactsContract.Contacts.CONTENT_URI, contactId.toString())
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            }
        }
    }


    private fun getPhoneContacts(): List<Map<String, String>> {
        val contacts = mutableListOf<Map<String, String>>()
        val cr = contentResolver

        // Obtener IDs de raw contacts de NUESTRA cuenta (para excluirlos)
        val nuestrosIds = mutableSetOf<Long>()
        val rawCursor = cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts.CONTACT_ID),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?",
            arrayOf("com.rootecosystem.guia_telefonica"),
            null
        )
        rawCursor?.use {
            val idIdx = it.getColumnIndex(ContactsContract.RawContacts.CONTACT_ID)
            while (it.moveToNext()) {
                nuestrosIds.add(it.getLong(idIdx))
            }
        }

        // Leer todos los contactos con teléfono, excluyendo los nuestros
        val cursor = cr.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID
            ),
            null, null, null
        )
        cursor?.use {
            val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val phoneIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val contactIdIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            while (it.moveToNext()) {
                val contactId = it.getLong(contactIdIdx)
                if (nuestrosIds.contains(contactId)) continue // Excluir los nuestros
                val name = it.getString(nameIdx) ?: ""
                val phone = it.getString(phoneIdx) ?: ""
                if (phone.isNotEmpty()) contacts.add(mapOf("name" to name, "phone" to phone))
            }
        }
        return contacts
    }


    private fun getGuiaContactsInAgenda(): List<Map<String, String>> {
        val contacts = mutableListOf<Map<String, String>>()
        val cr = contentResolver

        // Query directa: obtener nombre y teléfono de contactos de nuestra cuenta
        // usando Data table filtrada por account_type via raw_contact_id
        val rawIds = mutableListOf<Long>()
        val rawCursor = cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts._ID),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ? AND ${ContactsContract.RawContacts.DELETED} = 0",
            arrayOf("com.rootecosystem.guia_telefonica"),
            null
        )
        rawCursor?.use {
            val idIdx = it.getColumnIndex(ContactsContract.RawContacts._ID)
            while (it.moveToNext()) {
                rawIds.add(it.getLong(idIdx))
            }
        }

        if (rawIds.isEmpty()) return contacts

        // Obtener todos los datos de una sola vez (batch query)
        // Procesamos en chunks de 100 para no exceder límite de SQL
        val namesMap = mutableMapOf<Long, String>()
        val phonesMap = mutableMapOf<Long, String>()

        for (chunk in rawIds.chunked(100)) {
            val placeholders = chunk.joinToString(",") { "?" }
            val args = chunk.map { it.toString() }.toTypedArray()

            // Nombres
            val nameCursor = cr.query(
                ContactsContract.Data.CONTENT_URI,
                arrayOf(ContactsContract.Data.RAW_CONTACT_ID, ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME),
                "${ContactsContract.Data.RAW_CONTACT_ID} IN ($placeholders) AND ${ContactsContract.Data.MIMETYPE} = ?",
                args + ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE,
                null
            )
            nameCursor?.use { nc ->
                val ridIdx = nc.getColumnIndex(ContactsContract.Data.RAW_CONTACT_ID)
                val nameIdx = nc.getColumnIndex(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME)
                while (nc.moveToNext()) {
                    namesMap[nc.getLong(ridIdx)] = nc.getString(nameIdx) ?: ""
                }
            }

            // Teléfonos
            val phoneCursor = cr.query(
                ContactsContract.Data.CONTENT_URI,
                arrayOf(ContactsContract.Data.RAW_CONTACT_ID, ContactsContract.CommonDataKinds.Phone.NUMBER),
                "${ContactsContract.Data.RAW_CONTACT_ID} IN ($placeholders) AND ${ContactsContract.Data.MIMETYPE} = ?",
                args + ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE,
                null
            )
            phoneCursor?.use { pc ->
                val ridIdx = pc.getColumnIndex(ContactsContract.Data.RAW_CONTACT_ID)
                val phoneIdx = pc.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (pc.moveToNext()) {
                    phonesMap[pc.getLong(ridIdx)] = pc.getString(phoneIdx) ?: ""
                }
            }
        }

        // Combinar
        for (rawId in rawIds) {
            val phone = phonesMap[rawId] ?: ""
            if (phone.isNotEmpty()) {
                contacts.add(mapOf(
                    "name" to (namesMap[rawId] ?: ""),
                    "phone" to phone
                ))
            }
        }

        return contacts
    }

    // === INSTALADOR APK ===

    private fun canInstallApk(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) packageManager.canRequestPackageInstalls() else true
    }

    private fun requestInstallPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            intent.data = Uri.parse("package:$packageName")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        }
    }

    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val intent = Intent(Intent.ACTION_VIEW)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
                intent.setDataAndType(uri, "application/vnd.android.package-archive")
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                intent.setDataAndType(Uri.fromFile(file), "application/vnd.android.package-archive")
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) { false }
    }

    // === RECONOCIMIENTO DE VOZ (Intent nativo) ===

    private fun startSpeechRecognition(locale: String, prompt: String, result: MethodChannel.Result) {
        speechResult = result
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
            putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        try {
            startActivityForResult(intent, SPEECH_REQUEST_CODE)
        } catch (e: Exception) {
            speechResult = null
            result.error("SPEECH_NOT_AVAILABLE", "Reconocimiento de voz no disponible: ${e.message}", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == SPEECH_REQUEST_CODE) {
            val pending = speechResult
            speechResult = null

            if (resultCode == Activity.RESULT_OK && data != null) {
                val results = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val text = results?.firstOrNull() ?: ""
                pending?.success(text)
            } else {
                // Usuario canceló o no se reconoció nada
                pending?.success("")
            }
        }
    }
}
