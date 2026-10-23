//
//  BlomixTrophyCibleView.swift
//  Blomix
//
//  Pastille-cible : anneaux, disque peau, arc du tour actif, compteur, paillettes Magix.
//

import UIKit

enum BlomixTrophyCibleMetrics {
    static let ficheSide: CGFloat = 168
    static let r1: CGFloat = 0.30
    static let r2: CGFloat = 0.54
    static let r3: CGFloat = 0.82
}

@MainActor
final class BlomixTrophyCibleView: UIView {

    var value: Int = 0 { didSet { setNeedsLayout() } }
    var curve: BlomixTrophyCurve = .volumeDefault { didSet { setNeedsLayout() } }
    var isSecretLocked: Bool = false { didSet { setNeedsLayout() } }

    private let ring1 = CAShapeLayer()
    private let ring2 = CAShapeLayer()
    private let ring3 = CAShapeLayer()
    private let discHost = UIView()
    private let discGradient = BlomixSkinGradientLayer()
    private let discMask = CAShapeLayer()
    private let arcGradient = BlomixSkinGradientLayer()
    private let arcMask = CAShapeLayer()
    private let countLabel = UILabel()
    private let innerEmitter = CAEmitterLayer()
    private let outerEmitter = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        for ring in [ring1, ring2, ring3] {
            ring.fillColor = UIColor.clear.cgColor
            ring.lineCap = .round
            layer.addSublayer(ring)
        }

        discHost.backgroundColor = .clear
        discHost.isUserInteractionEnabled = false
        addSubview(discHost)
        discGradient.contentsGravity = .resize
        discHost.layer.addSublayer(discGradient)
        discHost.layer.mask = discMask
        BlomixSkinGradientClock.shared.register(discGradient)

        arcGradient.contentsGravity = .resize
        layer.addSublayer(arcGradient)
        arcGradient.mask = arcMask
        arcMask.fillColor = UIColor.clear.cgColor
        arcMask.strokeColor = UIColor.white.cgColor
        arcMask.lineCap = .round
        BlomixSkinGradientClock.shared.register(arcGradient)

        countLabel.textAlignment = .center
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.45
        countLabel.baselineAdjustment = .alignCenters
        addSubview(countLabel)

        innerEmitter.renderMode = .unordered
        outerEmitter.renderMode = .unordered
        layer.addSublayer(innerEmitter)
        layer.addSublayer(outerEmitter)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        guard side > 8 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let r = side / 2
        let r1 = r * BlomixTrophyCibleMetrics.r1
        let r2 = r * BlomixTrophyCibleMetrics.r2
        let r3 = r * BlomixTrophyCibleMetrics.r3
        let ringW = max(1.2, side * 0.028)
        let tours = BlomixTrophyMath.tours(value: value, curve: curve)
        let locked = isSecretLocked && value <= 0
        let ringColor = BlomixAppearance.tertiaryText.withAlphaComponent(tours.innerLit ? 0.85 : 0.45)

