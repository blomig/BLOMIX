//
//  BlomixTrophyCibleView.swift
//  Blomix
//
//  Pastille-cible : anneaux, disque peau, arc du tour actif, compteur, paillettes Magix.
//

import UIKit

@MainActor
final class BlomixTrophyCibleView: UIView {

    var value: Int = 0 { didSet { setNeedsLayout() } }
    var curve: BlomixTrophyCurve = .volumeDefault { didSet { setNeedsLayout() } }
    var showsLegends: Bool = false { didSet { setNeedsLayout() } }
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
    private let legend1 = UILabel()
    private let legend2 = UILabel()
    private let legend3 = UILabel()
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

        for legend in [legend1, legend2, legend3] {
            legend.font = BlomixTypography.uiFont(size: 8, weight: .regular)
            legend.textColor = BlomixAppearance.tertiaryText
            legend.textAlignment = .center
            addSubview(legend)
        }

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
        let r1 = r * 0.30
        let r2 = r * 0.54
        let r3 = r * 0.82
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

        let fontSize = side * (value >= 100 ? 0.22 : 0.28)
        countLabel.font = BlomixTypography.displayFont(size: max(9, fontSize))
        countLabel.textColor = tours.innerLit ? .white : BlomixAppearance.tertiaryText
        countLabel.layer.shadowColor = UIColor.black.cgColor
        countLabel.layer.shadowOpacity = tours.innerLit ? 0.45 : 0
        countLabel.layer.shadowRadius = 1.5
        countLabel.layer.shadowOffset = .zero
        if locked {
            countLabel.text = ""
        } else {
            countLabel.text = "\(value)"
        }
        let labelSide = r1 * 1.7
        countLabel.frame = CGRect(
            x: center.x - labelSide / 2,
            y: center.y - labelSide / 2,
            width: labelSide,
            height: labelSide
        )

        let showLeg = showsLegends && !locked && curve.hasTours
        legend1.isHidden = !showLeg
        legend2.isHidden = !showLeg
        legend3.isHidden = !showLeg
        if showLeg {
            legend1.text = "\(curve.s1)"
            legend2.text = "\(curve.s2)"
            legend3.text = "\(curve.s3)"
            placeLegend(legend1, center: center, radius: r1, side: side)
            placeLegend(legend2, center: center, radius: r2, side: side)
            placeLegend(legend3, center: center, radius: r3, side: side)
        }

        configureEmitters(center: center, innerR: r1, outerR: r3, on: tours.bothFull && !locked)
    }

    private func placeLegend(_ label: UILabel, center: CGPoint, radius: CGFloat, side: CGFloat) {
        label.sizeToFit()
        let w = max(label.bounds.width, 10)
        let h = max(label.bounds.height, 8)
        label.frame = CGRect(
            x: center.x - w / 2,
            y: center.y - radius - h * 0.85,
            width: w,
            height: h
        )
        label.font = BlomixTypography.uiFont(size: max(7, side * 0.09), weight: .regular)
        label.textColor = BlomixAppearance.tertiaryText
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
