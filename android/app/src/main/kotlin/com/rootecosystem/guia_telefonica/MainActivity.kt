package com.rootecosystem.guia_telefonica

import android.accounts.Account
import android.accounts.AccountManager
import android.content.ContentProviderOperation
import android.content.ContentResolver
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val INSTALLER_CHANNEL = "guia_telefonica/installer"
    private val CONTACTS_CHANNEL = "guia_telefonica/contacts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

        // Canal de contactos
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTACTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncContact" -> {
                    val nombre = call.argument<String>("nombre") ?: ""
                    val apellido = call.argument<String>("apellido") ?: ""
                    val telefono = call.argument<String>("telefono") ?: ""
                    val reportado = call.argument<Boolean>("reportado") ?: false
                    val res = syncContact(nombre, apellido, telefono, reportado)
                    result.success(res)
                }
                "removeGuiaContacts" -> {
                    val count = removeGuiaContacts()
                    result.success(count)
                }
                "getPhoneContacts" -> {
                    val contacts = getPhoneContacts()
                    result.success(contacts)
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
        val cursor = cr.query(
            ContactsContract.RawContacts.CONTENT_URI,
            arrayOf(ContactsContract.RawContacts._ID),
            "${ContactsContract.RawContacts.ACCOUNT_TYPE} = ?",
            arrayOf("com.rootecosystem.guia_telefonica"),
            null
        )
        var count = 0
        cursor?.use {
            while (it.moveToNext()) {
                val id = it.getLong(0)
                cr.delete(
                    ContactsContract.RawContacts.CONTENT_URI,
                    "${ContactsContract.RawContacts._ID} = ?",
                    arrayOf(id.toString())
                )
                count++
            }
        }
        return count
    }

    private fun getPhoneContacts(): List<Map<String, String>> {
        val contacts = mutableListOf<Map<String, String>>()
        val cursor = contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
            null, null, null
        )
        cursor?.use {
            val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val phoneIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (it.moveToNext()) {
                val name = it.getString(nameIdx) ?: ""
                val phone = it.getString(phoneIdx) ?: ""
                if (phone.isNotEmpty()) contacts.add(mapOf("name" to name, "phone" to phone))
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
}
