import CoreGraphics
import CoreText
import Foundation

/// Diagrama de flujo con posiciones calculadas, listo para dibujar en la
/// Vista previa (SwiftUI), el PDF o el SVG del HTML. Se calcula durante el
/// análisis, fuera del hilo principal.
nonisolated struct LitteraMermaidLayout: Equatable, Sendable {
    struct PlacedNode: Equatable, Sendable {
        let id: String
        let label: String
        let shape: LitteraMermaidFlowchart.NodeShape
        let frame: CGRect
    }

    /// Tramo cúbico de Bézier desde el punto anterior.
    struct Curve: Equatable, Sendable {
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    struct PlacedEdge: Equatable, Sendable {
        let start: CGPoint
        let curves: [Curve]
        let style: LitteraMermaidFlowchart.EdgeStyle
        let arrowAtStart: Bool
        let arrowAtEnd: Bool
        let label: String?
        let labelFrame: CGRect?

        var end: CGPoint { curves.last?.end ?? start }
    }

    let size: CGSize
    let nodes: [PlacedNode]
    let edges: [PlacedEdge]

    nonisolated enum Metrics {
        static let nodeFontSize: CGFloat = 13
        static let labelFontSize: CGFloat = 12
        static let nodePaddingH: CGFloat = 14
        static let nodePaddingV: CGFloat = 9
        static let minNodeWidth: CGFloat = 44
        static let labelPaddingH: CGFloat = 6
        static let labelPaddingV: CGFloat = 3
        static let cylinderCap: CGFloat = 10
        static let nodeGap: CGFloat = 26
        static let rankGap: CGFloat = 22
        static let selfLoop: CGFloat = 22
        static let margin: CGFloat = 4
        static let arrowLength: CGFloat = 8
        /// Esquinas de rectángulos y subrutinas (D48).
        static let cornerRadius: CGFloat = 8
        /// Esquinas de los nodos `(redondeados)`.
        static let roundedCornerRadius: CGFloat = 14
    }

    typealias Measure = (String, CGFloat) -> CGSize

    static func make(
        _ chart: LitteraMermaidFlowchart,
        measure: @escaping Measure = LitteraMermaidLayout.measureText
    ) -> LitteraMermaidLayout {
        var engine = LitteraMermaidLayoutEngine(chart: chart, measure: measure)
        return engine.run()
    }

    /// Tamaño del texto con la fuente del sistema (CoreText es seguro fuera
    /// del hilo principal). Una línea por cada `\n`.
    static func measureText(_ text: String, fontSize: CGFloat) -> CGSize {
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        let lines = text.components(separatedBy: "\n")
        var width: CGFloat = 0
        for line in lines {
            let attributed = NSAttributedString(
                string: line,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            let ctLine = CTLineCreateWithAttributedString(attributed)
            width = max(width, CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)))
        }
        return CGSize(width: ceil(width), height: lineHeight * CGFloat(lines.count))
    }

    /// Tamaño de un nodo para un texto de tamaño `text`.
    static func nodeSize(for shape: LitteraMermaidFlowchart.NodeShape, text: CGSize) -> CGSize {
        let width = text.width + Metrics.nodePaddingH * 2
        let height = text.height + Metrics.nodePaddingV * 2
        switch shape {
        case .rectangle, .rounded:
            return CGSize(width: max(width, Metrics.minNodeWidth), height: height)
        case .subroutine:
            return CGSize(width: max(width, Metrics.minNodeWidth) + 16, height: height)
        case .stadium:
            return CGSize(width: max(width + height * 0.5, Metrics.minNodeWidth), height: height)
        case .circle:
            let diameter = max(ceil((text.width * text.width + text.height * text.height).squareRoot()) + Metrics.nodePaddingV * 2, Metrics.minNodeWidth)
            return CGSize(width: diameter, height: diameter)
        case .diamond:
            let diamondHeight = ceil(height * 1.8)
            return CGSize(width: max(ceil(width * 1.6), diamondHeight), height: diamondHeight)
        case .hexagon:
            return CGSize(width: max(width + height * 0.6, Metrics.minNodeWidth), height: height)
        case .cylinder:
            return CGSize(width: max(width, Metrics.minNodeWidth), height: height + Metrics.cylinderCap)
        }
    }

    /// Distancia horizontal de cada punta del hexágono.
    static func hexagonInset(height: CGFloat) -> CGFloat { height * 0.3 }
}

