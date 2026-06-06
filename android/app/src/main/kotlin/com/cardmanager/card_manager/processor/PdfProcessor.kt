package com.cardmanager.card_manager.processor

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.graphics.createBitmap
import com.cardmanager.card_manager.model.StudentCard
import com.googlecode.tesseract.android.TessBaseAPI
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException

// États de progression de l'extraction
sealed class ExtractionProgress {
    object Loading : ExtractionProgress()
    data class PageDone(val currentPage: Int, val totalPages: Int, val cards: List<StudentCard>) : ExtractionProgress()
    data class Complete(val cards: List<StudentCard>) : ExtractionProgress()
    data class Error(val message: String) : ExtractionProgress()
}

class PdfProcessor(private val context: Context) {

    private val tag = "[PdfProcessor]"
    
    // Expressions régulières super-flexibles et non-gloutonnes pour le parsing multi-colonnes
    private val flexibleNomRegex = Regex("""\b(?:N[o0]m|Norn|No[mn]e)(?:\b|(?=[A-ZÀ-Ü\s[:.;,\-—_]]))\s*[:.;,\-—_]?\s*(.*?)(?=\b(?:Nom|Norn|Nome|Prénom|Prenom)\b|$)""", RegexOption.IGNORE_CASE)
    private val flexiblePrenomRegex = Regex("""\b(?:Pr[éêe]n[o0]m|Pr[éêe]norn)(?:s|\(s\))?(?:\b|(?=[A-ZÀ-Ü\s[:.;,\-—_]]))\s*[:.;,\-—_]?\s*(.*?)(?=\b(?:Nom|Norn|Nome|Prénom|Prenom)\b|$)""", RegexOption.IGNORE_CASE)

    /**
     * Lit un PDF et extrait les informations des cartes d'étudiant via un Flow asynchrone.
     */
    fun extractStudentCards(uri: Uri): Flow<ExtractionProgress> = flow {
        emit(ExtractionProgress.Loading)
        val allCards = mutableListOf<StudentCard>()
        var pfd: ParcelFileDescriptor? = null
        var pdfRenderer: PdfRenderer? = null

        try {
            // Étape 1 : Vérification et copie du fichier de langue
            val tessDataPath = prepareTesseractData()

            // Étape 2 : Ouverture du PDF
            pfd = context.contentResolver.openFileDescriptor(uri, "r")
                ?: throw IOException("Impossible d'ouvrir le fichier PDF sélectionné.")
            pdfRenderer = PdfRenderer(pfd)
            val totalPages = pdfRenderer.pageCount

            // Étape 3 : Traitement page par page
            for (pageIndex in 0 until totalPages) {
                // Timeout de 30 secondes maximum par page pour éviter tout gel du thread
                val pageCards = withTimeout(30000L) {
                    processPage(pdfRenderer, pageIndex, tessDataPath)
                }
                allCards.addAll(pageCards)
                emit(ExtractionProgress.PageDone(pageIndex + 1, totalPages, allCards))
            }

            emit(ExtractionProgress.Complete(allCards))

        } catch (e: Exception) {
            Log.e(tag, "Erreur globale de traitement PDF/OCR", e)
            emit(ExtractionProgress.Error(e.localizedMessage ?: "Une erreur inattendue est survenue"))
        } finally {
            try {
                pdfRenderer?.close()
                pfd?.close()
            } catch (e: Exception) {
                Log.e(tag, "Erreur lors de la fermeture des ressources PDF", e)
            }
        }
    }.flowOn(Dispatchers.IO)