        func ringPath(_ radius: CGFloat) -> UIBezierPath {
            UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )
        }

        for (layer, radius) in [(ring1, r1), (ring2, r2), (ring3, r3)] {
            layer.frame = bounds
            layer.path = ringPath(radius).cgPath
            layer.lineWidth = ringW
            layer.strokeColor = ringColor.cgColor
        }
        if case .unique = curve {
            ring2.isHidden = true
            ring3.isHidden = true
        } else {
            ring2.isHidden = false
            ring3.isHidden = false
        }

        let discRadius: CGFloat
        if locked || !tours.innerLit {
            discRadius = 0
        } else if tours.bothFull {
            discRadius = r3
        } else if tours.second > 0 {
            discRadius = r2
        } else {
            discRadius = r1
        }
        discHost.frame = bounds
        discGradient.frame = bounds
        discHost.isHidden = discRadius < 0.5
        if discRadius >= 0.5 {
            discMask.path = UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - discRadius,
                    y: center.y - discRadius,
                    width: discRadius * 2,
                    height: discRadius * 2
                )
            ).cgPath
        }

        arcGradient.frame = bounds
        arcMask.frame = bounds
        arcMask.lineWidth = max(2.2, side * 0.055)
        let arcRadius: CGFloat
        let arcFill: CGFloat
        if locked || !curve.hasTours || tours.bothFull {
            arcRadius = 0
            arcFill = 0
        } else if tours.second > 0 {
            arcRadius = r3
            arcFill = tours.second
        } else if tours.first > 0 {
            arcRadius = r2
            arcFill = tours.first
        } else {
            arcRadius = 0
            arcFill = 0
        }
        arcGradient.isHidden = arcRadius < 0.5 || arcFill <= 0.001
        if arcRadius >= 0.5 {
            let start = -CGFloat.pi / 2
            let path = UIBezierPath(
                arcCenter: center,
                radius: arcRadius,
                startAngle: start,
                endAngle: start + .pi * 2,
                clockwise: true
            )
            arcMask.path = path.cgPath
            arcMask.strokeEnd = arcFill
        }

        if locked {
            countLabel.text = ""
        } else {
            countLabel.text = "\(value)"
        }
        // Le chiffre vit dans le disque déjà rempli (I = r1, II = r2, III = r3),
        // pas coincé dans le petit cercle central une fois le trophée avancé.
        let usableR = discRadius >= 0.5 ? discRadius : r1
        let labelSide = usableR * 1.72
        let digits = max(1, countLabel.text?.count ?? 1)
        let fontRatio: CGFloat
        switch digits {
        case 1: fontRatio = 0.78
        case 2: fontRatio = 0.52
        case 3: fontRatio = 0.40
        default: fontRatio = 0.32
        }
        countLabel.font = BlomixTypography.displayFont(size: max(8, labelSide * fontRatio))
        countLabel.textColor = tours.innerLit ? .white : BlomixAppearance.tertiaryText
        countLabel.layer.shadowColor = UIColor.black.cgColor
        countLabel.layer.shadowOpacity = tours.innerLit ? 0.45 : 0
        countLabel.layer.shadowRadius = 1.5
        countLabel.layer.shadowOffset = .zero
        countLabel.frame = CGRect(
            x: center.x - labelSide / 2,
            y: center.y - labelSide / 2,
            width: labelSide,
            height: labelSide
        )

        configureEmitters(center: center, innerR: r1, outerR: r3, on: tours.bothFull && !locked)
    }

    private func configureEmitters(center: CGPoint, innerR: CGFloat, outerR: CGFloat, on: Bool) {
        innerEmitter.emitterPosition = center
        outerEmitter.emitterPosition = center
        innerEmitter.emitterSize = CGSize(width: innerR * 2, height: innerR * 2)
        outerEmitter.emitterSize = CGSize(width: outerR * 2, height: outerR * 2)
        innerEmitter.emitterShape = .circle
        outerEmitter.emitterShape = .circle
        innerEmitter.emitterMode = .outline
        outerEmitter.emitterMode = .outline
        if on {
            innerEmitter.emitterCells = [Self.sparkCell(velocity: 18)]
            outerEmitter.emitterCells = [Self.sparkCell(velocity: 28)]
            innerEmitter.birthRate = 1
            outerEmitter.birthRate = 1
        } else {
            innerEmitter.emitterCells = nil
            outerEmitter.emitterCells = nil
            innerEmitter.birthRate = 0
            outerEmitter.birthRate = 0
        }
    }

    private static let sparkImage: CGImage = {
        let s: CGFloat = 8
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: s - 2, height: s - 2)).fill()
        }
        return img.cgImage!
    }()

    private static func sparkCell(velocity: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = sparkImage
        cell.birthRate = 7
        cell.lifetime = 1.15
        cell.lifetimeRange = 0.35
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.4
        cell.scale = 0.22
        cell.scaleRange = 0.12
        cell.alphaSpeed = -0.7
        cell.emissionRange = .pi * 2
        cell.spin = 1.2
        cell.spinRange = 2
        return cell
    }
}

// MARK: - Étoiles post-III

/// Trois étoiles sous la cible. Vides jusqu’au III ; gouttière à 1× / 2× / 3× s3.
enum BlomixTrophyStarsMetrics {
    /// Mur : un peu plus grand que 7 pt, sans bouger cible ni caption (hauteur réservée 9 pt).
    static let wallPointSize: CGFloat = 11
    static let wallReservedHeight: CGFloat = 9
    /// Fiche : même ratio que la cible 168 / 52.
    static let fichePointSize: CGFloat = 36
}

@MainActor
final class BlomixTrophyStarsView: UIView {

    var litCount: Int = 0 {
        didSet {
            let n = min(3, max(0, litCount))
            if n != oldValue { applyLit() }
        }
    }

    var pointSize: CGFloat = 8 {
        didSet { if pointSize != oldValue { applySize() } }
    }

    private struct Slot {
        let view: StarSlotView
        let width: NSLayoutConstraint
        let height: NSLayoutConstraint
    }

    private var slots: [Slot] = []
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
        for _ in 0..<3 {
            slots.append(makeSlot())
        }
        applySize()
        applyLit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func configure(value: Int, curve: BlomixTrophyCurve, secretLocked: Bool) {
        let show = curve.hasTours && !secretLocked
        isHidden = !show
        litCount = show ? BlomixTrophyMath.starCount(value: value, curve: curve) : 0
    }

