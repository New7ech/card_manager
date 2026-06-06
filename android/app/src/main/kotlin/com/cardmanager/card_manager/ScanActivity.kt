package com.cardmanager.card_manager

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.cardmanager.card_manager.model.StudentCard
import com.cardmanager.card_manager.ui.ScanScreen
import org.json.JSONArray
import org.json.JSONObject

class ScanActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ScanScreen(
                onFinish = { cards ->
                    val resultIntent = Intent()
                    
                    val jsonResult = JSONObject()
                    jsonResult.put("success", true)
                    jsonResult.put("total_cards", cards.size)
                    
                    val studentsArray = JSONArray()
                    cards.forEach { card ->
                        if (card.isRecognized) {
                            val studentJson = JSONObject()
                            studentJson.put("nom", card.nom)
                            studentJson.put("prenom", card.prenom)
                            studentJson.put("page", card.pageNumber)
                            studentJson.put("index", card.cardIndex)
                            studentsArray.put(studentJson)
                        }
                    }
                    jsonResult.put("students", studentsArray)
                    
                    // Génération du texte de rapport brut
                    val reportText = buildReportText(cards)
                    jsonResult.put("report_text", reportText)
                    
                    resultIntent.putExtra("ocr_result", jsonResult.toString())
                    setResult(Activity.RESULT_OK, resultIntent)
                    finish()
                }
            )
        }
    }

    private fun buildReportText(cards: List<StudentCard>): String {
        val total = cards.size
        val recognized = cards.count { it.isRecognized }
        val unrecognized = total - recognized
        val sb = StringBuilder()
        sb.append("RAPPORT D'EXTRACTION OCR\n")
        sb.append("========================\n")
        sb.append("Total cartes détectées : $total\n")
        sb.append("Cartes reconnues : $recognized\n")
        sb.append("Cartes non reconnues : $unrecognized\n")
        sb.append("------------------------\n\n")
        cards.forEachIndexed { i, card ->
            val status = if (card.isRecognized) "OK" else "ÉCHEC"
            sb.append("${i+1}. NOM: ${card.nom} | PRÉNOM: ${card.prenom} (Page ${card.pageNumber}, Pos ${card.cardIndex}) [$status]\n")
        }
        return sb.toString()
    }
}
