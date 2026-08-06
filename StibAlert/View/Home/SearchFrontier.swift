import CoreLocation

/// L'exploration du réseau dessinée pendant qu'un itinéraire se calcule.
///
/// Deux fronts partent du DÉPART et de l'ARRIVÉE, se propagent le long des
/// lignes et se rejoignent quelque part au milieu. C'est la forme qu'a toute
/// recherche de plus court chemin — deux taches qui grossissent jusqu'à se
/// toucher — et c'est ce qui remplit l'attente au lieu d'une carte figée.
///
/// Le graphe n'est pas inventé : ses arêtes sont les **tracés réels** des
/// lignes STIB (`line-shapes.json`, embarqué, 81 000 sommets qui suivent la
/// voirie). Les branches épousent donc les rues sans qu'on ait besoin d'un
/// graphe routier, et là où deux lignes se croisent le front bifurque —
/// exactement ce qui donne l'allure de tentacules.
///
/// ⚠️ Ce n'est pas la trace du solveur. Le calcul réel tourne chez Transitous,
/// pas sur le téléphone. C'est une illustration honnête de la zone fouillée —
/// d'où l'absence de tout chiffre à l'écran : aucun nombre affiché ici ne
/// correspondrait à quoi que ce soit de mesuré.
struct SearchFrontier {

