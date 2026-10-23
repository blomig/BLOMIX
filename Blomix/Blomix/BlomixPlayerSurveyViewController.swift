//
//  BlomixPlayerSurveyViewController.swift
//  Blomix
//
//  Sondage 8.8 : invitation → 3 questions → merci. Famille Crédits (chrome + blox).
//

import UIKit

@MainActor
final class BlomixPlayerSurveyViewController: UIViewController, UITextViewDelegate {

    private enum Step {
        case invite
        case q1
        case q2
        case q3
        case thanks
    }

    private var step: Step = .invite
    private var selectedModes: Set<BlomixPlayerSurvey.Mode> = []
    private var improveText = ""
    private var recommend: Int?
    private var recommendWhy = ""

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var ratingBar: BlomixSurveyRatingBar?

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        view.backgroundColor = BlomixAppearance.sceneBackground
        addAmbientBlocksBackground(density: .low)
        buildChrome()
        rebuildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        NotificationCenter.default.removeObserver(self)
        if BlomixPlayerSurvey.isShowing {
            BlomixPlayerSurvey.markLater()
        }
    }

    // MARK: - Chrome

    private func buildChrome() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.indicatorStyle = BlomixAppearance.isDark ? .white : .black
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
        ])
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        ratingBar = nil

        switch step {
        case .invite:
            contentStack.addArrangedSubview(makeBody(BlomixL10n.surveyInviteBody))
            contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews.last!)
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyYes, action: #selector(yesTapped)))
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyLater, action: #selector(laterTapped), secondary: true))
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyNever, action: #selector(neverTapped), secondary: true))
        case .q1:
            contentStack.addArrangedSubview(makeTitle(BlomixL10n.surveyQ1))
            contentStack.addArrangedSubview(makeHint(BlomixL10n.surveyQ1Hint))
            for mode in BlomixPlayerSurvey.Mode.allCases {
                contentStack.addArrangedSubview(makeModeChip(mode))
            }
            contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews.last!)
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyContinue, action: #selector(q1Continue)))
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyLater, action: #selector(laterTapped), secondary: true))
        case .q2:
            contentStack.addArrangedSubview(makeTitle(BlomixL10n.surveyQ2))
            let box = makeTextBox(text: improveText, tag: 2)
            contentStack.addArrangedSubview(box.wrap)
            contentStack.addArrangedSubview(box.counter)
            contentStack.setCustomSpacing(24, after: box.counter)
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyContinue, action: #selector(q2Continue)))
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyLater, action: #selector(laterTapped), secondary: true))
        case .q3:
            contentStack.addArrangedSubview(makeTitle(BlomixL10n.surveyQ3))
            let bar = BlomixSurveyRatingBar()
            bar.value = recommend
            bar.addTarget(self, action: #selector(ratingChanged(_:)), for: .valueChanged)
            ratingBar = bar
            contentStack.addArrangedSubview(bar)
            contentStack.addArrangedSubview(makeRatingLabels())
            contentStack.addArrangedSubview(makeHint(BlomixL10n.surveyQ3Why))
            let box = makeTextBox(text: recommendWhy, tag: 3)
            contentStack.addArrangedSubview(box.wrap)
            contentStack.addArrangedSubview(box.counter)
            contentStack.setCustomSpacing(24, after: box.counter)
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyContinue, action: #selector(q3Continue)))
            contentStack.addArrangedSubview(makeButton(BlomixL10n.surveyLater, action: #selector(laterTapped), secondary: true))
        case .thanks:
            contentStack.addArrangedSubview(makeBody(BlomixL10n.surveyThanksBody))
            contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews.last!)
            contentStack.addArrangedSubview(makeButton(BlomixL10n.ok, action: #selector(thanksOK)))
        }
    }

    // MARK: - Widgets

    private func makeTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = BlomixAppearance.primaryText
        label.font = BlomixTypography.displayFont(size: 22)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func makeBody(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = BlomixAppearance.primaryText
        label.font = BlomixTypography.uiFont(size: 16, weight: .regular)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func makeHint(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = BlomixAppearance.secondaryText
        label.font = BlomixTypography.uiFont(size: 13, weight: .regular)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func makeButton(_ title: String, action: Selector, secondary: Bool = false) -> UIButton {
        let btn = BlomixUIButton(type: .system)
        BlomixUIDestinationButtonStyle.applyNavigationButtonStyle(to: btn)
        BlomixUIDestinationButtonStyle.applyContentInsets(
            UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16),
            to: btn
        )
        let font = BlomixTypography.uiFont(size: 16, weight: .semibold)
        btn.setAttributedTitle(NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: BlomixAppearance.chipTitle,
        ]), for: .normal)
        if secondary { btn.alpha = 0.92 }
        btn.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func makeModeChip(_ mode: BlomixPlayerSurvey.Mode) -> UIButton {
        let on = selectedModes.contains(mode)
        let title = on ? "✓  \(mode.title)" : mode.title
        let btn = makeButton(title, action: #selector(modeTapped(_:)), secondary: !on)
        btn.tag = BlomixPlayerSurvey.Mode.allCases.firstIndex(of: mode) ?? 0
        btn.alpha = on ? 1 : 0.72
        return btn
    }

    private func makeRatingLabels() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .equalSpacing
        let left = UILabel()
        left.text = BlomixL10n.surveyRatingLow
        left.textColor = BlomixAppearance.tertiaryText
        left.font = BlomixTypography.uiFont(size: 12, weight: .regular)
        let right = UILabel()
        right.text = BlomixL10n.surveyRatingHigh
        right.textColor = BlomixAppearance.tertiaryText
        right.font = BlomixTypography.uiFont(size: 12, weight: .regular)
        right.textAlignment = .right
        row.addArrangedSubview(left)
        row.addArrangedSubview(right)
        return row
    }

    private func makeTextBox(text: String, tag: Int) -> (wrap: UIView, counter: UILabel) {
        let wrap = UIView()
        wrap.backgroundColor = BlomixAppearance.chipFill
        wrap.layer.cornerRadius = BlomixUIDestinationButtonStyle.cornerRadius
        wrap.layer.borderWidth = 0.75
        wrap.layer.borderColor = BlomixAppearance.chipBorder.cgColor

        let tv = UITextView()
        tv.tag = tag
        tv.delegate = self
        tv.text = text
        tv.font = BlomixTypography.uiFont(size: 16, weight: .regular)
        tv.textColor = BlomixAppearance.primaryText
        tv.backgroundColor = .clear
        tv.tintColor = BlomixAppearance.primaryText
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(tv)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 120),
            tv.topAnchor.constraint(equalTo: wrap.topAnchor),
            tv.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
        ])

        let counter = UILabel()
        counter.tag = tag + 100
        counter.textAlignment = .right
        counter.textColor = BlomixAppearance.tertiaryText
        counter.font = BlomixTypography.uiFont(size: 12, weight: .regular)
        counter.text = "\(text.count)/\(BlomixPlayerSurvey.maxFreeText)"
        return (wrap, counter)
    }

    // MARK: - Actions

    @objc private func yesTapped() {
        step = .q1
        rebuildContent()
    }

    @objc private func laterTapped() {
        BlomixPlayerSurvey.markLater()
        dismiss(animated: true)
    }

    @objc private func neverTapped() {
        BlomixPlayerSurvey.markNever()
        dismiss(animated: true)
    }

    @objc private func modeTapped(_ sender: UIButton) {
        let modes = BlomixPlayerSurvey.Mode.allCases
        guard sender.tag >= 0, sender.tag < modes.count else { return }
        let mode = modes[sender.tag]
        if selectedModes.contains(mode) {
            selectedModes.remove(mode)
        } else {
            selectedModes.insert(mode)
        }
        rebuildContent()
    }

    @objc private func q1Continue() {
        guard !selectedModes.isEmpty else { return }
        step = .q2
        rebuildContent()
    }

    @objc private func q2Continue() {
        step = .q3
        rebuildContent()
    }

    @objc private func ratingChanged(_ bar: BlomixSurveyRatingBar) {
        recommend = bar.value
    }

    @objc private func q3Continue() {
        guard let recommend else { return }
        let answers = BlomixPlayerSurvey.Answers(
            modes: BlomixPlayerSurvey.Mode.allCases
                .filter { selectedModes.contains($0) }
                .map(\.rawValue),
            improve: improveText.trimmingCharacters(in: .whitespacesAndNewlines),
            recommend: recommend,
            recommendWhy: recommendWhy.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        BlomixPlayerSurvey.submit(answers)
        step = .thanks
        rebuildContent()
    }

    @objc private func thanksOK() {
        dismiss(animated: true) {
            BlomixPlayerSurvey.isShowing = false
        }
    }

    // MARK: - Text

    func textViewDidChange(_ textView: UITextView) {
        let clipped = String(textView.text.prefix(BlomixPlayerSurvey.maxFreeText))
        if clipped != textView.text {
            textView.text = clipped
        }
        if textView.tag == 2 {
            improveText = clipped
        } else if textView.tag == 3 {
            recommendWhy = clipped
        }
        if let counter = contentStack.arrangedSubviews.compactMap({ $0 as? UILabel }).first(where: { $0.tag == textView.tag + 100 }) {
            counter.text = "\(clipped.count)/\(BlomixPlayerSurvey.maxFreeText)"
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text as NSString? ?? ""
        let next = current.replacingCharacters(in: range, with: text)
        return next.count <= BlomixPlayerSurvey.maxFreeText
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        adjustForKeyboard(note)
    }

    private func adjustForKeyboard(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let inView = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - inView.minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
    }
}

// MARK: - Barre 0…10 (gouttière peau + pastille)

@MainActor
final class BlomixSurveyRatingBar: UIControl {

    var value: Int? {
        didSet { applyValue(animated: false) }
    }

    private let track = UIView()
    private let fillClip = UIView()
    private let gradient = BlomixSkinGradientLayer()
    private let lip = CALayer()
    private let knob = UIView()
    private var knobCenterX: NSLayoutConstraint?
    private var fillWidth: NSLayoutConstraint?
    private var lastLipSize: CGSize = .zero
    private let valueLabel = UILabel()
    private static let haptic = UIImpactFeedbackGenerator(style: .light)
    private static let knobSize: CGFloat = 28
    private static let trackH: CGFloat = 14

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = BlomixL10n.surveyQ3

        valueLabel.font = BlomixTypography.displayFont(size: 28)
        valueLabel.textColor = BlomixAppearance.primaryText
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        track.clipsToBounds = true
        track.isUserInteractionEnabled = false
        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = BlomixAppearance.progressTrack
        addSubview(track)

        fillClip.clipsToBounds = true
        fillClip.isUserInteractionEnabled = false
        fillClip.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fillClip)
        gradient.actions = ["contents": NSNull()]
        fillClip.layer.addSublayer(gradient)
        BlomixSkinGradientClock.shared.register(gradient)
        lip.contentsGravity = .resize
        lip.actions = ["contents": NSNull()]
        track.layer.addSublayer(lip)

        knob.isUserInteractionEnabled = false
        knob.translatesAutoresizingMaskIntoConstraints = false
        knob.layer.borderWidth = BlomixUIDestinationButtonStyle.hairlineBorderWidth
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        knob.layer.shadowRadius = 1.6
        knob.backgroundColor = BlomixAppearance.chipFill
        addSubview(knob)

        let kx = knob.centerXAnchor.constraint(equalTo: track.leadingAnchor)
        knobCenterX = kx
        let fw = fillClip.widthAnchor.constraint(equalToConstant: 0.5)
        fillWidth = fw

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 72),
            valueLabel.topAnchor.constraint(equalTo: topAnchor),
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            track.heightAnchor.constraint(equalToConstant: Self.trackH),

            fillClip.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fillClip.topAnchor.constraint(equalTo: track.topAnchor),
            fillClip.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fw,

            knob.centerYAnchor.constraint(equalTo: track.centerYAnchor),
            knob.widthAnchor.constraint(equalToConstant: Self.knobSize),
            knob.heightAnchor.constraint(equalToConstant: Self.knobSize),
            kx,
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)

        applyValue(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cap = Self.trackH / 2
        track.layer.cornerRadius = cap
        fillClip.layer.cornerRadius = cap
        gradient.frame = CGRect(origin: .zero, size: track.bounds.size)
        lip.frame = track.bounds
        let lipKey = CGSize(width: bounds.width.rounded(), height: Self.trackH)
        if lipKey != lastLipSize, track.bounds.width > 1 {
            lastLipSize = lipKey
            lip.contents = BlomixButtonRelief.wellInnerShadowImage(
                size: track.bounds.size,
                cornerRadius: cap
            ).cgImage
        }
        knob.layer.cornerRadius = Self.knobSize / 2
        knob.layer.borderColor = BlomixAppearance.chipBorder.cgColor
        knob.layer.shadowOpacity = Float(BlomixButtonRelief.contactShadowAlpha)
        knob.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: Self.knobSize, height: Self.knobSize)),
            cornerRadius: Self.knobSize / 2
        ).cgPath
        applyValue(animated: false)
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        setFromLocation(g.location(in: track).x)
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        setFromLocation(g.location(in: track).x)
    }

    private func setFromLocation(_ x: CGFloat) {
        let w = max(1, track.bounds.width)
        let t = min(1, max(0, x / w))
        let stepped = Int((t * 10).rounded())
        if value != stepped {
            Self.haptic.impactOccurred()
            Self.haptic.prepare()
        }
        value = stepped
        sendActions(for: .valueChanged)
        applyValue(animated: true)
    }

    private func applyValue(animated: Bool) {
        let v = value
        valueLabel.text = v.map { "\($0)" } ?? "—"
        knob.alpha = v == nil ? 0.35 : 1
        accessibilityValue = v.map { "\($0)" } ?? ""
        let frac = CGFloat(v ?? 0) / 10
        let w = track.bounds.width
        let x = (v == nil) ? Self.knobSize / 2 : (Self.knobSize / 2) + frac * max(0, w - Self.knobSize)
        let changes = {
            self.knobCenterX?.constant = x
            self.fillWidth?.constant = max(0.5, frac * w)
            self.gradient.frame = CGRect(origin: .zero, size: self.track.bounds.size)
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut], animations: changes)
        } else {
            changes()
        }
    }

    override func accessibilityIncrement() {
        let next = min(10, (value ?? -1) + 1)
        value = next
        sendActions(for: .valueChanged)
    }

    override func accessibilityDecrement() {
        let next = max(0, (value ?? 1) - 1)
        value = next
        sendActions(for: .valueChanged)
    }
}
