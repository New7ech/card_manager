package com.cardmanager.card_manager.viewmodel

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cardmanager.card_manager.model.StudentCard
import com.cardmanager.card_manager.processor.ExtractionProgress
import com.cardmanager.card_manager.processor.PdfProcessor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// Modèle de l'état de l'UI
data class ScanUiState(
    val isScanning: Boolean = false,
    val progressPercent: Float = 0f,
    val progressText: String = "",
    val studentCards: List<StudentCard> = emptyList(),
    val errorMessage: String? = null,
    val isComplete: Boolean = false
)

class ScanViewModel(application: Application) : AndroidViewModel(application) {

    private val pdfProcessor = PdfProcessor(application.applicationContext)

    private val _uiState = MutableStateFlow(ScanUiState())
    val uiState: StateFlow<ScanUiState> = _uiState.asStateFlow()

    /**
     * Lance le traitement OCR sur le document PDF spécifié.
     */
    fun startScan(uri: Uri) {
        viewModelScope.launch {
            _uiState.update { 
                it.copy(
                    isScanning = true, 
                    errorMessage = null, 
                    isComplete = false,
                    studentCards = emptyList(),
                    progressPercent = 0f,
                    progressText = "Démarrage..."
                ) 
            }

            try {
                pdfProcessor.extractStudentCards(uri).collect { progress ->
                    when (progress) {
                        is ExtractionProgress.Loading -> {
                            _uiState.update {
                                it.copy(progressText = "Vérification des dépendances OCR...")
                            }
                        }
                        is ExtractionProgress.PageDone -> {
                            val percent = progress.currentPage.toFloat() / progress.totalPages.toFloat()
                            _uiState.update {
                                it.copy(
                                    progressPercent = percent,
                                    progressText = "Traitement page ${progress.currentPage} / ${progress.totalPages}...",
                                    studentCards = progress.cards
                                )
                            }
                        }
                        is ExtractionProgress.Complete -> {
                            _uiState.update {
                                it.copy(
                                    isScanning = false,
                                    isComplete = true,
                                    progressPercent = 1.0f,
                                    progressText = "Extraction terminée ! ${progress.cards.size} cartes lues.",
                                    studentCards = progress.cards
                                )
                            }
                        }
                        is ExtractionProgress.Error -> {
                            _uiState.update {
                                it.copy(
                                    isScanning = false,
                                    isComplete = false,
                                    errorMessage = progress.message
                                )
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isScanning = false,
                        isComplete = false,
                        errorMessage = e.localizedMessage ?: "Erreur inattendue durant l'exécution"
                    )
                }
            }
        }
    }

    /**
     * Réinitialise le module d'OCR pour traiter un autre fichier.
     */
    fun reset() {
        _uiState.value = ScanUiState()
    }

    /**
     * Efface les messages d'erreurs pour éviter l'apparition répétitive de Snackbars.
     */
    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }
}
