# AGENTS.md — card_manager (Flutter)

**Projet :** card_manager — Scan, classement et export de cartes physiques
**Dépôt :** https://github.com/New7ech/card_manager
**Statut :** Actions métier locales/offline ; comptes, rôles et statuts partagés via Firebase
**SDK Dart requis :** `^3.11.4` (voir `pubspec.yaml` — source de vérité en cas de doute)

> Ce fichier est lu par les agents de codage IA (OpenAI Codex, Google Antigravity, Claude Code via
> `@AGENTS.md`, etc.) avant de commencer une tâche. Il décrit la stack **réellement installée**,
> pas une architecture idéale. En cas de doute, le `pubspec.yaml` et le code source priment sur ce
> document — merci de le corriger si un écart est constaté.

---

## 🎯 Objectif du projet

Outil interne utilisé par des employés pour :

- Scanner/importer des photos de cartes, dédupliquer par hash, générer un PDF planche A4
  (action **Classement**).
- Dupliquer une carte unique en N copies pour impression (action **Duplication**).
- Scanner un PDF multi-pages via OCR natif Android pour en extraire les cartes/noms
  (action **OCR**).
- Recevoir automatiquement un rapport (PDF et/ou message) sur Telegram après chaque action.

## 🔧 Stack technique réelle

| Domaine | Détail |
|---|---|
| State management | **Aucun package dédié.** `StatefulWidget` + `setState()` partout. Ne pas introduire Riverpod, Provider, Bloc ou GetX sans demande explicite — ce serait un changement d'architecture majeur non sollicité. |
| Persistance | Journal d'activité et statistiques **100% locaux** dans `app_db.json` (chemin via `path_provider` → `getApplicationSupportDirectory()`), lu/écrit par `DatabaseService` (singleton `.instance`). Les profils utilisateurs sont dans Firestore (`users/{uid}`). Pas de Hive, pas de SQLite. |
| Authentification | Firebase Auth via `AuthService` (singleton `.instance`) : Email/Password avec email synthétique déterministe `${username.trim().toLowerCase()}@cardmanager.internal`, et connexion Google via `google_sign_in`. La session est restaurée par Firebase Auth (`currentUser` / `authStateChanges()`), sans expiration 24h maison. |
| Cloud / backend | Firebase est utilisé uniquement pour Auth + Firestore des comptes/rôles/statuts. Pas d'API REST propre à l'app. Autre communication externe : Telegram Bot API (`TelegramService`, via le package `http`) pour les notifications. |
| OCR | Pont natif Android via `MethodChannel('com.cardmanager.card_manager/ocr')` (traitement Kotlin + Tesseract côté natif, hors du code Dart). |
| PDF | Packages `pdf` (génération) + `pdfx` (rendu/preview). |
| Sélection de fichiers | `image_picker`, `file_picker`. |
| Sécurité | Firebase Auth hash les mots de passe côté serveur. `flutter_secure_storage` reste utilisé pour la configuration Telegram, `crypto` pour les hashes de doublons dans `HashService`, `permission_handler` pour les permissions locales. |
| UI | Material 3, `ColorScheme.fromSeed(seedColor: 0xFF1E3A8A)` — primaire bleu nuit `0xFF1E3A8A`, secondaire vert émeraude `0xFF10B981`. Textes et commentaires en français. |

## 🏗️ Architecture

```text
lib/
├── core/services/     # Singletons métier, appelés directement depuis les écrans (pas d'injection de dépendances) :
│   ├── auth_service.dart        # AuthService.instance — Firebase Auth + profils Firestore
│   ├── database_service.dart    # DatabaseService.instance — logs/stats JSON locaux, ActivityLog
│   ├── telegram_service.dart    # TelegramService.instance — notifications Bot API
│   ├── hash_service.dart        # Déduplication d'images par hash
│   ├── pdf_service.dart         # Génération des planches PDF
│   └── file_service.dart
├── screens/            # Écrans (StatefulWidget), pas de séparation domain/data/presentation :
│   ├── login_screen.dart / register_screen.dart
│   ├── home_screen.dart         # Contient MainMenuScreen (écran principal post-connexion)
│   └── admin_screen.dart        # Panneau d'administration (TabBarView)
└── main.dart           # Point d'entrée : init Firebase, init DatabaseService, routage via Firebase Auth
```

