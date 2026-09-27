# Paperless-GPT

Déploiement Argo CD de Paperless-GPT v0.28.0. Les appels API et les liens vers Paperless-NGX utilisent tous `https://paperless.lafranque.net` via le Gateway public.
Paperless-NGX assure déjà l'OCR classique. Paperless-GPT peut aussi refaire l'OCR avec un modèle de vision lorsque les paramètres `VISION_LLM_PROVIDER` et `VISION_LLM_MODEL` sont définis.

## Avant la synchronisation

Créer deux entrées dans OpenBao (ne pas placer leurs valeurs dans Git) :

| Chemin | Clés requises |
| --- | --- |
| `k8s/dorado/applications/paperless-gpt` | `PAPERLESS_API_TOKEN`, `LLM_PROVIDER=openai`, `LLM_MODEL=gpt-4o-mini`, `OPENAI_API_KEY` ; pour l'OCR IA, ajouter `VISION_LLM_PROVIDER=openai` et `VISION_LLM_MODEL=gpt-4o-mini` |
| `k8s/dorado/applications/paperless-gpt-auth` | `users`, contenant une ligne htpasswd `nom_utilisateur:hash_SHA` ; l'ExternalSecret la place sous la clé Kubernetes `.htpasswd` |

Le jeton Paperless-NGX doit appartenir à un compte autorisé à lire et modifier les documents voulus. La clé du fournisseur de modèle ne doit pas être envoyée dans une conversation ni ajoutée au dépôt. Pour créer la valeur `users`, utiliser `htpasswd -ns nom_utilisateur` et enregistrer sa sortie dans OpenBao. Envoy Gateway prend en charge le hachage SHA pour cette authentification. `gpt-4o-mini` est le modèle initial proposé pour la classification ; il peut être changé par la seule valeur `LLM_MODEL` dans OpenBao.

Avec l'API OpenAI officielle, **ne pas définir** `OPENAI_BASE_URL` : Paperless-GPT utilise l'endpoint OpenAI par défaut. Définir cette clé uniquement pour un fournisseur compatible, avec son URL de base (par exemple `https://openrouter.ai/api/v1`). Les deux modèles peuvent partager la même `OPENAI_API_KEY` ; `gpt-4o-mini` accepte aussi les images. L'OCR IA est déclenché par le tag `paperless-gpt-ocr-auto` ou depuis l'interface de Paperless-GPT ; il n'est pas appliqué à tous les documents simplement parce que le modèle est configuré.

Créer un CNAME `paperless-gpt.lafranque.net` vers `paperless.lafranque.net` afin de joindre le même Gateway. Le certificat générique du Gateway couvre ce nom. L'accès HTTPS exige une géolocalisation IP `FR` et une authentification HTTP Basic. Sa règle propre remplace l'exception du Gateway pour les plages privées. La redirection HTTP hérite de la règle GeoIP du Gateway. Le service Kubernetes est uniquement de type `ClusterIP`.

## Reprise du prompt Paperless-AI

Le prompt fourni a été réparti dans les cinq modèles de métadonnées du dossier `prompts/` : titre, tags, correspondant, date et type. Au premier démarrage, un conteneur d'initialisation les copie dans `/app/prompts` sans remplacer une version déjà présente. Les autres modèles de l'application restent ceux fournis par Paperless-GPT. Les modifications faites ensuite dans **Settings → Prompts** sont conservées sur le PVC ; une mise à jour des fichiers Git ne remplace pas automatiquement ces modifications.

Les modèles utilisent Go `text/template`, par exemple `{{.Content}}` pour le texte du document et `{{.AvailableTags}}` pour les tags existants. Chaque modèle attend sa propre réponse, pas l'objet JSON global de Paperless-AI. La date et le type sont pris en charge. Le type doit déjà exister dans Paperless-NGX. Paperless-GPT n'écrit pas un champ de langue du document dans Paperless-NGX ; le prompt demande seulement que les titres et tags suivent la langue du document. La consigne sur les adresses empêche de suggérer un tag d'adresse s'il est hors sujet, mais ne retire pas un tag déjà présent. Les tags techniques de traitement peuvent aussi s'ajouter aux quatre tags thématiques demandés.

## Vérification après synchronisation

Vérifier que les deux `ExternalSecret` sont prêts, que le déploiement et ses trois PVC sont opérationnels, puis ouvrir l'URL depuis une IP française avec les identifiants Basic Auth. Une IP hors France doit être refusée par le Gateway. Commencer par attribuer le tag `paperless-gpt` à un document et approuver manuellement ses suggestions. Pour traiter ensuite automatiquement les nouveaux documents, créer dans Paperless-NGX un workflow qui leur ajoute `paperless-gpt-auto`. Ne pas ajouter ce tag aux documents existants avant d'avoir validé le prompt et le modèle.
