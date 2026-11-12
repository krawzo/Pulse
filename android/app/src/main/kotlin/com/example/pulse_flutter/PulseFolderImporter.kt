package com.example.pulse_flutter

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.concurrent.Executors

/** Imports a user-selected SAF tree into app-owned, persistent, read-only source copies. */
class PulseFolderImporter(private val activity: Activity) {
    private val requestCode = 49210
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val preferences = activity.getSharedPreferences("pulse_mobile_folder", 0)
    private var pendingPick: MethodChannel.Result? = null

    fun pick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("PICKER_BUSY", "A seleção de pasta já está aberta.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            pendingPick = null
            result.error("FOLDER_PICKER", error.message, null)
        }
    }

    fun onActivityResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != requestCode) return false
        val reply = pendingPick ?: return true
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            reply.success(null)
            return true
        }
        val tree = data.data!!
        try {
            activity.contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (error: Exception) {
            reply.error("FOLDER_PERMISSION", error.message, null)
            return true
        }
        runImport(tree, reply, saveSelection = true)
        return true
    }

    fun refresh(result: MethodChannel.Result) {
        val saved = preferences.getString("tree_uri", null)
        if (saved == null) {
            result.error("NO_FOLDER", "Nenhuma pasta foi selecionada no Android.", null)
            return
        }
        runImport(Uri.parse(saved), result, saveSelection = false)
    }

    private fun runImport(tree: Uri, reply: MethodChannel.Result, saveSelection: Boolean) {
        worker.execute {
            try {
                val root = targetFor(tree)
                val count = importTree(tree, root)
                if (count == 0) throw IllegalStateException("A pasta não contém arquivos MP3 acessíveis.")
                if (saveSelection) preferences.edit().putString("tree_uri", tree.toString()).apply()
                main.post { reply.success(root.absolutePath) }
            } catch (error: Exception) {
                main.post { reply.error("FOLDER_IMPORT", error.message, null) }
            }
        }
    }

    private fun targetFor(tree: Uri): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(tree.toString().toByteArray(Charsets.UTF_8))
            .take(12)
            .joinToString("") { "%02x".format(it) }
        return File(activity.filesDir, "PulseFlutter/folder_sources/$digest")
    }

    private fun importTree(tree: Uri, root: File): Int {
        if (!root.exists() && !root.mkdirs()) throw IllegalStateException("Não foi possível criar a biblioteca local.")
        val resolver = activity.contentResolver
        val queue = ArrayDeque<Pair<String, File>>()
        val visited = mutableSetOf<String>()
        val retained = mutableSetOf<String>()
        queue.add(DocumentsContract.getTreeDocumentId(tree) to root)
        var count = 0

        while (queue.isNotEmpty()) {
            val (parentId, destination) = queue.removeFirst()
            if (!visited.add(parentId)) continue
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
            resolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val typeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
                while (cursor.moveToNext()) {
                    val id = cursor.getString(idColumn) ?: continue
                    val originalName = cursor.getString(nameColumn) ?: continue
                    val name = safeName(originalName)
                    val type = cursor.getString(typeColumn) ?: ""
                    if (type == DocumentsContract.Document.MIME_TYPE_DIR) {
                        val childDirectory = File(destination, name)
                        if (!childDirectory.exists() && !childDirectory.mkdirs()) {
                            throw IllegalStateException("Não foi possível criar a pasta $name.")
                        }
                        queue.add(id to childDirectory)
                    } else if (name.endsWith(".mp3", ignoreCase = true) || type == "audio/mpeg") {
                        val outputName = if (name.endsWith(".mp3", ignoreCase = true)) name else "$name.mp3"
                        val target = File(destination, outputName)
                        val temporary = File(destination, "$outputName.pulse-part")
                        val document = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                        try {
                            val input = resolver.openInputStream(document)
                                ?: throw IllegalStateException("Não foi possível ler $originalName.")
                            input.use { source ->
                                FileOutputStream(temporary).use { output -> source.copyTo(output) }
                            }
                            if (target.exists() && !target.delete()) {
                                throw IllegalStateException("Não foi possível atualizar $originalName.")
                            }
                            if (!temporary.renameTo(target)) {
                                throw IllegalStateException("Não foi possível salvar $originalName.")
                            }
                            retained.add(target.absolutePath)
                            count++
                        } finally {
                            if (temporary.exists()) temporary.delete()
                        }
                    }
                }
            } ?: throw IllegalStateException("Não foi possível ler uma das pastas selecionadas.")
        }

        if (count > 0) {
            root.walkBottomUp().forEach { entry ->
                if (entry.isFile && !retained.contains(entry.absolutePath)) entry.delete()
                if (entry.isDirectory && entry != root && entry.list()?.isEmpty() == true) entry.delete()
            }
        }
        return count
    }

    private fun safeName(value: String): String {
        val cleaned = value.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_").trim()
        return if (cleaned.isEmpty() || cleaned == "." || cleaned == "..") "untitled" else cleaned
    }

    fun dispose() {
        pendingPick?.error("ACTIVITY_CLOSED", "A seleção de pasta foi interrompida.", null)
        pendingPick = null
        worker.shutdownNow()
    }
}
