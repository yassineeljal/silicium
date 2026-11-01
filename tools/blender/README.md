# Modèle matériel de Silicium

`build_model.py` génère un USDZ autonome : 65 maillages après regroupement des détails, matériaux physiques, textures de rugosité intégrées. Aucun téléchargement d'asset n'est nécessaire. Les répétitions utilisent des maillages partagés pendant la génération ; les décorations sont ensuite regroupées par matériau et par couche.

La silhouette, les boîtiers, les soudures et les nappes s'inspirent des [photographies de démontage iFixit du MacBook Air M4](https://www.ifixit.com/News/108697/m4-macbook-air-teardown-apple-when-will-macbooks-finally-get-repair-upgrades). Les photographies ne sont pas incorporées au modèle. Les dimensions, le placement, les inscriptions et les unités du die sont une interprétation pédagogique ; ce modèle ne sert pas de guide de réparation et ne prétend pas reproduire le M5.

## Contrat avec RealityKit

- `PART__<ComponentID>__<detail>` : chaque maillage descendant reçoit le composant de sélection correspondant. Les limites de cadrage et les contours sont calculés à partir de ces géométries.
- `LAYER__board`, `LAYER__battery`, `LAYER__chassis` : couches du matériel ; les translations de la vue éclatée sont appliquées dans la boucle d'image.
- `LAYER__lid` : surface physique du silicium avec son marquage.
- `LAYER__silicon` : coupe pédagogique, cachée par défaut. Seules ses unités de calcul reçoivent une émission liée aux mesures.
- `DETAIL__...` : détails statiques regroupés. Les détails sous un `PART__` restent cliquables avec leur parent.

Axes d'édition : Blender Z vers le haut, coordonnées d'app Y vers le haut. `P(x, z, y)` effectue la conversion ; USD conserve les métadonnées d'axes pour l'import RealityKit. Les couches importées sont placées dans des conteneurs Y-up, en préservant leur transformation mondiale, pour aligner les contours et les déplacements sur les repères de l'app. La texture de circuit générée par l'ancien fallback n'écrase plus les matériaux importés.

## Reproduire les captures

```sh
mkdir -p build/visual-review
blender -b -P tools/blender/build_model.py -- App/Resources/Silicium.usdz --render build/visual-review/blender-studio.png
```

Le rendu Blender est un contrôle de géométrie. Le rendu de référence de l'application est produit par `Silicium --render`, avec RealityKit, le même éclairage et le même contrôleur que la fenêtre. `--select gpu` active automatiquement la coupe pédagogique ; `--exploded` sépare les couches. `--verify-model` vérifie le chargement, les composants sélectionnables et la visibilité des deux modes.

Avec `--snapshot-ui`, ajouter `--verify-interactions` teste les rayons de sélection sur les six groupes physiques, ou sur les quatre groupes de calcul avec `--select gpu`. Les captures restent dans `build/visual-review/`, ignoré par Git. Les tests du paquet couvrent également les retours à la vue d'ensemble, le changement de mode et le recadrage d'un composant déjà sélectionné.
