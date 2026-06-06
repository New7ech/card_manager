package com.cardmanager.card_manager.utils

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import com.cardmanager.card_manager.model.StudentCard
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object ReportExporter {

    private const val tag = "[ReportExporter]"

    /**
     * Génère et partage le rapport textuel au format TXT.
     */
    fun exportReport(context: Context, cards: List<StudentCard>) {
        val dateFormat = SimpleDateFormat("dd/MM/yyyy HH:mm:ss", Locale.getDefault())
        val dateString = dateFormat.format(Date())

        val report = StringBuilder().apply {
            append("=========================================\n")
            append("      RAPPORT D'EXTRACTION OCR CARTES    \n")
            append("=========================================\n")
            append("Date d'extraction : $dateString\n")
            append("Fichier traité : Document PDF d'étudiants\n")
            append("Nombre total de cartes : ${cards.size}\n")
            append("Cartes reconnues : ${cards.count { it.isRecognized }}\n")
            append("Cartes non reconnues : ${cards.count { !it.isRecognized }}\n")
            append("-----------------------------------------\n\n")
            
            append(String.format(Locale.getDefault(), "%-5s | %-20s | %-20s | %s\n", "N°", "NOM", "PRÉNOM", "PAGE (POSITION)"))
            append("----------------------------------------------------------------------\n")

            cards.forEachIndexed { index, card ->
                append(
                    String.format(
                        Locale.getDefault(),
                        "%-5d | %-20s | %-20s | Page %d (Pos %d)\n",
                        index + 1,
                        if (card.isRecognized) card.nom else "NON RECONNU",
                        if (card.isRecognized) card.prenom else "NON RECONNU",
                        card.pageNumber,
                        card.cardIndex
                    )
                )
            }
            append("----------------------------------------------------------------------\n")
            append("Fin du rapport d'extraction.\n")
        }

        try {
            // Création du fichier temporaire dans le cache privé
            val cacheFile = File(context.cacheDir, "Rapport_Cartes_Etudiants.txt")
            FileWriter(cacheFile).use { writer ->
                writer.write(report.toString())
            }

            // Génération de l'Uri sécurisé via le FileProvider
            val authority = "com.cardmanager.card_manager.fileprovider"
            val uri: Uri = FileProvider.getUriForFile(context, authority, cacheFile)

            // Lancement de l'intention de partage
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, "Rapport d'extraction cartes d'étudiant")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            val chooser = Intent.createChooser(shareIntent, "Partager le rapport via...")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) 
            context.startActivity(chooser)

        } catch (e: Exception) {
            Log.e(tag, "Échec lors de la génération ou du partage du rapport", e)
        }
    }
}