Contrairement à d'autres projets de l'auteur (ex. DriveAuto, en Clean Architecture + Riverpod),
card_manager reste volontairement simple : services singletons appelés directement et UI en
`StatefulWidget`/`setState()`. Firebase est limité aux comptes, rôles et statuts ; ne pas importer
Riverpod, Clean Architecture ou un backend applicatif sans demande explicite.

## 🔐 Modèle utilisateur (Firebase Auth + Firestore `users/{uid}`)

- Identité Firebase Auth Email/Password avec email synthétique déterministe :
  `${username.trim().toLowerCase()}@cardmanager.internal`
- Identité Firebase Auth Google pour les utilisateurs qui choisissent "Continuer avec Google".
- Profil Firestore `users/{uid}` :
  - `username`
  - `email` optionnel pour les comptes Google
  - `role` : `'admin'` | `'user'`
  - `status` : `'active'` | `'blocked'`
  - `provider` optionnel (ex. `'google.com'`)
  - `createdAt` : `FieldValue.serverTimestamp()`
- Le mot de passe n'est jamais stocké dans `app_db.json` ; Firebase Auth le gère côté serveur.
- `DatabaseService.User` reste utilisé comme modèle applicatif léger dans l'UI, mais les comptes ne
  sont plus la source de vérité du JSON local.
- Le premier administrateur est promu manuellement depuis la console Firebase en éditant le champ
  `role` du document Firestore `users/{uid}` à `'admin'` ; il n'existe plus d'écran dédié de
  configuration initiale.

> **Inscription = accès immédiat.** Un nouveau compte est créé `active` et la session est établie
> automatiquement dès l'inscription (pas d'attente de validation admin). Le statut `'blocked'`
> reste une information d'administration visible dans le tableau de bord, mais il ne doit pas
> bloquer la connexion ni la navigation après une authentification Firebase réussie.

## 📊 Journal d'activité (`ActivityLog`)

Chaque action métier mesurable appelle `DatabaseService.instance.logActivity(username, action, details, count: n)`.
Le champ `count` (`final int?`, nullable) porte la métrique numérique de l'action (ex. nombre de cartes)
pour alimenter `DatabaseService.stats` (`ActivityStats`) sans parser le texte libre de `details`.
Le journal détaillé reste une fenêtre glissante limitée à 2000 entrées ; les totaux permanents du
tableau de bord viennent de `ActivityStats` (cartes classées, duplications, OCR, top classeurs).
Les entrées créées avant l'ajout de `count` ont `count == null` et sont exclues des totaux agrégés.

Actions connues : `'Connexion'`, `'Deconnexion'`, `'Echec Connexion'`, `'Blocage'`, `'Deblocage'`, `'Inscription'`,
`'Classement'` (cartes classées), `'Duplication'` (copies générées), `'OCR'` (cartes scannées).

## 🧭 Panneau admin (`AdminScreen`, `lib/screens/admin_screen.dart`)

Onglets (4) : **Tableau de bord** (KPIs + top classeurs + activité récente locale),
**Utilisateurs** (StreamBuilder Firestore sur `users`, blocage/déblocage, changement de rôle,
suppression du profil Firestore), **Telegram** (configuration du bot), **Journal** (historique
local complet des logs).

## 🛠️ Commandes utiles

```bash
flutter pub get
flutter run
flutter build apk --release
flutter test
flutter analyze
```

## 📝 Règles pour les agents IA

- Respecter le style existant : commentaires et textes UI en français, `StatefulWidget`/`setState`
  uniquement (pas de nouvelle lib de state management).
- Ne jamais committer de secrets (token Telegram, futures clés API tierces) — suivre le pattern déjà
  en place dans `telegram_service.dart`.
- Ne pas réintroduire de stockage local des mots de passe ni de session maison : les comptes passent
  par Firebase Auth, et les rôles/statuts par Firestore `users/{uid}`.
- Toute nouvelle métrique doit passer par le champ structuré `count` de `ActivityLog`, jamais
  uniquement par du texte libre dans `details`.
- Avant de modifier le flux d'authentification ou le panneau admin, relire ce fichier ; après une
  modification qui change le comportement décrit ici, mettre ce fichier à jour dans le même commit.