    override var intrinsicContentSize: CGSize {
        let size = max(6, pointSize)
        let spacing = max(3, (size * 0.25).rounded())
        return CGSize(width: size * 3 + spacing * 2, height: size)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        for slot in slots { slot.view.refreshChrome() }
    }

    private func makeSlot() -> Slot {
        let view = StarSlotView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let size = max(6, pointSize)
        let width = view.widthAnchor.constraint(equalToConstant: size)
        let height = view.heightAnchor.constraint(equalToConstant: size)
        NSLayoutConstraint.activate([width, height])
        stack.addArrangedSubview(view)
        return Slot(view: view, width: width, height: height)
    }

    private func applySize() {
        let size = max(6, pointSize)
        stack.spacing = max(3, (size * 0.25).rounded())
        for slot in slots {
            slot.width.constant = size
            slot.height.constant = size
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func applyLit() {
        let n = min(3, max(0, litCount))
        for (i, slot) in slots.enumerated() {
            slot.view.isLit = i < n
        }
    }
}

/// Une étoile : même recette que le disque de la cible (dégradé peau + masque `CAShapeLayer`).
private final class StarSlotView: UIView {
    var isLit: Bool = false {
        didSet { if isLit != oldValue { applyLit() } }
    }

    private let fillHost = UIView()
    private let gradient = BlomixSkinGradientLayer()
    private let fillMask = CAShapeLayer()
    private let outline = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false

        fillHost.backgroundColor = .clear
        fillHost.isUserInteractionEnabled = false
        addSubview(fillHost)
        gradient.contentsGravity = .resize
        fillHost.layer.addSublayer(gradient)
        fillMask.fillColor = UIColor.white.cgColor
        fillMask.strokeColor = UIColor.white.cgColor
        fillMask.lineJoin = .round
        fillMask.lineCap = .round
        fillHost.layer.mask = fillMask
        BlomixSkinGradientClock.shared.register(gradient)

        outline.fillColor = UIColor.clear.cgColor
        outline.lineJoin = .round
        outline.lineCap = .round
        layer.addSublayer(outline)
        applyLit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillHost.frame = bounds
        gradient.frame = fillHost.bounds
        fillMask.frame = fillHost.bounds
        let side = min(bounds.width, bounds.height)
        let lineW = max(1.05, side * 0.09)
        let pad = lineW / 2 + side * 0.02
        let path = Self.starPath(in: bounds.insetBy(dx: pad, dy: pad)).cgPath
        // Remplie = intérieur + tour, une seule tache gouttière (même gabarit que le contour vide).
        fillMask.path = path
        fillMask.lineWidth = lineW
        outline.frame = bounds
        outline.path = path
        outline.lineWidth = lineW
        outline.strokeColor = BlomixAppearance.tertiaryText.cgColor
    }

    func refreshChrome() {
        outline.strokeColor = BlomixAppearance.tertiaryText.cgColor
        setNeedsLayout()
    }

    private func applyLit() {
        fillHost.alpha = isLit ? 1 : 0
        outline.isHidden = isLit
    }

    private static func starPath(in rect: CGRect) -> UIBezierPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.40
        let path = UIBezierPath()
        for i in 0..<5 {
            let outerAngle = CGFloat(i) * (2 * .pi / 5) - .pi / 2
            let innerAngle = outerAngle + .pi / 5
            let o = CGPoint(
                x: center.x + outer * cos(outerAngle),
                y: center.y + outer * sin(outerAngle)
            )
            let inn = CGPoint(
                x: center.x + inner * cos(innerAngle),
                y: center.y + inner * sin(innerAngle)
            )
            if i == 0 { path.move(to: o) } else { path.addLine(to: o) }
            path.addLine(to: inn)
        }
        path.close()
        return path
    }
}

// MARK: - Légendes fiche (à droite de la cible)

/// Chiffre de seuil : Changa gris (tertiary, Sombre/Clair) ; gouttière qui monte depuis le bas.
@MainActor
final class BlomixTrophyThresholdLabel: UIView {
    var text: String = "" {
        didSet { if text != oldValue { rebuild() } }
    }
    var fill: CGFloat = 0 {
        didSet {
            let n = min(1, max(0, fill))
            if n != oldValue { setNeedsLayout() }
        }
    }

    private let fontSize: CGFloat
    private let grayView = UIImageView()
    private let fillWrap = UIView()
    private let fillContent = UIView()
    private let gradient = BlomixSkinGradientLayer()
    private let textMask = CALayer()
    private var maskImage: UIImage?