    /**
     * Effectue le traitement d'une page du PDF en exécutant les stratégies OCR en parallèle.
     */
    private suspend fun processPage(pdfRenderer: PdfRenderer, pageIndex: Int, tessDataPath: String): List<StudentCard> = coroutineScope {
        Log.d(tag, "Début du traitement de la Page ${pageIndex + 1}")
        val page = pdfRenderer.openPage(pageIndex)
        
        // Rendu à 300 DPI pour une précision maximale de l'OCR
        val dpiScale = 300f / 72f
        val width = (page.width * dpiScale).toInt()
        val height = (page.height * dpiScale).toInt()
        
        val pageBitmap = createBitmap(width, height)
        // Fond blanc obligatoire pour éviter le texte noir sur fond transparent
        pageBitmap.eraseColor(Color.WHITE)
        page.render(pageBitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        page.close()

        // Exécution en parallèle de trois stratégies d'OCR
        val fullPageJob = async(Dispatchers.IO) {
            runFullPageOcr(tessDataPath, pageBitmap, pageIndex + 1)
        }
        
        val croppedJob = async(Dispatchers.IO) {
            runCroppedOcr(tessDataPath, pageBitmap, pageIndex + 1, width, height, useMargins = false)
        }

        val croppedMarginedJob = async(Dispatchers.IO) {
            runCroppedOcr(tessDataPath, pageBitmap, pageIndex + 1, width, height, useMargins = true)
        }

        val fullPageResults = fullPageJob.await()
        val croppedResults = croppedJob.await()
        val croppedMarginedResults = croppedMarginedJob.await()

        // Libération immédiate de la mémoire de la page
        pageBitmap.recycle()

        // Évaluation du meilleur résultat : on garde celui qui a reconnu le plus grand nombre de cartes
        val fullPageScore = fullPageResults.count { it.isRecognized }
        val croppedScore = croppedResults.count { it.isRecognized }
        val marginedScore = croppedMarginedResults.count { it.isRecognized }

        Log.d(tag, "[OCR] Page ${pageIndex + 1} - Score Global: $fullPageScore/10 | Score Découpé: $croppedScore/10 | Score Margé: $marginedScore/10")

        val bestResults = listOf(
            fullPageResults to fullPageScore,
            croppedResults to croppedScore,
            croppedMarginedResults to marginedScore
        ).maxByOrNull { it.second }?.first ?: fullPageResults

        bestResults
    }

    /**
     * Stratégie 1 : OCR sur la page complète.
     */
    private fun runFullPageOcr(tessDataPath: String, bitmap: Bitmap, pageNumber: Int): List<StudentCard> {
        val tessApi = TessBaseAPI().apply {
            init(tessDataPath, "fra")
            setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
        }
        return try {
            tessApi.setImage(bitmap)
            val fullText = tessApi.getUTF8Text() ?: ""
            parseTextToCards(fullText, pageNumber)
        } catch (e: Exception) {
            Log.e(tag, "[OCR Global] Erreur OCR sur page $pageNumber", e)
            emptyList()
        } finally {
            tessApi.recycle()
        }
    }

    /**
     * Stratégie 2 & 3 : OCR avec découpage en 10 zones (2 colonnes x 5 lignes).
     */
    private fun runCroppedOcr(
        tessDataPath: String,
        pageBitmap: Bitmap,
        pageNumber: Int,
        width: Int,
        height: Int,
        useMargins: Boolean
    ): List<StudentCard> {
        val tessApi = TessBaseAPI().apply {
            init(tessDataPath, "fra")
            setPageSegMode(TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK)
        }
        val cards = mutableListOf<StudentCard>()

        // Calcul des marges si demandé
        val leftMargin = if (useMargins) (width * 0.04f).toInt() else 0
        val rightMargin = if (useMargins) (width * 0.04f).toInt() else 0
        val topMargin = if (useMargins) (height * 0.06f).toInt() else 0
        val bottomMargin = if (useMargins) (height * 0.06f).toInt() else 0

        val usableWidth = width - leftMargin - rightMargin
        val usableHeight = height - topMargin - bottomMargin

        val cardWidth = usableWidth / 2
        val cardHeight = usableHeight / 5

        try {
            for (i in 0 until 10) {
                val col = i % 2
                val row = i / 2
                
                val x = leftMargin + col * cardWidth
                val y = topMargin + row * cardHeight
                
                val w = if (col == 1) width - rightMargin - x else cardWidth
                val h = if (row == 4) height - bottomMargin - y else cardHeight

                // Inset de 8% pour éviter les bordures de la carte
                val insetX = (w * 0.08f).toInt()
                val insetY = (h * 0.08f).toInt()
                
                val cropX = x + insetX
                val cropY = y + insetY
                val cropW = w - (insetX * 2)
                val cropH = h - (insetY * 2)

                // Sécurité pour éviter les coordonnées négatives ou hors-limites
                val safeX = cropX.coerceIn(0, width - 1)
                val safeY = cropY.coerceIn(0, height - 1)
                val safeW = cropW.coerceAtMost(width - safeX)
                val safeH = cropH.coerceAtMost(height - safeY)

                if (safeW > 0 && safeH > 0) {
                    val cardBitmap = Bitmap.createBitmap(pageBitmap, safeX, safeY, safeW, safeH)
                    tessApi.setImage(cardBitmap)
                    val cardText = tessApi.getUTF8Text() ?: ""
                    cardBitmap.recycle()

                    val parsedCard = parseSingleCardText(cardText, pageNumber, i + 1)
                    cards.add(parsedCard)
                } else {
                    cards.add(StudentCard("Non reconnu", "Non reconnu", pageNumber, i + 1))
                }
            }
        } catch (e: Exception) {
            Log.e(tag, "[OCR Découpé] Erreur lors du traitement par zone (useMargins=$useMargins)", e)
        } finally {
            tessApi.recycle()
        }
        return cards
    }

    /**
     * Parse le texte brut de la page complète pour en extraire des cartes.
     * Gère intelligemment la lecture par colonnes horizontales ou verticales.
     */
    private fun parseTextToCards(text: String, pageNumber: Int): List<StudentCard> {
        val cards = mutableListOf<StudentCard>()
        val lines = text.split("\n")
        var pendingNoms = listOf<String>()
        var cardCount = 0

        for (i in lines.indices) {
            val line = cleanOcrText(lines[i])
            
            val nomMatches = flexibleNomRegex.findAll(line).toList()
            if (nomMatches.isNotEmpty()) {
                if (pendingNoms.isNotEmpty()) {
                    pendingNoms.forEach { nom ->
                        if (cardCount < 10) {
                            cardCount++
                            cards.add(StudentCard(nom, "Non reconnu", pageNumber, cardCount))
                        }
                    }
                }
                
                pendingNoms = nomMatches.map { match ->
                    var valNom = cleanValue(match.groupValues[1])
                    if (valNom.isBlank() && i + 1 < lines.size) {
                        val nextLine = cleanOcrText(lines[i + 1])
                        if (!isLabel(nextLine)) {
                            valNom = cleanValue(nextLine)
                        }
                    }
                    valNom.uppercase()
                }
                continue
            }

            val prenomMatches = flexiblePrenomRegex.findAll(line).toList()
            if (prenomMatches.isNotEmpty()) {
                val currentPrenoms = prenomMatches.map { match ->
                    var valPrenom = cleanValue(match.groupValues[1])
                    if (valPrenom.isBlank() && i + 1 < lines.size) {
                        val nextLine = cleanOcrText(lines[i + 1])
                        if (!isLabel(nextLine)) {
                            valPrenom = cleanValue(nextLine)
                        }
                    }
                    valPrenom
                }

                val maxIndex = maxOf(pendingNoms.size, currentPrenoms.size)
                for (j in 0 until maxIndex) {
                    val nom = pendingNoms.getOrNull(j) ?: "Non reconnu"
                    val prenom = currentPrenoms.getOrNull(j) ?: "Non reconnu"
                    if (cardCount < 10) {
                        cardCount++
                        cards.add(StudentCard(nom, prenom, pageNumber, cardCount))
                    }
                }
                pendingNoms = emptyList()
            }
        }

        if (pendingNoms.isNotEmpty()) {
            pendingNoms.forEach { nom ->
                if (cardCount < 10) {
                    cardCount++
                    cards.add(StudentCard(nom, "Non reconnu", pageNumber, cardCount))
                }
            }
        }
        
        while (cards.size < 10) {
            cards.add(StudentCard("Non reconnu", "Non reconnu", pageNumber, cards.size + 1))
        }
        return cards.take(10)
    }

    /**
     * Parse le texte extrait d'une unique zone de carte.
     */
    private fun parseSingleCardText(cardText: String, pageNumber: Int, cardIndex: Int): StudentCard {
        val lines = cardText.split("\n")
        
        val nom = extractValueWithFallback(lines, flexibleNomRegex)
        val prenom = extractValueWithFallback(lines, flexiblePrenomRegex)
        
        return StudentCard(
            nom = if (nom.isNullOrBlank()) "Non reconnu" else cleanValue(nom).uppercase(),
            prenom = if (prenom.isNullOrBlank()) "Non reconnu" else cleanValue(prenom),
            pageNumber = pageNumber,
            cardIndex = cardIndex
        )
    }

    private fun extractValueWithFallback(lines: List<String>, labelRegex: Regex): String? {
        for (i in lines.indices) {
            val line = cleanOcrText(lines[i])
            val match = labelRegex.find(line)
            if (match != null) {
                val value = match.groupValues[1].trim()
                if (value.isNotBlank()) {
                    return value
                }
                if (i + 1 < lines.size) {
                    val nextLine = cleanOcrText(lines[i + 1])
                    if (!isLabel(nextLine) && nextLine.isNotBlank()) {
                        return nextLine
                    }
                }
            }
        }
        return null
    }

    private fun cleanValue(value: String): String {
        var cleaned = value.replace(Regex("""^[^\p{L}\d]+"""), "")
            .replace(Regex("""[^\p{L}\d]+$"""), "")
            .trim()
            
        // Supprime les résidus d'OCR courants représentant des deux-points mal reconnus (ex: "i ", "l ", "1 ", "o ", "c ", "s ", "t ")
        // au début de la valeur si c'est suivi d'un espace ou d'une lettre majuscule
        cleaned = cleaned.replace(Regex("""^[il1ocstIL1OCST]\s+"""), "")
            .replace(Regex("""^[:.;,\-—_]+"""), "")
            .trim()
            
        return cleaned
    }

    private fun isLabel(text: String): Boolean {
        val clean = text.lowercase()
        return clean.contains("nom") || clean.contains("norn") || clean.contains("prénom") || clean.contains("prenom")
    }

    private fun cleanOcrText(text: String): String {
        return text.replace(Regex("[|_@]"), "")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    /**
     * Vérifie et copie le fichier linguistique requis. Lance une erreur explicite s'il est manquant.
     */
    private suspend fun prepareTesseractData(): String = withContext(Dispatchers.IO) {
        val tesseractDir = File(context.filesDir, "tesseract")
        val tessDataDir = File(tesseractDir, "tessdata")
        if (!tessDataDir.exists()) {
            tessDataDir.mkdirs()
        }
        
        val traineddataFile = File(tessDataDir, "fra.traineddata")
        if (!traineddataFile.exists()) {
            // Vérification de la présence du fichier dans les assets
            try {
                context.assets.open("tessdata/fra.traineddata").use { input ->
                    FileOutputStream(traineddataFile).use { output ->
                        input.copyTo(output)
                    }
                }
                Log.d(tag, "fra.traineddata initialisé avec succès dans le stockage local.")
            } catch (e: Exception) {
                // Erreur explicite à destination de l'utilisateur
                throw FileNotFoundException(
                    "Le pack de langue OCR français (fra.traineddata) est absent du dossier 'assets/tessdata/' du projet.\n\n" +
                    "Veuillez télécharger le fichier 'fra.traineddata' et le déposer dans :\n" +
                    "app/src/main/assets/tessdata/fra.traineddata"
                )
            }
        }
        tesseractDir.absolutePath
    }
}
