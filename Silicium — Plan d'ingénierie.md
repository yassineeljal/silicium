# Silicium — Plan d'ingénierie

Oct 31, 2026 · @jalwach

## 1. Vision du produit

**Silicium** est une application macOS native qui montre l'intérieur du Mac comme une maquette 3D vivante : chaque composante (puce, cœurs CPU, GPU, mémoire, SSD, batterie, réseau, ventilation) s'illumine selon sa charge et son état de santé. Une icône dans la barre des menus donne un score global en un clic.

Le nom vient du matériau des puces Apple Silicon ; il se prononce pareil en français et en anglais.

### Objectifs (v1.0)

1. Visualiser en 3D, à 60 images/s, l'état en temps réel de 8 familles de composantes.
2. Afficher au survol un aperçu rapide et au clic une fiche détaillée avec historique.
3. Fournir un résumé « santé du Mac » en pourcentage depuis la barre des menus.
4. Alerter quand quelque chose va mal (chaleur, mémoire saturée, disque presque plein, batterie usée).
5. Rester léger : moins de 1 % de CPU et moins de 80 Mo de RAM quand la fenêtre 3D est fermée.

### Non-objectifs (v1.0)

- Pas de support Intel ni Windows : Apple Silicon seulement, ciblé d'abord sur le MacBook Air M5.
- Pas de modification du système (pas de contrôle de ventilateur, pas d'overclock, pas de nettoyage automatique).
- Pas de distribution sur le Mac App Store en v1 (le sandbox bloque plusieurs capteurs) : distribution directe signée et notarisée.
- Pas de compte en ligne ni de collecte de données : tout reste local.

### Critère de réussite

En moins de 3 secondes, tu sais si ton Mac va bien, et si non, quelle composante pose problème et pourquoi.

## 2. Fonctionnalités

La v1.0 livre 4 fonctionnalités cœur (F1–F4) ; les fonctionnalités bonus (B1–B8) sont classées par valeur et arrivent au sprint 7 ou après.

### Composantes modélisées (MacBook Air M5)

Le [MacBook Air M5](https://support.apple.com/es-lamr/126320) a un CPU de 10 cœurs (4 super-cœurs, 6 cœurs d'efficacité), un GPU de 8 ou 10 cœurs et un Neural Engine de 16 cœurs. Il n'a **pas de ventilateur** : la gestion thermique est passive, donc la « pression thermique » remplace la vitesse du ventilateur comme indicateur clé.

| Composante 3D | Ce qu'on mesure | Problèmes détectés |
| --- | --- | --- |
| Puce M5 (boîtier) | Puissance totale (W), température, pression thermique | Throttling, surchauffe soutenue |
| Grappe super-cœurs (×4) | Charge par cœur (%), fréquence (GHz), puissance | Cœur bloqué à 100 % longtemps |
| Grappe efficacité (×6) | Charge par cœur, fréquence | Saturation des cœurs E en veille (processus parasite) |
| GPU (8 ou 10 cœurs) | Utilisation (%), fréquence, puissance, mémoire GPU allouée | Charge GPU élevée sans app au premier plan |
| Neural Engine | Puissance (W), actif/inactif | — (informatif) |
| Mémoire unifiée 16 Go | Utilisée, compressée, swap, pression mémoire | Pression jaune/rouge, swap qui grossit |
| SSD | Espace libre, lecture/écriture (Mo/s), santé SMART, usure | Disque > 90 % plein, erreurs SMART |
| Batterie | Charge, cycles, capacité max vs design, santé, température, puissance entrante/sortante | Capacité < 80 %, chauffe en charge |
| Wi-Fi / Bluetooth | Débit montant/descendant, signal (RSSI), bruit | Signal faible, perte de connexion |
| Ports et alimentation (MagSafe, USB-C) | Adaptateur branché, puissance négociée (W) | Chargeur trop faible |
| Écran | Luminosité, résolution active | — (informatif) |

### F1 — Vue 3D interactive

- Maquette 3D éclatée de la carte mère stylisée : chaque composante est un objet cliquable.
- Couleur et pulsation en direct : vert (OK), ambre (attention), rouge (problème) ; intensité lumineuse proportionnelle à la charge.
- Survol = carte d'aperçu ; clic = zoom caméra + panneau de détail (voir section 6).
- Mode « vue éclatée » qui écarte les couches (boîtier, carte, batterie) pour mieux voir.

### F2 — Fiche détaillée par composante

- Valeurs en direct, mini-graphiques sur 60 s, puis historique 1 h / 24 h / 7 j.
- Score de santé de la composante (0–100) avec la raison en une phrase.
- Liste des 5 processus qui la sollicitent le plus (CPU, GPU, mémoire, disque, réseau).

### F3 — Résumé dans la barre des menus

- Icône compacte : une puce stylisée colorée selon le score global, ou le score en chiffres (au choix).
- Clic = panneau avec le score global (%), une jauge par famille, ce qui va bien / moins bien, et un bouton « Ouvrir la vue 3D ».

### F4 — Alertes

- Notifications macOS sur seuils configurables, avec anti-spam (une alerte par problème par 30 min).
- Exemples : throttling depuis 2 min, pression mémoire rouge, disque > 90 %, batterie qui chauffe en charge.

### Fonctionnalités bonus recommandées

| ID | Fonctionnalité | Pourquoi c'est utile |
| --- | --- | --- |
| B1 | « Pourquoi mon Mac rame ? » : diagnostic en un clic | Croise charge, mémoire et thermique pour nommer la vraie cause |
| B2 | Explication en langage simple par l'IA locale d'Apple (Foundation Models) | Traduit les chiffres en conseils, hors ligne, sans clé API |
| B3 | Rapport santé batterie (tendance de capacité, prévision de remplacement) | La batterie est la pièce qui s'use le plus vite |
| B4 | Widget de bureau (WidgetKit) avec le score | Vue d'ensemble sans ouvrir l'app |
| B5 | Raccourcis (App Intents) : « Quel est l'état de mon Mac ? » via Siri/Spotlight | Intégration système gratuite |
| B6 | Mode session : enregistrer une session (jeu, compilation) et la rejouer en 3D | Comprendre un pic après coup |
| B7 | Export d'un rapport PDF | Utile pour un technicien ou un travail d'école |
| B8 | Raccourci clavier global pour ouvrir le panneau | Accès rapide |

## 3. Choix technologiques

Décision : **Swift 6 + SwiftUI + RealityKit**, 100 % natif Apple. C'est le seul choix qui donne à la fois l'accès direct aux capteurs bas niveau (IOKit, IOReport, SMC), une vraie icône de barre des menus et une 3D fluide sur le GPU Apple avec peu de mémoire.

### Pile retenue

| Couche | Technologie | Raison |
| --- | --- | --- |
| Langage | Swift 6 (concurrence stricte : actors, async/await) | Appels C directs vers IOKit, sûreté des threads vérifiée à la compilation |
| Interface | SwiftUI (+ AppKit ponctuellement) | Fenêtres, panneaux, réglages ; AppKit seulement pour le raccourci global |
| Barre des menus | `MenuBarExtra` en style `.window` | API officielle SwiftUI pour un panneau riche |
| 3D | RealityKit via `RealityView` | Moteur 3D actuel d'Apple ; [SceneKit est déprécié depuis la WWDC25](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit.md) |
| Modèles 3D | Blender → export USDZ, retouches dans Reality Composer Pro | USD est le format natif de RealityKit |
| Graphiques | Swift Charts | Natif, animé, accessible |
| Historique | SQLite via GRDB.swift | Séries temporelles rapides, requêtes d'agrégation, rétention simple |
| Alertes | UserNotifications | Notifications macOS standard |
| Lancement au démarrage | `SMAppService.mainApp` | API moderne pour les éléments de connexion |
| Widget / raccourcis | WidgetKit, App Intents | Bonus B4 et B5 |
| IA locale | Foundation Models (macOS 26+) | Bonus B2, sur l'appareil, gratuit |
| Tests | Swift Testing + XCTest (UI) | Framework de test moderne d'Apple |
| Mises à jour | Sparkle 2 | Standard pour les apps distribuées hors App Store |

**Cible système :** macOS 26 Tahoe minimum, testé sur macOS 27 (sorti à l'automne 2026). Outils : Xcode 26 ou plus récent.

### Alternatives écartées

| Option | Pourquoi non |
| --- | --- |
| Python (PyQt + psutil) | psutil ne lit ni températures, ni GPU, ni puissance sur Apple Silicon ; barre des menus et 3D médiocres ; app lourde à empaqueter |
| Electron + Three.js | 200–400 Mo de RAM pour une app de monitoring : contradictoire ; capteurs via module natif quand même |
| Tauri (Rust + web) | Bon compromis, mais la 3D passe par WebGL et les capteurs demandent du Rust + FFI : deux langages à maîtriser |
| Unity / Godot | 3D superbe, mais app lourde, pas de vraie intégration barre des menus |
| SceneKit | Déprécié, plus de nouvelles fonctionnalités |

### Pour toi qui es fort en Python

Swift se lit vite quand on connaît Python (types inférés, closures, `guard`). Python reste utile à côté : scripts de prototypage des capteurs, analyse des données exportées de la base SQLite, génération de la table des seuils. La courbe d'apprentissage est intégrée au sprint 0.

## 4. Architecture logicielle

Silicium tourne en **un seul processus agent** (pas d'icône dans le Dock, `LSUIElement = YES`) qui collecte en continu ; la fenêtre 3D s'ouvre à la demande et se libère quand on la ferme. Les données circulent dans un seul sens : capteurs → hub → instantané immuable → moteurs et interface.

&#91;embedded content: architecture de Silicium · 6 couches\]

Le Snapshot est le seul point de passage : l'interface, le moteur de santé et l'historique lisent tous la même photo de l'état du Mac.

### Modules (paquets Swift locaux)

| Module | Rôle | Dépend de |
| --- | --- | --- |
| `SiliciumSensors` | Un « sampler » par source : CPU, mémoire, puissance, GPU, thermique, disque, batterie, réseau, processus | IOKit, libproc, CoreWLAN |
| `SiliciumCore` | `SensorHub` (actor qui planifie les lectures), `MetricStore` (tampons circulaires 10 min en RAM), `HealthEngine`, `AlertEngine` | SiliciumSensors |
| `SiliciumStorage` | `HistoryRepository` : écriture par lots, agrégation 1 min / 15 min, rétention 30 jours | GRDB |
| `SiliciumUI` | Panneau barre des menus, scène 3D, fiches détaillées, réglages | SwiftUI, RealityKit, Charts |
| `SiliciumShared` | Types `Snapshot`, `HealthReport` partagés avec le widget via un App Group | — |

### Flux de données

1. Chaque sampler implémente `protocol Sampler { func sample() async throws -> Reading }`.
2. `SensorHub` (actor) appelle les samplers à leur fréquence propre et assemble un `Snapshot` immuable (struct `Sendable`).
3. Le `Snapshot` est diffusé par `AsyncStream` à trois abonnés : l'`AppModel` (`@Observable`, sur le MainActor) pour l'interface, le `HealthEngine`, et le `HistoryRepository`.
4. Le `HealthEngine` produit un `HealthReport` (score global + score et raison par composante), consommé par l'interface et l'`AlertEngine`.

### Fréquence d'échantillonnage adaptative

| Contexte | Fréquence | But |
| --- | --- | --- |
| Fenêtre 3D ou panneau ouvert | 1 s (CPU, GPU, puissance), 2 s (le reste) | Animation fluide |
| Arrière-plan, sur secteur | 5 s | Alertes réactives |
| Arrière-plan, sur batterie | 15 s | Économiser l'énergie |
| Mode économie d'énergie actif | 30 s | Impact quasi nul |

Les données lentes (cycles batterie, SMART, capacité disque) sont lues toutes les 5 min au plus.

### Modèle de santé

Principe clé : **charge ≠ problème**. Un CPU à 100 % pendant une compilation est normal ; il devient un problème seulement s'il est soutenu, inattendu (en arrière-plan) ou accompagné de throttling.

Chaque composante démarre à 100 et perd des points selon des règles. Le score global est la moyenne pondérée, plafonnée par la pire composante pour qu'un seul gros problème ne soit jamais noyé :

```latex
G = \min\left( \frac{\sum_i w_i \, s_i}{\sum_i w_i},\; \min_i s_i + 25 \right)
```

Couleurs : 80–100 vert, 50–79 ambre, 0–49 rouge. Hystérésis : un état ne change qu'après 10 s de condition stable (30 s pour revenir au vert), ce qui évite le clignotement.

Règles initiales (à calibrer au sprint 6 avec tes vraies données) :

| Composante | Condition | Pénalité |
| --- | --- | --- |
| Thermique | Pression modérée / forte / critique | −20 / −50 / −80 |
| Mémoire | Pression avertissement / critique | −25 / −60 |
| Mémoire | Swap > 4 Go | −15 |
| SSD | Espace libre < 15 % / < 10 % / < 5 % | −20 / −40 / −70 |
| SSD | Avertissement critique SMART | −100 |
| Batterie | Capacité max < 80 % | −30 |
| Batterie | Température > 40 °C en charge | −20 |
| CPU | Un processus d'arrière-plan > 90 % d'un cœur pendant 5 min | −15 |
| Réseau | Signal Wi-Fi < −75 dBm | −20 |

Poids par défaut : thermique 3, mémoire 3, SSD 2, batterie 2, CPU 2, GPU 1, réseau 1.

## 5. Sources de données système

Toutes les mesures se lisent **sans droits administrateur** ; trois sources (IOReport, SMC, HID) sont des API privées non documentées, ce qui exclut le Mac App Store mais reste la pratique standard des outils comme Stats, macmon et [SiliconScope](https://gittrend.io/repo/kennss/SiliconScope).

| Donnée | Source | API publique ? | Notes |
| --- | --- | --- | --- |
| Charge CPU par cœur | `host_processor_info` (Mach) | Oui | Delta des ticks entre deux lectures |
| Fréquence CPU, résidence par grappe | IOReport « CPU Stats » + table DVFS de l'IORegistry | Non | Lier `libIOReport.dylib` manuellement (pas de stub dans le SDK) |
| Puissance CPU / GPU / ANE / DRAM (W) | IOReport « Energy Model » | Non | Énergie ÷ durée d'échantillon |
| Utilisation GPU, mémoire GPU | IORegistry `AGXAccelerator` → `PerformanceStatistics` | Semi | Clés stables depuis M1, à vérifier sur M5 |
| Températures | SMC (clés FourCC) + `IOHIDEventSystem` en secours | Non | Les clés changent à chaque génération de puce : table propre au M5 à établir |
| Pression thermique | Notification Darwin `com.apple.system.thermalpressurelevel` + `ProcessInfo.thermalState` | Oui | Indicateur principal : le M5 Air n'a pas de ventilateur |
| Mémoire, swap | `host_statistics64`, `sysctl vm.swapusage` | Oui | Calculer « utilisée » comme le Moniteur d'activité |
| Pression mémoire | `sysctl kern.memorystatus_vm_pressure_level` + `DispatchSource.makeMemoryPressureSource` | Oui | Vert / jaune / rouge comme macOS |
| Espace disque | `URLResourceValues.volumeAvailableCapacityForImportantUsage` | Oui | Inclut l'espace purgeable |
| Débit disque | IORegistry `IOBlockStorageDriver` → `Statistics` | Semi | Octets lus/écrits cumulés |
| Santé SSD (SMART) | Interface NVMe SMART d'IOKit | Semi | Usure (%), avertissement critique, température |
| Batterie | `IOPSCopyPowerSourcesInfo` + IORegistry `AppleSmartBattery` | Mixte | Cycles, capacité max, température, ampérage, tension |
| Adaptateur secteur | `IOPSCopyExternalPowerAdapterDetails` | Oui | Puissance négociée (W) |
| Réseau (débit) | `getifaddrs` → `if_data` | Oui | Delta des octets sur `en0` |
| Wi-Fi (signal, bruit) | CoreWLAN `CWInterface` | Oui | Le nom du réseau (SSID) exige l'autorisation de localisation : optionnel |
| Top processus | `proc_listpids` + `proc_pid_rusage` (libproc) | Oui | CPU, mémoire, E/S disque, énergie par processus |

### Contraintes à retenir

- **Pas de sandbox** : l'app est signée « Developer ID » avec Hardened Runtime, sans App Sandbox.
- **Clés SMC du M5** : le travail de cartographie (quelle clé = quel capteur) est le plus gros risque technique ; prévu au sprint 3 avec des tests de charge pour relier chaque clé à une zone.
- **Isolation** : chaque API privée est encapsulée derrière un protocole ; si une lecture échoue après une mise à jour de macOS, la composante passe en « donnée indisponible » au lieu de faire planter l'app.

## 6. Design UX/UI

Décision : **les deux, avec des rôles différents**. Le survol donne un aperçu instantané (on balaie la maquette des yeux), le clic ouvre le détail (on veut creuser). Survol seul : impossible de lire un graphique sans que la carte disparaisse. Clic seul : il faut cliquer partout pour avoir une vue d'ensemble.

### Interactions dans la vue 3D

| Geste | Résultat |
| --- | --- |
| Survol d'une composante (après 150 ms) | Contour lumineux + carte flottante : nom, valeur clé, score, une phrase d'état |
| Clic | La caméra glisse vers la composante (animation 0,4 s) ; panneau de détail à droite |
| Clic dans le vide ou Échap | Retour à la vue d'ensemble |
| Glisser / pincer / défiler | Orbite, zoom, panoramique (bornés pour ne jamais perdre la maquette) |
| Touches 1 à 9 | Saut direct vers une composante |
| Barre d'espace | Basculer la vue éclatée |

### Direction artistique de la scène

- Style « maquette technique » : carte mère sombre mate, composantes en volumes simplifiés et propres, pas de photoréalisme. Plus lisible, plus léger et plus beau qu'une copie fidèle.
- L'état se lit par la **lumière** : émission colorée (vert, ambre, rouge) dont l'intensité suit la charge ; pulsation lente si alerte.
- Les cœurs CPU et GPU sont des tuiles individuelles sur la puce : on voit chaque cœur s'allumer.
- Flux animés : petites particules entre la mémoire et la puce (bande passante), entre la batterie et la carte (puissance).
- Thermique : halo de chaleur subtil au-dessus de la puce selon la température.
- Thème clair et sombre suivant le système ; respect de « Réduire les animations » (pulsations et particules désactivées).
- Accessibilité : la couleur n'est jamais seule, chaque état a aussi une icône et un mot (OK, Attention, Problème).

### Panneau de la barre des menus

- Icône : petite puce monochrome (style système) avec une pastille de couleur ; option pour afficher le score en chiffres.
- Panneau (≈ 340 × 480 pt) de haut en bas :
  1. Score global en grand (ex. « 87 % — Ton Mac va bien »).
  2. Une ligne par famille : icône, jauge, valeur clé, pastille d'état.
  3. Section « À surveiller » : 0 à 3 problèmes avec leur raison.
  4. Boutons : « Ouvrir la vue 3D », « Diagnostic » (B1), réglages, quitter.
- Le panneau s'ouvre en moins de 100 ms : il lit le dernier `Snapshot` déjà en mémoire.

### Fenêtre principale

- Gauche : scène 3D (≈ 70 % de la largeur).
- Droite : panneau de détail (valeurs en direct, graphiques Swift Charts 60 s / 1 h / 24 h / 7 j, top 5 processus, conseils).
- Bas : chronologie des alertes récentes.

## 7. Plan de sprints

Le projet compte 9 sprints sur environ 21 semaines, avec un MVP utilisable (barre des menus) le 6 décembre 2026 et la v1.0 le 28 mars 2027. Hypothèses : tu travailles seul, 8 à 10 h par semaine pendant la session, avec une pause pour les examens de décembre et les Fêtes (dates à ajuster à ton horaire).

&#91;embedded content: calendrier des sprints · 9 sprints, 2 jalons\]

Le MVP arrive avant la pause des examens : même si la session devient chargée, tu as déjà un outil utile.

### Sprint 0 — Fondations (2–8 nov. 2026)

Objectif : un projet qui compile, et assez de Swift pour être autonome.

- [ ] Installer Xcode, créer le dépôt Git (GitHub privé) avec `.gitignore` et README
- [ ] Créer le projet macOS SwiftUI + les 5 paquets Swift locaux (section 4)
- [ ] Activer Swift 6 en mode concurrence stricte, SwiftLint, GitHub Actions (build + tests)
- [ ] Faire le tutoriel officiel SwiftUI et un mini-exercice async/await + actor
- [ ] Prototype jetable : afficher la charge CPU dans une fenêtre, rafraîchie chaque seconde

Acceptation : `xcodebuild test` passe en CI ; le prototype affiche une charge CPU cohérente avec le Moniteur d'activité (± 5 points).

### Sprint 1 — Capteurs de base (9–22 nov.)

Objectif : lire tout ce qui est accessible par API publique.

- [ ] Protocole `Sampler`, type `Reading`, et `SensorHub` (actor) avec planification
- [ ] Samplers : CPU par cœur, mémoire + swap + pression, disque (espace + débit), batterie, adaptateur, réseau (débit + Wi-Fi), pression thermique
- [ ] `Snapshot` immuable diffusé par `AsyncStream`
- [ ] Tests unitaires avec samplers simulés (« mocks ») et valeurs enregistrées
- [ ] Écran de debug : tableau brut de toutes les valeurs

Acceptation : chaque valeur est à ± 5 % du Moniteur d'activité ou d'Informations système ; CPU de Silicium < 1 % en échantillonnage 5 s.

### Sprint 2 — Barre des menus et score (23 nov.–6 déc.) · jalon MVP

Objectif : la fonctionnalité F3 utilisable au quotidien.

- [ ] `HealthEngine` : règles, pénalités, score global, hystérésis (section 4)
- [ ] `MenuBarExtra` avec icône colorée et panneau complet (section 6)
- [ ] App agent sans icône dans le Dock + lancement au démarrage (`SMAppService`)
- [ ] Fenêtre de réglages : fréquence, affichage de l'icône, seuils de base
- [ ] Tests du `HealthEngine` sur des scénarios (disque plein, pression mémoire, etc.)

Acceptation : tu utilises Silicium une semaine sans bug bloquant ; le panneau s'ouvre en < 100 ms ; chaque scénario de test donne la couleur attendue.

### Pause — examens et Fêtes (7 déc. 2026–3 janv. 2027)

Optionnel et léger : modéliser la maquette 3D dans Blender (bonne activité « détente »).

### Sprint 3 — Capteurs avancés (4–17 janv. 2027)

Objectif : les données privées, le plus gros risque technique.

- [ ] Liaison à `libIOReport` ; puissance CPU / GPU / ANE / DRAM ; fréquences et résidence par grappe
- [ ] GPU : utilisation et mémoire via `AGXAccelerator`
- [ ] SMC : lecture des clés ; script de cartographie (lancer une charge CPU, puis GPU, et voir quelles clés montent) pour établir la table du M5
- [ ] HID en secours pour les températures ; SMART NVMe
- [ ] Top processus via libproc
- [ ] Dégradation propre : « donnée indisponible » si une API échoue

Acceptation : puissance totale cohérente avec `sudo powermetrics` (± 10 %) ; au moins une température fiable pour la grappe super-cœurs, le GPU et la batterie ; aucun crash si on désactive une source.

### Sprint 4 — Scène 3D statique (18–31 janv.)

Objectif : la maquette affichée et navigable.

- [ ] Finaliser le modèle Blender (puce avec tuiles par cœur, mémoire, SSD, batterie, antennes, ports) ; nommer chaque objet ; exporter en USDZ
- [ ] `RealityView` dans la fenêtre principale ; éclairage, caméra orbitale bornée
- [ ] Détection du survol et du clic (`InputTargetComponent` + `CollisionComponent` + gestes SwiftUI)
- [ ] Carte de survol et animation de caméra au clic

Acceptation : 60 images/s stables sur le M5 Air ; chaque composante réagit au survol et au clic ; mémoire de la fenêtre 3D < 250 Mo.

### Sprint 5 — 3D vivante et fiches détaillées (1–14 févr.)

Objectif : la fonctionnalité F1 + F2 complète.

- [ ] Liaison `Snapshot` → matériaux : couleur d'émission, intensité, pulsation
- [ ] Effets : particules de flux, halo thermique, vue éclatée animée
- [ ] Panneau de détail : valeurs en direct, graphique 60 s (Swift Charts), top 5 processus, raison du score
- [ ] Respect de « Réduire les animations » et du thème clair/sombre

Acceptation : lancer un benchmark CPU allume les 4 super-cœurs en moins de 2 s ; un test de remplissage disque fait passer le SSD à l'ambre.

### Sprint 6 — Historique et alertes (15–28 févr.)

Objectif : F4 + l'historique long.

- [ ] `HistoryRepository` (GRDB) : écriture par lots, agrégation 1 min / 15 min, rétention 30 jours
- [ ] Graphiques 1 h / 24 h / 7 j dans les fiches
- [ ] `AlertEngine` : seuils, anti-spam 30 min, notifications avec bouton « Voir »
- [ ] Calibrer les seuils du `HealthEngine` sur 2 semaines de tes données réelles (analyse en Python possible)

Acceptation : base < 50 Mo après 30 jours ; une alerte de pression mémoire arrive en < 15 s ; aucune alerte en double.

### Sprint 7 — Fonctionnalités bonus (1–14 mars)

Objectif : 3 à 4 bonus, par ordre de priorité.

- [ ] B1 Diagnostic « Pourquoi mon Mac rame ? »
- [ ] B3 Rapport santé batterie avec tendance de capacité
- [ ] B4 Widget de bureau (App Group pour partager le dernier `HealthReport`)
- [ ] B2 Explication par Foundation Models (si le temps le permet)

Acceptation : chaque bonus livré a ses tests ; les bonus non faits passent au backlog v1.1.

### Sprint 8 — Finition et version 1.0 (15–28 mars)

Objectif : une app que tu pourrais donner à un ami.

- [ ] Profilage avec Instruments (Time Profiler, Allocations, Energy Log) et correction des pics
- [ ] Icône de l'app, écran d'accueil au premier lancement, page « À propos »
- [ ] Signature Developer ID, notarisation, DMG, Sparkle pour les mises à jour
- [ ] Tests UI des parcours principaux ; correction des bogues ouverts
- [ ] README avec captures, vidéo de démo (utile pour ton portfolio)

Acceptation : tous les budgets de performance de la section 8 sont respectés ; le DMG s'installe sur un Mac propre sans avertissement Gatekeeper.

## 8. Qualité, risques et distribution

Un moniteur système qui ralentit le Mac rate sa mission : les budgets de performance ci-dessous sont des critères bloquants pour la v1.0.

### Budgets de performance

| Mesure | Budget | Outil de vérification |
| --- | --- | --- |
| CPU, agent seul en arrière-plan (5 s) | < 0,5 % | Moniteur d'activité, Instruments |
| CPU, panneau ouvert (1 s) | < 2 % | Instruments Time Profiler |
| CPU + GPU, fenêtre 3D ouverte | < 8 % CPU | Instruments, `powermetrics` |
| RAM, agent seul | < 80 Mo | Instruments Allocations |
| RAM, fenêtre 3D ouverte | < 250 Mo | Instruments Allocations |
| Images par seconde, scène 3D | 60 stables | RealityKit Trace |
| Ouverture du panneau | < 100 ms | Signposts `os_signpost` |
| Base d'historique après 30 jours | < 50 Mo | Taille du fichier |

### Stratégie de tests

- **Unitaires** (Swift Testing) : `HealthEngine`, `AlertEngine`, agrégation de l'historique, conversions d'unités. Objectif : 80 % de couverture sur `SiliciumCore`.
- **Samplers** : chaque sampler a une version simulée ; des enregistrements réels (JSON) servent de jeux de test rejouables.
- **Scénarios de charge** : scripts qui provoquent un état (stress CPU avec `yes > /dev/null`, remplissage disque temporaire, forte allocation mémoire) et vérifient la couleur attendue.
- **UI** (XCTest) : ouvrir le panneau, ouvrir la vue 3D, cliquer une composante, changer un réglage.
- **Endurance** : 24 h d'exécution sans fuite mémoire (Instruments Leaks), avec cycles veille/réveil.

### Risques

| Risque | Probabilité | Impact | Plan |
| --- | --- | --- | --- |
| Clés SMC du M5 inconnues ou mal identifiées | Élevée | Moyen | Script de cartographie au sprint 3 ; HID en secours ; sinon afficher seulement la pression thermique |
| Mise à jour de macOS qui casse une API privée | Moyenne | Moyen | Encapsulation par protocole, dégradation propre, test à chaque bêta de macOS |
| Courbe d'apprentissage Swift / RealityKit | Moyenne | Élevé | Sprint 0 dédié ; 3D repoussée aux sprints 4–5 une fois Swift maîtrisé |
| Modélisation 3D plus longue que prévu | Moyenne | Moyen | Style simplifié ; maquette en primitives RealityKit (boîtes) en plan B |
| Surcharge de session (cours, projet d'équipe) | Élevée | Moyen | MVP tôt (6 déc.) ; sprints 7 et 8 compressibles ; bonus reportables |
| Silicium lui-même consomme trop | Faible | Élevé | Budgets bloquants, fréquence adaptative, profilage à chaque sprint |

### Distribution

- **Pour toi seul** : un build signé localement suffit, gratuit.
- **Pour d'autres personnes** : compte Apple Developer (99 $ US par an) pour la signature Developer ID et la notarisation ; DMG + Sparkle ; publication sur GitHub Releases.
- **Licence** : open source (MIT ou GPLv3) si tu veux en faire une vitrine de portfolio.

### Après la v1.0 (backlog)

- Bonus restants (B5 Raccourcis, B6 sessions enregistrées, B7 rapport PDF, B8 raccourci global).
- Prise en charge des autres Mac Apple Silicon (M1 à M5 Pro/Max) via une table de modèles 3D et de clés par puce.
- Version anglaise (fichiers de traduction `.xcstrings`).
- Comparaison « avant / après » une mise à jour de macOS.