    init(fontSize: CGFloat = 16) {
        self.fontSize = fontSize
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false

        grayView.contentMode = .topLeft
        addSubview(grayView)

        fillWrap.clipsToBounds = true
        fillWrap.isUserInteractionEnabled = false
        addSubview(fillWrap)
        fillContent.isUserInteractionEnabled = false
        fillWrap.addSubview(fillContent)
        gradient.contentsGravity = .resize
        fillContent.layer.addSublayer(gradient)
        textMask.contentsGravity = .topLeft
        fillContent.layer.mask = textMask
        BlomixSkinGradientClock.shared.register(gradient)

        NotificationCenter.default.addObserver(
            forName: .blomixAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var intrinsicContentSize: CGSize {
        let font = BlomixTypography.displayFont(size: fontSize)
        let sz = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: max(8, ceil(sz.width)), height: max(8, ceil(sz.height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        grayView.frame = bounds
        let f = min(1, max(0, fill))
        fillWrap.isHidden = f < 0.001
        guard f >= 0.001, bounds.height > 0.5 else { return }
        let h = bounds.height
        fillWrap.frame = CGRect(x: 0, y: h * (1 - f), width: bounds.width, height: h * f)
        fillContent.frame = CGRect(x: 0, y: -h * (1 - f), width: bounds.width, height: h)
        gradient.frame = fillContent.bounds
        textMask.frame = fillContent.bounds
        textMask.contents = maskImage?.cgImage
        textMask.contentsScale = maskImage?.scale ?? UITraitCollection.current.displayScale
    }

    private func rebuild() {
        grayView.image = Self.raster(text: text, fontSize: fontSize, color: BlomixAppearance.tertiaryText)
        maskImage = Self.raster(text: text, fontSize: fontSize, color: .white)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private static func raster(text: String, fontSize: CGFloat, color: UIColor) -> UIImage {
        let font = BlomixTypography.displayFont(size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let sz = (text as NSString).size(withAttributes: attrs)
        let canvas = CGSize(width: max(1, ceil(sz.width)), height: max(1, ceil(sz.height)))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = max(UITraitCollection.current.displayScale, 2)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            (text as NSString).draw(at: .zero, withAttributes: attrs)
        }
    }
}

/// Cible fiche + étoiles sous la cible + 1 / 10 / 100 à droite, calés sur le centre et le haut des anneaux.
@MainActor
final class BlomixTrophyFicheCibleRow: UIView {
    private let cible = BlomixTrophyCibleView()
    private let stars = BlomixTrophyStarsView()
    private let mark1 = BlomixTrophyThresholdLabel()
    private let mark2 = BlomixTrophyThresholdLabel()
    private let mark3 = BlomixTrophyThresholdLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false
        cible.translatesAutoresizingMaskIntoConstraints = true
        stars.translatesAutoresizingMaskIntoConstraints = true
        stars.pointSize = BlomixTrophyStarsMetrics.fichePointSize
        addSubview(cible)
        addSubview(stars)
        addSubview(mark3)
        addSubview(mark2)
        addSubview(mark1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func configure(value: Int, curve: BlomixTrophyCurve, secretLocked: Bool) {
        cible.value = value
        cible.curve = curve
        cible.isSecretLocked = secretLocked
        stars.configure(value: value, curve: curve, secretLocked: secretLocked)
        let show = curve.hasTours && !secretLocked
        mark1.isHidden = !show
        mark2.isHidden = !show
        mark3.isHidden = !show
        if show {
            mark1.text = "\(curve.s1)"
            mark2.text = "\(curve.s2)"
            mark3.text = "\(curve.s3)"
            let tours = BlomixTrophyMath.tours(value: value, curve: curve)
            mark1.fill = tours.innerLit ? 1 : 0
            mark2.fill = tours.first
            mark3.fill = tours.second
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        let side = BlomixTrophyCibleMetrics.ficheSide
        var height = side
        if !stars.isHidden {
            height += 8 + BlomixTrophyStarsMetrics.fichePointSize
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = BlomixTrophyCibleMetrics.ficheSide
        let gap: CGFloat = 12
        let cibleX = (bounds.width - side) / 2
        cible.frame = CGRect(x: cibleX, y: 0, width: side, height: side)
        let starH = stars.isHidden ? 0 : BlomixTrophyStarsMetrics.fichePointSize
        if !stars.isHidden {
            stars.frame = CGRect(
                x: cibleX,
                y: side + 8,
                width: side,
                height: starH
            )
        }
        let r = side / 2
        let cy = cible.frame.midY
        let x = cible.frame.maxX + gap
        func place(_ mark: BlomixTrophyThresholdLabel, centerY: CGFloat) {
            guard !mark.isHidden else { return }
            let size = mark.intrinsicContentSize
            mark.frame = CGRect(
                x: x,
                y: centerY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
        place(mark1, centerY: cy)
        place(mark2, centerY: cy - r * BlomixTrophyCibleMetrics.r2)
        place(mark3, centerY: cy - r * BlomixTrophyCibleMetrics.r3)
    }
}