// MARK: - Motor de disposición por capas

/// Disposición en capas (Sugiyama simplificado):
/// 1. Se rompen los ciclos invirtiendo las aristas de retroceso.
/// 2. Rango por camino más largo; los nodos sin entradas se acercan a sus hijos.
/// 3. Rangos duplicados: cada arista tiene al menos un nodo ficticio en medio,
///    donde va su etiqueta; las aristas largas tienen uno por capa.
/// 4. Orden dentro de cada capa por baricentros, conservando el de menos cruces.
/// 5. Posición transversal por regresión isotónica ponderada (sin solapes).
nonisolated private struct LitteraMermaidLayoutEngine {
    typealias Metrics = LitteraMermaidLayout.Metrics

    struct Vertex {
        var node: Int?
        var edge: Int?
        var hasLabel = false
        var layer: Int
        /// Tamaño a lo largo de las capas.
        var mainSize: CGFloat
        /// Tamaño reservado en la capa (incluye bucles y sus etiquetas).
        var crossSize: CGFloat
        var cross: CGFloat = 0
        var order = 0
        var preds: [Int] = []
        var succs: [Int] = []
    }

    let chart: LitteraMermaidFlowchart
    let measure: LitteraMermaidLayout.Measure
    let vertical: Bool

    var vertices: [Vertex] = []
    var layers: [[Int]] = []
    var nodeSizes: [CGSize] = []
    var labelSizes: [CGSize?] = []
    var nodeVertex: [Int] = []
    var chains: [[Int]] = []
    var reversed: [Bool] = []
    var labelVertex: [Int?] = []
    var selfLoopReserve: [CGFloat] = []

    init(chart: LitteraMermaidFlowchart, measure: @escaping LitteraMermaidLayout.Measure) {
        self.chart = chart
        self.measure = measure
        vertical = chart.direction == .topDown || chart.direction == .bottomUp
    }

    // Tamaños orientados: «main» a lo largo de las capas, «cross» dentro de ellas.
    private func main(_ size: CGSize) -> CGFloat { vertical ? size.height : size.width }
    private func cross(_ size: CGSize) -> CGFloat { vertical ? size.width : size.height }

    mutating func run() -> LitteraMermaidLayout {
        let nodeCount = chart.nodes.count
        guard nodeCount > 0 else { return LitteraMermaidLayout(size: .zero, nodes: [], edges: []) }

        var indexByID: [String: Int] = [:]
        for (index, node) in chart.nodes.enumerated() { indexByID[node.id] = index }
        let endpoints = chart.edges.map { (indexByID[$0.from] ?? 0, indexByID[$0.to] ?? 0) }

        nodeSizes = chart.nodes.map {
            LitteraMermaidLayout.nodeSize(for: $0.shape, text: measure($0.label, Metrics.nodeFontSize))
        }
        labelSizes = chart.edges.map { edge in
            edge.label.map {
                let text = measure($0, Metrics.labelFontSize)
                return CGSize(width: text.width + Metrics.labelPaddingH * 2, height: text.height + Metrics.labelPaddingV * 2)
            }
        }

        let ranks = assignRanks(endpoints: endpoints, nodeCount: nodeCount)
        buildLayers(endpoints: endpoints, ranks: ranks)
        orderLayers()
        placeCross()
        return output(endpoints: endpoints)
    }

    // MARK: 1–2. Ciclos y rangos

    private mutating func assignRanks(endpoints: [(Int, Int)], nodeCount: Int) -> [Int] {
        var outgoing = Array(repeating: [(to: Int, edge: Int)](), count: nodeCount)
        for (edge, (from, to)) in endpoints.enumerated() where from != to {
            outgoing[from].append((to, edge))
        }

        // DFS iterativo: una arista hacia un nodo de la pila cierra un ciclo.
        reversed = Array(repeating: false, count: endpoints.count)
        var state = Array(repeating: 0, count: nodeCount) // 0 nuevo, 1 en pila, 2 hecho
        for root in 0..<nodeCount where state[root] == 0 {
            var stack: [(node: Int, next: Int)] = [(root, 0)]
            state[root] = 1
            while let top = stack.last {
                if top.next < outgoing[top.node].count {
                    let (to, edge) = outgoing[top.node][top.next]
                    stack[stack.count - 1].next += 1
                    if state[to] == 1 {
                        reversed[edge] = true
                    } else if state[to] == 0 {
                        state[to] = 1
                        stack.append((to, 0))
                    }
                } else {
                    state[top.node] = 2
                    stack.removeLast()
                }
            }
        }

        var successors = Array(repeating: [Int](), count: nodeCount)
        var indegree = Array(repeating: 0, count: nodeCount)
        for (edge, (from, to)) in endpoints.enumerated() where from != to {
            let (a, b) = reversed[edge] ? (to, from) : (from, to)
            successors[a].append(b)
            indegree[b] += 1
        }

        // Camino más largo con orden topológico (Kahn).
        var rank = Array(repeating: 0, count: nodeCount)
        var remaining = indegree
        var queue = (0..<nodeCount).filter { remaining[$0] == 0 }
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for next in successors[node] {
                rank[next] = max(rank[next], rank[node] + 1)
                remaining[next] -= 1
                if remaining[next] == 0 { queue.append(next) }
            }
        }

        // Fuentes junto a su primer hijo, no arriba del todo.
        for node in 0..<nodeCount where indegree[node] == 0 && !successors[node].isEmpty {
            rank[node] = max(0, successors[node].map { rank[$0] }.min()! - 1)
        }
        return rank
    }

    // MARK: 3. Capas con nodos ficticios

    private mutating func buildLayers(endpoints: [(Int, Int)], ranks: [Int]) {
        let layerCount = (ranks.max() ?? 0) * 2 + 1
        layers = Array(repeating: [], count: layerCount)

        selfLoopReserve = Array(repeating: 0, count: chart.nodes.count)
        var selfLoopLabelMain = Array(repeating: CGFloat(0), count: chart.nodes.count)
        for (edge, (from, to)) in endpoints.enumerated() where from == to {
            let label = labelSizes[edge].map(cross) ?? 0
            selfLoopReserve[from] = max(selfLoopReserve[from], Metrics.selfLoop + 6 + label)
            selfLoopLabelMain[from] = max(selfLoopLabelMain[from], labelSizes[edge].map(main) ?? 0)
        }

        nodeVertex = []
        for (node, size) in nodeSizes.enumerated() {
            nodeVertex.append(addVertex(Vertex(
                node: node,
                layer: ranks[node] * 2,
                mainSize: max(main(size), selfLoopLabelMain[node]),
                crossSize: cross(size) + selfLoopReserve[node] * 2
            )))
        }

        chains = Array(repeating: [], count: endpoints.count)
        labelVertex = Array(repeating: nil, count: endpoints.count)
        for (edge, (from, to)) in endpoints.enumerated() where from != to {
            let (a, b) = reversed[edge] ? (to, from) : (from, to)
            let startLayer = ranks[a] * 2
            let endLayer = ranks[b] * 2
            let labelLayer = (startLayer + endLayer) / 2
            var chain = [nodeVertex[a]]
            for layer in (startLayer + 1)..<endLayer {
                let label = layer == labelLayer ? labelSizes[edge] : nil
                let dummy = addVertex(Vertex(
                    edge: edge,
                    hasLabel: label != nil,
                    layer: layer,
                    mainSize: label.map(main) ?? 0,
                    crossSize: label.map(cross) ?? 0
                ))
                if label != nil { labelVertex[edge] = dummy }
                link(chain.last!, dummy)
                chain.append(dummy)
            }
            link(chain.last!, nodeVertex[b])
            chain.append(nodeVertex[b])
            chains[edge] = chain
        }
    }

    private mutating func addVertex(_ vertex: Vertex) -> Int {
        vertices.append(vertex)
        layers[vertex.layer].append(vertices.count - 1)
        return vertices.count - 1
    }

    private mutating func link(_ a: Int, _ b: Int) {
        vertices[a].succs.append(b)
        vertices[b].preds.append(a)
    }

    // MARK: 4. Orden dentro de las capas

    private mutating func orderLayers() {
        // Orden inicial: recorrido en profundidad en el orden de declaración.
        var visited = Array(repeating: false, count: vertices.count)
        var initial = Array(repeating: [Int](), count: layers.count)
        for start in nodeVertex where !visited[start] {
            var stack = [start]
            while let vertex = stack.popLast() {
                guard !visited[vertex] else { continue }
                visited[vertex] = true
                initial[vertices[vertex].layer].append(vertex)
                stack.append(contentsOf: vertices[vertex].succs.reversed().filter { !visited[$0] })
            }
        }
        for vertex in vertices.indices where !visited[vertex] {
            initial[vertices[vertex].layer].append(vertex)
        }
        layers = initial
        refreshOrder()

        var best = layers
        var bestCrossings = crossings()
        var iteration = 0
        while iteration < 12, bestCrossings > 0 {
            if iteration % 2 == 0 {
                for layer in layers.indices.dropFirst() { reorder(layer, downward: true) }
            } else {
                for layer in layers.indices.reversed().dropFirst() { reorder(layer, downward: false) }
            }
            let count = crossings()
            if count < bestCrossings {
                best = layers
                bestCrossings = count
            }
            iteration += 1
        }
        layers = best
        refreshOrder()
    }

    private mutating func refreshOrder() {
        for layer in layers {
            for (position, vertex) in layer.enumerated() { vertices[vertex].order = position }
        }
    }

    private mutating func reorder(_ layer: Int, downward: Bool) {
        var keyed: [(vertex: Int, key: Double, position: Int)] = []
        for (position, vertex) in layers[layer].enumerated() {
            let neighbors = downward ? vertices[vertex].preds : vertices[vertex].succs
            var key = Double(vertices[vertex].order)
            if !neighbors.isEmpty {
                var sum = 0
                for neighbor in neighbors { sum += vertices[neighbor].order }
                key = Double(sum) / Double(neighbors.count)
            }
            keyed.append((vertex, key, position))
        }
        layers[layer] = keyed
            .sorted { $0.key != $1.key ? $0.key < $1.key : $0.position < $1.position }
            .map(\.vertex)
        for (position, vertex) in layers[layer].enumerated() { vertices[vertex].order = position }
    }

    private func crossings() -> Int {
        var total = 0
        for layer in layers.dropLast() {
            var segments: [(Int, Int)] = []
            for vertex in layer {
                for next in vertices[vertex].succs {
                    segments.append((vertices[vertex].order, vertices[next].order))
                }
            }
            for i in segments.indices {
                for j in segments.indices where j > i {
                    let (a1, b1) = segments[i]
                    let (a2, b2) = segments[j]
                    if (a1 - a2) * (b1 - b2) < 0 { total += 1 }
                }
            }
        }
        return total
    }

    // MARK: 5. Posición transversal

    private func gap(_ a: Int, _ b: Int) -> CGFloat {
        let plainA = vertices[a].node == nil && !vertices[a].hasLabel
        let plainB = vertices[b].node == nil && !vertices[b].hasLabel
        if plainA && plainB { return 8 }
        if plainA || plainB { return 14 }
        return Metrics.nodeGap
    }

    private func separation(_ a: Int, _ b: Int) -> CGFloat {
        (vertices[a].crossSize + vertices[b].crossSize) / 2 + gap(a, b)
    }

    private mutating func placeCross() {
        // Posición inicial: cada capa empaquetada y centrada en 0.
        for layer in layers {
            var position: CGFloat = 0
            for (offset, vertex) in layer.enumerated() {
                if offset > 0 { position += separation(layer[offset - 1], vertex) }
                vertices[vertex].cross = position
            }
            let shift = position / 2
            for vertex in layer { vertices[vertex].cross -= shift }
        }

        for pass in 0..<18 {
            let mode = pass % 3
            let order: [Int] = mode == 1 ? Array(layers.indices.reversed()) : Array(layers.indices)
            for layer in order {
                let desired = layers[layer].map { vertex -> CGFloat in
                    let neighbors: [Int]
                    switch mode {
                    case 0: neighbors = vertices[vertex].preds
                    case 1: neighbors = vertices[vertex].succs
                    default: neighbors = vertices[vertex].preds + vertices[vertex].succs
                    }
                    guard !neighbors.isEmpty else { return vertices[vertex].cross }
                    return neighbors.reduce(0) { $0 + vertices[$1].cross } / CGFloat(neighbors.count)
                }
                place(layer, desired: desired)
            }
        }

        let minimum = vertices.map { $0.cross - $0.crossSize / 2 }.min() ?? 0
        for index in vertices.indices { vertices[index].cross -= minimum }
    }

    /// Lo más cerca posible de `desired` respetando orden y separaciones:
    /// regresión isotónica ponderada (pool adjacent violators). Los nodos
    /// ficticios pesan más para que las aristas largas queden rectas.
    private mutating func place(_ layer: Int, desired: [CGFloat]) {
        let members = layers[layer]
        guard !members.isEmpty else { return }
        var offsets: [CGFloat] = [0]
        for index in members.indices.dropFirst() {
            offsets.append(offsets[index - 1] + separation(members[index - 1], members[index]))
        }

        var blocks: [(value: CGFloat, weight: CGFloat, count: Int)] = []
        for (index, vertex) in members.enumerated() {
            let weight: CGFloat = vertices[vertex].node == nil ? 4 : 1
            blocks.append((desired[index] - offsets[index], weight, 1))
            while blocks.count > 1, blocks[blocks.count - 2].value > blocks[blocks.count - 1].value {
                let last = blocks.removeLast()
                let previous = blocks.removeLast()
                let weight = previous.weight + last.weight
                blocks.append((
                    (previous.value * previous.weight + last.value * last.weight) / weight,
                    weight,
                    previous.count + last.count
                ))
            }
        }

        var index = 0
        for block in blocks {
            for _ in 0..<block.count {
                vertices[members[index]].cross = block.value + offsets[index]
                index += 1
            }
        }
    }

    // MARK: 6. Resultado

    private func layerCenters() -> (centers: [CGFloat], extent: CGFloat) {
        var centers: [CGFloat] = []
        var position: CGFloat = 0
        var previousHalf: CGFloat = 0
        for (index, layer) in layers.enumerated() {
            let half = (layer.map { vertices[$0].mainSize }.max() ?? 0) / 2
            position += index == 0 ? half : previousHalf + Metrics.rankGap + half
            centers.append(position)
            previousHalf = half
        }
        return (centers, position + previousHalf)
    }

    private func output(endpoints: [(Int, Int)]) -> LitteraMermaidLayout {
        let (centers, mainExtent) = layerCenters()
        let crossExtent = vertices.map { $0.cross + $0.crossSize / 2 }.max() ?? 0
        let margin = Metrics.margin

        func point(main: CGFloat, cross: CGFloat) -> CGPoint {
            switch chart.direction {
            case .topDown: CGPoint(x: cross + margin, y: main + margin)
            case .bottomUp: CGPoint(x: cross + margin, y: mainExtent - main + margin)
            case .leftRight: CGPoint(x: main + margin, y: cross + margin)
            case .rightLeft: CGPoint(x: mainExtent - main + margin, y: cross + margin)
            }
        }

        func frame(center: CGPoint, size: CGSize) -> CGRect {
            CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        }

        let nodes = chart.nodes.enumerated().map { index, node in
            let vertex = vertices[nodeVertex[index]]
            return LitteraMermaidLayout.PlacedNode(
                id: node.id,
                label: node.label,
                shape: node.shape,
                frame: frame(center: point(main: centers[vertex.layer], cross: vertex.cross), size: nodeSizes[index])
            )
        }

        let ports = portOffsets()
        var edges: [LitteraMermaidLayout.PlacedEdge] = []
        for (edgeIndex, edge) in chart.edges.enumerated() {
            let (from, to) = endpoints[edgeIndex]
            let labelFrame: CGRect?
            var points: [(main: CGFloat, cross: CGFloat)]
            var curves: [(c1: (CGFloat, CGFloat), c2: (CGFloat, CGFloat), end: (CGFloat, CGFloat))] = []

            if from == to {
                let (start, loopCurves, labelCenter) = selfLoop(node: from, centers: centers)
                points = [start]
                curves = loopCurves
                labelFrame = labelSizes[edgeIndex].map { size in
                    let crossSize = vertical ? size.width : size.height
                    return frame(center: point(main: labelCenter.main, cross: labelCenter.cross + crossSize / 2), size: size)
                }
            } else {
                let chain = chains[edgeIndex]
                let (startOffset, endOffset) = ports[edgeIndex]
                let first = vertices[chain[0]]
                let last = vertices[chain[chain.count - 1]]
                let firstNode = first.node!
                let lastNode = last.node!
                points = [(
                    centers[first.layer] + halfMain(node: firstNode, offset: startOffset),
                    first.cross + startOffset
                )]
                for dummy in chain.dropFirst().dropLast() {
                    points.append((centers[vertices[dummy].layer], vertices[dummy].cross))
                }
                points.append((
                    centers[last.layer] - halfMain(node: lastNode, offset: endOffset),
                    last.cross + endOffset
                ))
                if reversed[edgeIndex] { points.reverse() }
                for (p, q) in zip(points, points.dropFirst()) {
                    let middle = (p.main + q.main) / 2
                    curves.append(((middle, p.cross), (middle, q.cross), (q.main, q.cross)))
                }
                labelFrame = labelVertex[edgeIndex].flatMap { dummy in
                    labelSizes[edgeIndex].map { size in
                        frame(center: point(main: centers[vertices[dummy].layer], cross: vertices[dummy].cross), size: size)
                    }
                }
            }

            edges.append(LitteraMermaidLayout.PlacedEdge(
                start: point(main: points[0].main, cross: points[0].cross),
                curves: curves.map {
                    LitteraMermaidLayout.Curve(
                        control1: point(main: $0.c1.0, cross: $0.c1.1),
                        control2: point(main: $0.c2.0, cross: $0.c2.1),
                        end: point(main: $0.end.0, cross: $0.end.1)
                    )
                },
                style: edge.style,
                arrowAtStart: edge.arrowAtStart,
                arrowAtEnd: edge.arrowAtEnd,
                label: edge.label,
                labelFrame: labelFrame
            ))
        }

        let mainSize = mainExtent + margin * 2
        let crossSize = crossExtent + margin * 2
        return LitteraMermaidLayout(
            size: vertical ? CGSize(width: crossSize, height: mainSize) : CGSize(width: mainSize, height: crossSize),
            nodes: nodes,
            edges: edges
        )
    }

    /// Reparte las aristas que entran o salen de un mismo nodo a lo ancho de
    /// su borde, ordenadas según el vecino para no cruzarse.
    private func portOffsets() -> [(start: CGFloat, end: CGFloat)] {
        var result = Array(repeating: (start: CGFloat(0), end: CGFloat(0)), count: chart.edges.count)
        var outgoing = Array(repeating: [(edge: Int, neighbor: CGFloat)](), count: chart.nodes.count)
        var incoming = outgoing
        for (edge, chain) in chains.enumerated() where chain.count >= 2 {
            outgoing[vertices[chain[0]].node!].append((edge, vertices[chain[1]].cross))
            incoming[vertices[chain[chain.count - 1]].node!].append((edge, vertices[chain[chain.count - 2]].cross))
        }

        func offsets(_ count: Int, node: Int) -> [CGFloat] {
            guard count > 1 else { return [0] }
            let width = cross(nodeSizes[node])
            let shape = chart.nodes[node].shape
            let narrow = shape == .diamond || shape == .circle
            let spread = min(width * (narrow ? 0.35 : 0.6), CGFloat(count - 1) * (narrow ? 12 : 16))
            return (0..<count).map { -spread / 2 + spread * CGFloat($0) / CGFloat(count - 1) }
        }

        for node in chart.nodes.indices {
            let sortedOut = outgoing[node].sorted { $0.neighbor < $1.neighbor }
            for (item, offset) in zip(sortedOut, offsets(sortedOut.count, node: node)) {
                result[item.edge].start = offset
            }
            let sortedIn = incoming[node].sorted { $0.neighbor < $1.neighbor }
            for (item, offset) in zip(sortedIn, offsets(sortedIn.count, node: node)) {
                result[item.edge].end = offset
            }
        }
        return result
    }

    /// Distancia del centro al borde a lo largo de las capas, a una distancia
    /// `offset` del centro en la dirección transversal.
    private func halfMain(node: Int, offset: CGFloat) -> CGFloat {
        let size = nodeSizes[node]
        let halfMain = main(size) / 2
        let halfCross = cross(size) / 2
        let t = min(abs(offset) / max(halfCross, 1), 1)
        switch chart.nodes[node].shape {
        case .diamond:
            return halfMain * (1 - t)
        case .circle:
            return max(halfMain * halfMain - offset * offset, 0).squareRoot()
        case .hexagon:
            return vertical ? halfMain : halfMain - LitteraMermaidLayout.hexagonInset(height: size.height) * t
        case .stadium:
            guard !vertical else { return halfMain }
            let radius = halfCross
            return halfMain - radius + max(radius * radius - offset * offset, 0).squareRoot()
        case .rectangle, .rounded, .subroutine, .cylinder:
            return halfMain
        }
    }

    /// Bucle sobre el lado transversal positivo del nodo.
    private func selfLoop(
        node: Int,
        centers: [CGFloat]
    ) -> (start: (main: CGFloat, cross: CGFloat),
          curves: [(c1: (CGFloat, CGFloat), c2: (CGFloat, CGFloat), end: (CGFloat, CGFloat))],
          labelCenter: (main: CGFloat, cross: CGFloat)) {
        let vertex = vertices[nodeVertex[node]]
        let size = nodeSizes[node]
        let centerMain = centers[vertex.layer]
        let halfMain = main(size) / 2
        let halfCross = cross(size) / 2
        let shape = chart.nodes[node].shape
        let border: CGFloat = switch shape {
        case .diamond: halfCross * 0.5
        case .circle: max(halfCross * halfCross - (halfMain / 2) * (halfMain / 2), 0).squareRoot()
        default: halfCross
        }
        let edge = vertex.cross + border
        let reach = Metrics.selfLoop / 0.75
        return (
            (centerMain - halfMain / 2, edge),
            [((centerMain - halfMain, edge + reach), (centerMain + halfMain, edge + reach), (centerMain + halfMain / 2, edge))],
            (centerMain, edge + Metrics.selfLoop + 6)
        )
    }
}

// MARK: - Bloque Mermaid listo para la Vista previa

/// Lo que la Vista previa necesita de un bloque ```mermaid.
nonisolated enum LitteraMermaidDiagram: Equatable, Sendable {
    case flowchart(LitteraMermaidLayout)
    case unsupported(diagramType: String)
    case invalid(line: Int)
    /// Bloque vacío o sin nodos: se muestra el código sin aviso.
    case empty

    static func make(code: String) -> Self {
        switch LitteraMermaidParser.parse(code) {
        case let .flowchart(chart):
            return chart.nodes.isEmpty ? .empty : .flowchart(LitteraMermaidLayout.make(chart))
        case let .unsupported(diagramType):
            return .unsupported(diagramType: diagramType)
        case let .invalid(line):
            return .invalid(line: line)
        case .empty:
            return .empty
        }
    }
}
