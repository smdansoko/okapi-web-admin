# Déploiement du serveur OKAPI Web Admin sur Render.com

Ce guide vous permet d'obtenir une URL **permanente** (qui ne change jamais)
pour le serveur admin web, avec **persistance des données** (les bases
SQLite ne sont pas perdues entre les redémarrages/déploiements).

## Étape 1 — Créer un compte Render (gratuit)

1. Allez sur https://render.com
2. Cliquez sur "Get Started" et créez un compte (avec votre email ou un
   compte GitHub existant).

## Étape 2 — Récupérer le code

Vous avez reçu (ou allez recevoir) une archive `okapi_web_admin.tar.gz`.
Deux options pour la mettre sur Render :

### Option A (recommandée) — Via GitHub
1. Créez un nouveau repo sur https://github.com/new (nom au choix, ex.
   `okapi-web-admin`), en le laissant **vide** (ne cochez pas "Add a
   README").
2. Sur votre ordinateur, décompressez l'archive, puis dans le dossier :
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/VOTRE_UTILISATEUR/okapi-web-admin.git
   git push -u origin main
   ```
3. Sur Render : "New +" → "Web Service" → "Build and deploy from a Git
   repository" → connectez votre compte GitHub → sélectionnez le repo.
4. Render détecte automatiquement le fichier `render.yaml` inclus dans
   l'archive et pré-remplit toute la configuration (Docker, disque
   persistant, variable de clé secrète). Vérifiez puis cliquez sur
   "Apply"/"Create Web Service".

### Option B — Sans GitHub (upload direct)
Render nécessite normalement un dépôt Git. Si vous ne voulez vraiment
pas utiliser GitHub, une alternative simple sans Git est **Railway.app**
(supporte l'upload de dossier/zip direct) ou un VPS classique (voir plus
bas). Pour rester sur Render, la voie GitHub (option A) reste la plus
simple et gratuite.

## Étape 3 — Vérifier la configuration (si `render.yaml` n'est pas détecté)

Si vous configurez manuellement au lieu d'utiliser `render.yaml` :
- **Runtime** : Docker
- **Dockerfile Path** : `./Dockerfile`
- **Plan** : Starter (le plus petit payant, ~7$/mois) — le plan gratuit
  ne supporte pas les disques persistants, nécessaires pour ne pas perdre
  les données à chaque redéploiement.
- **Disque persistant** :
  - Nom : `okapi-data`
  - Chemin de montage (`Mount Path`) : `/app/data`
  - Taille : 1 GB (largement suffisant, augmentable plus tard)
- **Variables d'environnement** :
  - `OKAPI_SECRET_KEY` : générez une valeur aléatoire longue (ou laissez
    Render la générer automatiquement si vous utilisez `render.yaml`)
  - `PORT` : `5070` (Render la définit généralement lui-même, mais on la
    fixe explicitement par sécurité)

## Étape 4 — Premier déploiement

1. Cliquez sur "Create Web Service" (ou "Apply" si vous utilisez
   `render.yaml`).
2. Render va construire l'image Docker (2-5 minutes) puis démarrer le
   service.
3. Une fois "Live" affiché, Render vous donne une URL permanente du type :
   `https://okapi-web-admin.onrender.com`

## Étape 5 — Initialiser les données

**IMPORTANT** : les fichiers `data/*.db` sont exclus du dépôt Git
(`.gitignore`) — au premier démarrage sur Render, les bases seront
**vides**. Il faut soit :
- Réimporter les données existantes (via les scripts d'import déjà
  présents : `import_legacy_excel.py`), soit
- Migrer les bases SQLite actuelles vers le nouveau serveur (copier les
  fichiers `data/wcag.db`, `data/simandou.db`, `data/smb.db` via un accès
  shell Render, ou via un petit script de transfert).

Dites-moi si vous voulez que je prépare cette migration une fois l'URL
Render obtenue — je peux écrire un script qui transfère toutes les
données actuelles vers le nouveau serveur en une seule fois.

## Étape 6 — Mettre à jour l'application mobile

Une fois l'URL Render stable obtenue, il faut remplacer l'URL du sandbox
temporaire dans le code mobile par la nouvelle URL permanente, puis
reconstruire l'APK/AAB :

Fichier : `lib/services/sync_service.dart`
```dart
static const String _defaultServerUrl = 'https://okapi-web-admin.onrender.com';
```

Revenez me voir avec l'URL Render exacte pour que je fasse cette
modification et rebuild l'APK/AAB final.

## Coût estimé

- Plan Starter Render : ~7 USD/mois (nécessaire pour le disque
  persistant — le plan gratuit "sleep" après inactivité et n'a pas de
  disque, donc perte de données à chaque redémarrage — à éviter en
  production).
- Alternative moins chère : un petit VPS (Contabo, Hetzner) à partir de
  ~4-5 EUR/mois, avec plus de configuration manuelle nécessaire (Docker,
  reverse proxy, certificat SSL via Let's Encrypt).
