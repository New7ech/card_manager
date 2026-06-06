package com.cardmanager.card_manager.model

/**
 * Modèle représentant les données extraites d'une carte d'étudiant individuelle.
 *
 * @property nom Nom de famille extrait en majuscules (ex: ZONGO).
 * @property prenom Prénom(s) extrait(s) (ex: GENEVIÈVE).
 * @property pageNumber Index de la page d'origine dans le PDF (commence à 1).
 * @property cardIndex Index de la position de la carte sur la page (1 à 10, disposition 2x5).
 */
data class StudentCard(
    val nom: String,
    val prenom: String,
    val pageNumber: Int,
    val cardIndex: Int
) {
    // Une carte est considérée comme valide si elle ne contient pas les valeurs par défaut d'échec d'extraction
    val isRecognized: Boolean
        get() = nom.isNotBlank() && 
                prenom.isNotBlank() && 
                nom != "Non reconnu" && 
                prenom != "Non reconnu"
}