    /// Une tentacule. `reach[i]` dit à quel moment (0…1) le point `i` est
    /// atteint : c'est la distance Dijkstra normalisée, donc croissante.
    struct Branch: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let reach: [Double]
        let fromStart: Bool
    }

    /// Une branche à l'instant t, prête à être dessinée.
    struct GrownBranch: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let fromStart: Bool
    }

    let branches: [Branch]

    var isEmpty: Bool { branches.isEmpty }

    // MARK: - Construction

    /// - Parameters:
    ///   - networkPaths: les tracés de lignes, tels quels. Les corridors
    ///     partagés par plusieurs lignes sont fusionnés ici.
    ///   - maxNodes: plafond dur. Le pas d'échantillonnage s'ajuste pour le
    ///     respecter, ce qui garde un coût constant que le trajet fasse 1 ou
    ///     10 km.
    static func build(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        networkPaths: [[CLLocationCoordinate2D]],
        maxNodes: Int = 850,
        maxBranches: Int = 30
    ) -> SearchFrontier {
        let direct = distance(start, end)
        guard direct > 150, !networkPaths.isEmpty else { return SearchFrontier(branches: []) }

        // Ellipse de foyers départ/arrivée : exactement la région qu'un routeur
        // fouille. Un détour qui rallonge de plus de 55 % n'a aucune chance
        // d'être sur une solution, et le dessiner brouillerait la lecture.
        let budget = direct * 1.55

        // Un premier échantillonnage, puis un seul rattrapage si le réseau est
        // trop dense ici. Sans ça, un trajet en centre-ville produirait dix
        // fois plus de nœuds qu'un trajet en périphérie, à animation égale.
        var step = max(45.0, direct / 55)
        var graph = sampleGraph(paths: networkPaths, start: start, end: end, budget: budget, step: step)
        if graph.nodes.count > maxNodes {
            step *= (Double(graph.nodes.count) / Double(maxNodes)).squareRoot()
            graph = sampleGraph(paths: networkPaths, start: start, end: end, budget: budget, step: step)
        }
        guard graph.nodes.count >= 12 else { return SearchFrontier(branches: []) }

        // Le départ et l'arrivée ne sont presque jamais SUR une ligne : on les
        // raccroche aux tronçons les plus proches, comme le fait un routeur
        // avec ses correspondances à pied.
        //
        // On élargit par paliers plutôt que de viser large d'emblée : le lien
        // d'accroche est le seul segment droit du dessin, et un rayon calculé
        // sur la longueur du trajet produisait une barre d'un kilomètre entre
        // le pin et le réseau — précisément l'allure « deux points reliés »
        // que cette animation doit faire oublier.
        guard let startIndex = attach(start, to: &graph, radii: [300, 700, 1600]),
              let endIndex = attach(end, to: &graph, radii: [300, 700, 1600])
        else { return SearchFrontier(branches: []) }

        let search = bidirectionalDijkstra(graph: graph, startIndex: startIndex, endIndex: endIndex)
        let branches = extractBranches(
            graph: graph,
            search: search,
            roots: [startIndex, endIndex],
            maxBranches: maxBranches
        )
        return SearchFrontier(branches: branches)
    }

    /// Repli quand le réseau n'est pas exploitable ici : trop court, hors
    /// Bruxelles (De Lijn, TEC), ou tracés pas encore chargés. Deux amorces
    /// symétriques en arc, volontairement abstraites — elles disent « on
    /// cherche entre ces deux points » sans prétendre suivre une rue.
    static func fallback(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        samples: Int = 26
    ) -> SearchFrontier {
        let deltaLat = end.latitude - start.latitude
        let deltaLng = end.longitude - start.longitude
        // La courbure (12 % de l'écart) évite la ligne droite, qu'on lirait
        // comme « voilà le chemin ».
        let control = CLLocationCoordinate2D(
            latitude: (start.latitude + end.latitude) / 2 - deltaLng * 0.12,
            longitude: (start.longitude + end.longitude) / 2 + deltaLat * 0.12
        )
        let arc = (0...samples).map { step -> CLLocationCoordinate2D in
            let t = Double(step) / Double(samples)
            let u = 1 - t
            return CLLocationCoordinate2D(
                latitude: u * u * start.latitude + 2 * u * t * control.latitude + t * t * end.latitude,
                longitude: u * u * start.longitude + 2 * u * t * control.longitude + t * t * end.longitude
            )
        }
        // Chaque moitié pousse depuis son extrémité et s'arrête au milieu : les
        // deux se rejoignent en fin de cycle, comme le fait le vrai front.
        let half = arc.count / 2
        let head = Array(arc.prefix(half))
        let tail = Array(arc.suffix(half)).reversed().map { $0 }
        func reach(_ count: Int) -> [Double] {
            (0..<count).map { Double($0) / Double(max(count - 1, 1)) }
        }
        return SearchFrontier(branches: [
            Branch(id: 0, coordinates: head, reach: reach(head.count), fromStart: true),
            Branch(id: 1, coordinates: tail, reach: reach(tail.count), fromStart: false),
        ])
    }

    // MARK: - Graphe

    private struct Graph {
        var nodes: [CLLocationCoordinate2D] = []
        var adjacency: [[Int]] = []
        var cells: [Int64: [Int]] = [:]

        mutating func addNode(_ coordinate: CLLocationCoordinate2D, mergeMeters: Double) -> Int {
            // On regarde aussi les 8 cases voisines : deux lignes qui longent la
            // même avenue tombent sinon dans des cases différentes et le graphe
            // se dédouble en rails parallèles au lieu de bifurquer.
            let key = gridKey(coordinate, meters: mergeMeters)
            for neighbourKey in Self.ring(around: key) {
                guard let bucket = cells[neighbourKey] else { continue }
                for index in bucket where distance(nodes[index], coordinate) <= mergeMeters {
                    return index
                }
            }
            let index = nodes.count
            nodes.append(coordinate)
            adjacency.append([])
            cells[key, default: []].append(index)
            return index
        }

        mutating func link(_ a: Int, _ b: Int) {
            guard a != b, !adjacency[a].contains(b) else { return }
            adjacency[a].append(b)
            adjacency[b].append(a)
        }

        private static func ring(around key: Int64) -> [Int64] {
            var keys: [Int64] = []
            for dRow in -1...1 {
                for dColumn in -1...1 {
                    keys.append(key &+ Int64(dRow) << 24 &+ Int64(dColumn))
                }
            }
            return keys
        }
    }

    /// Rééchantillonne chaque tracé à pas constant et ne garde que ce qui tombe
    /// dans l'ellipse. Les points consécutifs d'un même tracé deviennent des
    /// arêtes : c'est ce qui fait suivre les rues. Une coupure hors ellipse
    /// interrompt la suite, sinon on créerait un raccourci qui n'existe pas.
    private static func sampleGraph(
        paths: [[CLLocationCoordinate2D]],
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        budget: Double,
        step: Double
    ) -> Graph {
        var graph = Graph()
        let mergeMeters = step * 0.7

        for path in paths where path.count >= 2 {
            var previousIndex: Int? = nil
            var carried = 0.0

            for position in path.indices {
                let point = path[position]
                if position > 0 {
                    carried += distance(path[position - 1], point)
                    // Un sommet intermédiaire trop proche du précédent est
                    // ignoré : on veut un pas régulier, pas la densité
                    // capricieuse du GeoJSON d'origine.
                    guard carried >= step || position == path.count - 1 else { continue }
                }
                carried = 0

                guard distance(start, point) + distance(end, point) <= budget else {
                    previousIndex = nil
                    continue
                }
                let index = graph.addNode(point, mergeMeters: mergeMeters)
                if let previousIndex { graph.link(previousIndex, index) }
                previousIndex = index
            }
        }
        return graph
    }

    /// Raccroche un point au réseau via ses voisins les plus proches, en
    /// essayant les rayons dans l'ordre et en s'arrêtant au premier qui trouve
    /// quelque chose : le lien reste aussi court que le terrain le permet.
    private static func attach(
        _ coordinate: CLLocationCoordinate2D,
        to graph: inout Graph,
        radii: [Double],
        links: Int = 3
    ) -> Int? {
        var near: [(index: Int, distance: Double)] = []
        for radius in radii {
            near = []
            for index in graph.nodes.indices {
                let d = distance(graph.nodes[index], coordinate)
                guard d <= radius else { continue }
                near.append((index, d))
            }
            if !near.isEmpty { break }
        }
        guard !near.isEmpty else { return nil }
        near.sort { $0.distance < $1.distance }

        let anchor = graph.nodes.count
        graph.nodes.append(coordinate)
        graph.adjacency.append([])
        for candidate in near.prefix(links) { graph.link(anchor, candidate.index) }
        return anchor
    }

    private struct SearchResult {
        var owner: [Int]        // -1 = jamais atteint, sinon 0 (départ) / 1 (arrivée)
        var parent: [Int]
        var reach: [Double]     // normalisé 0…1 par côté
    }

    /// Dijkstra depuis les deux extrémités **en même temps** : le front le moins
    /// avancé est toujours celui qu'on étend, et le premier arrivé garde le
    /// nœud. C'est ce qui produit deux taches d'allure comparable qui se
    /// rencontrent au milieu, au lieu d'une seule qui avale toute la carte
    /// avant que l'autre ne démarre.
    private static func bidirectionalDijkstra(
        graph: Graph,
        startIndex: Int,
        endIndex: Int
    ) -> SearchResult {
        let count = graph.nodes.count
        var best = [[Double]](repeating: [Double](repeating: .infinity, count: count), count: 2)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: count), count: 2)
        var settled = [Int](repeating: -1, count: count)
        var maxSettled = [Double](repeating: 0, count: 2)

        best[0][startIndex] = 0
        best[1][endIndex] = 0

        // Tas binaire : le balayage linéaire coûterait O(n²) et le réseau du
        // centre-ville pousse facilement jusqu'au plafond de nœuds.
        var heap = MinHeap()
        heap.push(distance: 0, node: startIndex, side: 0)
        heap.push(distance: 0, node: endIndex, side: 1)

        while let top = heap.pop() {
            guard settled[top.node] == -1 else { continue }        // entrée périmée
            guard top.distance <= best[top.side][top.node] else { continue }

            settled[top.node] = top.side
            maxSettled[top.side] = max(maxSettled[top.side], top.distance)

            for neighbour in graph.adjacency[top.node] where settled[neighbour] == -1 {
                let candidate = top.distance + distance(graph.nodes[top.node], graph.nodes[neighbour])
                if candidate < best[top.side][neighbour] {
                    best[top.side][neighbour] = candidate
                    parent[top.side][neighbour] = top.node
                    heap.push(distance: candidate, node: neighbour, side: top.side)
                }
            }
        }

        // Les deux côtés doivent finir ensemble : chacun est normalisé par sa
        // propre portée maximale, sinon le côté le plus dense s'arrête à
        // mi-course et l'animation paraît bancale.
        var reach = [Double](repeating: 0, count: count)
        var flatParent = [Int](repeating: -1, count: count)
        for node in 0..<count {
            let side = settled[node]
            guard side >= 0 else { continue }
            reach[node] = min(1, best[side][node] / max(maxSettled[side], 1))
            flatParent[node] = parent[side][node]
        }
        return SearchResult(owner: settled, parent: flatParent, reach: reach)
    }

    private struct MinHeap {
        private var items: [(distance: Double, node: Int, side: Int)] = []

        mutating func push(distance: Double, node: Int, side: Int) {
            items.append((distance, node, side))
            var child = items.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard items[child].distance < items[parent].distance else { break }
                items.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> (distance: Double, node: Int, side: Int)? {
            guard !items.isEmpty else { return nil }
            let top = items[0]
            items[0] = items[items.count - 1]
            items.removeLast()

            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var smallest = parent
                if left < items.count, items[left].distance < items[smallest].distance { smallest = left }
                if right < items.count, items[right].distance < items[smallest].distance { smallest = right }
                guard smallest != parent else { break }
                items.swapAt(parent, smallest)
                parent = smallest
            }
            return top
        }
    }

    // MARK: - Découpe en tentacules

    /// L'arbre Dijkstra est découpé en chaînes : on part de chaque feuille et on
    /// remonte jusqu'à toucher une chaîne déjà émise, dont on garde le point de
    /// jonction. Les branches restent ainsi visuellement raccordées, et une
    /// chaîne devient une seule polyline au lieu de N segments épars.
    private static func extractBranches(
        graph: Graph,
        search: SearchResult,
        roots: [Int],
        maxBranches: Int
    ) -> [Branch] {
        var isParent = Set<Int>()
        for node in graph.nodes.indices where search.parent[node] >= 0 {
            isParent.insert(search.parent[node])
        }
        let leaves = graph.nodes.indices
            .filter { search.owner[$0] >= 0 && !isParent.contains($0) && !roots.contains($0) }
            .sorted { search.reach[$0] > search.reach[$1] }   // les plus longues d'abord

        var emitted = Set<Int>(roots)
        var branches: [Branch] = []

        for leaf in leaves {
            guard branches.count < maxBranches else { break }
            var chain: [Int] = []
            var cursor = leaf
            while cursor >= 0 {
                chain.append(cursor)
                if emitted.contains(cursor) { break }   // point de jonction inclus
                cursor = search.parent[cursor]
            }
            guard chain.count >= 3 else { continue }    // un moignon ne se lit pas
            for node in chain { emitted.insert(node) }
            chain.reverse()                             // portée croissante

            branches.append(
                Branch(
                    id: branches.count,
                    coordinates: chain.map { graph.nodes[$0] },
                    reach: chain.map { search.reach[$0] },
                    fromStart: search.owner[leaf] == 0
                )
            )
        }
        return branches
    }

    // MARK: - Croissance

    /// Les branches telles qu'elles doivent être dessinées à l'instant
    /// `progress`. Le dernier segment est **interpolé** : sans ça la tentacule
    /// avancerait par à-coups d'un sommet à l'autre au lieu de pousser.
    func grown(to progress: Double) -> [GrownBranch] {
        var grown: [GrownBranch] = []
        for branch in branches {
            guard let first = branch.reach.first, first <= progress else { continue }

            var lastReached = 0
            while lastReached + 1 < branch.reach.count && branch.reach[lastReached + 1] <= progress {
                lastReached += 1
            }

            var coordinates = Array(branch.coordinates.prefix(lastReached + 1))
            if lastReached + 1 < branch.coordinates.count {
                let span = branch.reach[lastReached + 1] - branch.reach[lastReached]
                let t = span > 0 ? (progress - branch.reach[lastReached]) / span : 0
                coordinates.append(
                    Self.interpolate(branch.coordinates[lastReached], branch.coordinates[lastReached + 1], t)
                )
            }
            guard coordinates.count >= 2 else { continue }
            grown.append(GrownBranch(id: branch.id, coordinates: coordinates, fromStart: branch.fromStart))
        }
        return grown
    }

    // MARK: - Géométrie

    private static func interpolate(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        _ t: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// Équirectangulaire : à l'échelle de Bruxelles l'écart avec la formule
    /// exacte est négligeable, et on économise des dizaines de milliers de
    /// trigonométries pendant l'échantillonnage.
    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let metersPerDegree = 111_320.0
        let x = (b.longitude - a.longitude) * metersPerDegree * 0.6316   // cos(50.85°)
        let y = (b.latitude - a.latitude) * metersPerDegree
        return (x * x + y * y).squareRoot()
    }

    private static func gridKey(_ coordinate: CLLocationCoordinate2D, meters: Double) -> Int64 {
        let latStep = meters / 111_320.0
        let lngStep = latStep / 0.6316
        let row = Int64((coordinate.latitude / latStep).rounded(.down))
        let column = Int64((coordinate.longitude / lngStep).rounded(.down))
        return row << 24 &+ column
    }
}
