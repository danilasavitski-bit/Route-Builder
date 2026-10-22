import UIKit

final class InstructionCardCell: UICollectionViewCell, UITextViewDelegate, UIGestureRecognizerDelegate {
    static let reuseID = "InstructionCardCell"

    private(set) var stopID = ""
    var onTextChange: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onCamera: (() -> Void)?
    var onRemove: (() -> Void)?

    private let card = UIView()
    private let nameRow = UIView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let addressLabel = UILabel()
    private let photosTitle = UILabel()
    private let photosRow = UIStackView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let errorRow = UIStackView()
    private let counterLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let dropOffImage = UIImageView()
    private let cameraButton = DropOffButton()
    private let removeButton = UIButton(type: .system)
    private let footerLabel = UILabel()
    private let blurView = UIVisualEffectView(effect: nil)
    private let removeStrip = UILabel()
    private var shownPhotoKey: String?
    private var shownDropOffPath: String?
    private var imageTasks: [URLSessionDataTask] = []
    private var showsBlur = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = false
        contentView.clipsToBounds = false

        card.backgroundColor = Theme.feedCard
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = Theme.hairline.cgColor
        card.layer.shadowColor = UIColor(red: 10 / 255, green: 25 / 255, blue: 35 / 255, alpha: 1).cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 8)
        card.translatesAutoresizingMaskIntoConstraints = false

        nameRow.backgroundColor = .white
        nameRow.layer.cornerRadius = 10
        nameRow.layer.borderWidth = 1.5
        nameRow.layer.borderColor = Theme.hairline.cgColor
        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.textColor = Theme.text
        countLabel.font = Theme.mono(13)
        countLabel.textColor = Theme.teal
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let nameStack = UIStackView(arrangedSubviews: [nameLabel, countLabel])
        nameStack.axis = .horizontal
        nameStack.spacing = 10
        nameStack.translatesAutoresizingMaskIntoConstraints = false
        nameRow.addSubview(nameStack)

        addressLabel.font = .systemFont(ofSize: 11)
        addressLabel.textColor = Theme.teal

        photosTitle.font = .systemFont(ofSize: 11)
        photosTitle.textColor = Theme.secondary
        photosTitle.text = "Photos from the last delivery"
        photosRow.axis = .horizontal
        photosRow.spacing = 6
        photosRow.distribution = .fillEqually

        textView.font = .systemFont(ofSize: 15)
        textView.textColor = Theme.text
        textView.backgroundColor = .white
        textView.layer.cornerRadius = 10
        textView.layer.borderWidth = 1
        textView.layer.borderColor = Theme.hairline.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        textView.isScrollEnabled = false
        textView.delegate = self
        placeholderLabel.text = "Special instructions for the driver…"
        placeholderLabel.font = .systemFont(ofSize: 15)
        placeholderLabel.textColor = Theme.secondary
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        let bang = UILabel()
        bang.text = "!"
        bang.font = .systemFont(ofSize: 10, weight: .bold)
        bang.textColor = .white
        bang.textAlignment = .center
        bang.backgroundColor = Theme.warning
        bang.layer.cornerRadius = 7.5
        bang.clipsToBounds = true
        bang.translatesAutoresizingMaskIntoConstraints = false
        bang.widthAnchor.constraint(equalToConstant: 15).isActive = true
        bang.heightAnchor.constraint(equalToConstant: 15).isActive = true
        let errorLabel = UILabel()
        errorLabel.text = "Add instructions for this stop before finishing"
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = Theme.warningText
        errorLabel.numberOfLines = 0
        errorRow.addArrangedSubview(bang)
        errorRow.addArrangedSubview(errorLabel)
        errorRow.axis = .horizontal
        errorRow.spacing = 8
        errorRow.alignment = .center
        errorRow.isHidden = true

        counterLabel.font = Theme.mono(12)
        counterLabel.textColor = Theme.secondary
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        let spacer = UIView()
        let metaRow = UIStackView(arrangedSubviews: [counterLabel, spacer, clearButton])
        metaRow.axis = .horizontal
        metaRow.alignment = .center

        dropOffImage.contentMode = .scaleAspectFill
        dropOffImage.clipsToBounds = true
        dropOffImage.layer.cornerRadius = 8
        dropOffImage.isHidden = true

        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)

        removeButton.setTitle("Remove from route", for: .normal)
        removeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        removeButton.setTitleColor(Theme.swipe, for: .normal)
        removeButton.contentHorizontalAlignment = .leading
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)

        footerLabel.text = "Instructions save automatically and go to the driver when you finish"
        footerLabel.font = .systemFont(ofSize: 10.5)
        footerLabel.textColor = Theme.secondary
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            nameRow, addressLabel, photosTitle, photosRow, textView, errorRow, metaRow, dropOffImage, cameraButton, removeButton, footerLabel
        ])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        blurView.layer.cornerRadius = 16
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        removeStrip.text = "Remove\nfrom route"
        removeStrip.numberOfLines = 2
        removeStrip.textAlignment = .center
        removeStrip.textColor = .white
        removeStrip.font = .systemFont(ofSize: 13, weight: .bold)
        removeStrip.backgroundColor = Theme.swipe
        removeStrip.layer.cornerRadius = 16
        removeStrip.clipsToBounds = true
        removeStrip.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(removeStrip)
        contentView.addSubview(card)
        card.addSubview(stack)
        card.addSubview(blurView)

        NSLayoutConstraint.activate([
            removeStrip.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            removeStrip.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            removeStrip.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeStrip.widthAnchor.constraint(equalToConstant: 110),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            blurView.topAnchor.constraint(equalTo: card.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            nameRow.heightAnchor.constraint(equalToConstant: 44),
            nameStack.leadingAnchor.constraint(equalTo: nameRow.leadingAnchor, constant: 12),
            nameStack.trailingAnchor.constraint(equalTo: nameRow.trailingAnchor, constant: -12),
            nameStack.centerYAnchor.constraint(equalTo: nameRow.centerYAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 11),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -11),
            cameraButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        let textHeight = textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 84)
        textHeight.isActive = true
        let photoHeight = photosRow.heightAnchor.constraint(equalToConstant: 60)
        photoHeight.priority = UILayoutPriority(999)
        photoHeight.isActive = true
        let dropHeight = dropOffImage.heightAnchor.constraint(equalToConstant: 72)
        dropHeight.priority = UILayoutPriority(999)
        dropHeight.isActive = true
        styleClear(enabled: false)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        bounds = CGRect(x: 0, y: 0, width: width, height: 1)
        contentView.bounds = bounds
        setNeedsLayout()
        layoutIfNeeded()
        let fitted = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return max(1, ceil(fitted.height))
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.view === self else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let velocity = pan.velocity(in: self)
        return velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer.view is UIScrollView
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: 16).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelImageLoads()
        shownPhotoKey = nil
        shownDropOffPath = ""
        onTextChange = nil
        onClear = nil
        onCamera = nil
        card.alpha = 1
        card.transform = .identity
        showsBlur = false
        blurView.effect = nil
        onRemove = nil
    }

    func configure(stop: RouteStop, invalid: Bool) {
        stopID = stop.stopID
        nameLabel.text = stop.name
        countLabel.text = "\(stop.packages)×"
        addressLabel.text = stop.address
        if textView.text != stop.instructions, !textView.isFirstResponder {
            textView.text = stop.instructions
        }
        refreshMeta()
        setInvalid(invalid)
    }

    func setActive(_ active: Bool) {
        nameRow.layer.borderColor = (active ? Theme.teal : Theme.hairline).cgColor
        let show = !active && !textView.isFirstResponder
        guard show != showsBlur else { return }
        showsBlur = show
        let effect: UIVisualEffect? = show ? UIBlurEffect(style: .systemUltraThinMaterialLight) : nil
        let apply = { self.blurView.effect = effect }
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState],
            animations: apply
        )
    }

    func setInvalid(_ invalid: Bool) {
        errorRow.isHidden = !invalid
        textView.layer.borderColor = (invalid ? Theme.warning : Theme.hairline).cgColor
        textView.layer.borderWidth = invalid ? 1.5 : 1
    }

    func showDeliveryPhotos(_ photos: [StopPhoto]?, local: Bool) {
        photosTitle.isHidden = local
        photosRow.isHidden = local
        if local {
            cancelImageLoads()
            shownPhotoKey = nil
            return
        }
        if photos == nil {
            guard shownPhotoKey != "loading" else { return }
            shownPhotoKey = "loading"
            clearPhotoRow()
            photosRow.addArrangedSubview(caption("Loading…"))
            return
        }
        let visible = photos?.filter { $0.url != nil } ?? []
        let key = visible.map(\.id).joined(separator: ",")
        guard shownPhotoKey != key else { return }
        shownPhotoKey = key
        cancelImageLoads()
        clearPhotoRow()
        if visible.isEmpty {
            photosRow.addArrangedSubview(caption("No photos from the last delivery"))
            return
        }
        for photo in visible {
            let tile = PhotoTile(title: photo.title)
            photosRow.addArrangedSubview(tile)
            guard let url = photo.url else { continue }
            let task = URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    tile.setImage(image)
                }
            }
            imageTasks.append(task)
            task.resume()
        }
    }

    func showDropOff(path: String?) {
        guard shownDropOffPath != path else { return }
        shownDropOffPath = path
        if let path, let image = UIImage(contentsOfFile: path) {
            dropOffImage.image = image
            dropOffImage.isHidden = false
        } else {
            dropOffImage.image = nil
            dropOffImage.isHidden = true
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        let limited = String(textView.text.prefix(200))
        if textView.text != limited {
            textView.text = limited
        }
        refreshMeta()
        onTextChange?(textView.text)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let swiftRange = Range(range, in: current) else { return false }
        return current.replacingCharacters(in: swiftRange, with: text).count <= 200
    }

    private func refreshMeta() {
        let text = textView.text ?? ""
        placeholderLabel.isHidden = !text.isEmpty
        counterLabel.text = "\(text.count)/200"
        styleClear(enabled: !text.isEmpty)
    }

    private func styleClear(enabled: Bool) {
        let color = enabled ? Theme.secondary : Theme.disabledText
        let title = NSAttributedString(string: "Clear all", attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: color,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        clearButton.setAttributedTitle(title, for: .normal)
    }

    private func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = Theme.secondary
        return label
    }

    private func clearPhotoRow() {
        photosRow.arrangedSubviews.forEach { view in
            photosRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func cancelImageLoads() {
        imageTasks.forEach { $0.cancel() }
        imageTasks.removeAll()
    }

    @objc private func clearTapped() {
        textView.text = ""
        refreshMeta()
        onClear?()
    }

    @objc private func cameraTapped() {
        onCamera?()
    }

    @objc private func removeTapped() {
        onRemove?()
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = min(0, pan.translation(in: self).x)
        switch pan.state {
        case .changed:
            card.transform = CGAffineTransform(translationX: translation, y: 0)
        case .ended, .cancelled:
            let remove = translation < -100 && pan.state == .ended
            UIView.animate(withDuration: 0.2) {
                self.card.transform = .identity
            }
            if remove {
                onRemove?()
            }
        default:
            break
        }
    }
}

private final class DropOffButton: UIControl {
    private let border = CAShapeLayer()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = 10
        clipsToBounds = true
        border.strokeColor = Theme.hairline.cgColor
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = 1.5
        border.lineDashPattern = [5, 4]
        layer.addSublayer(border)

        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.image = UIImage(systemName: "camera", withConfiguration: symbol)
        icon.tintColor = Theme.secondary
        icon.contentMode = .scaleAspectFit
        titleLabel.text = "Photo of the drop-off point"
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.textColor = Theme.text
        chevron.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        chevron.tintColor = Theme.secondary
        chevron.contentMode = .scaleAspectFit
        for view in [icon, titleLabel, chevron] {
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -10),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.frame = bounds
        let rect = bounds.insetBy(dx: border.lineWidth / 2, dy: border.lineWidth / 2)
        border.path = UIBezierPath(roundedRect: rect, cornerRadius: 10 - border.lineWidth / 2).cgPath
    }
}

private final class PhotoTile: UIView {
    private let imageView = UIImageView()
    private let caption = UILabel()

    init(title: String) {
        super.init(frame: .zero)
        layer.cornerRadius = 8
        clipsToBounds = true
        backgroundColor = UIColor(hex: 0xE9EEF1)
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        caption.text = title
        caption.font = .systemFont(ofSize: 10)
        caption.textColor = .white
        caption.textAlignment = .center
        caption.backgroundColor = UIColor(red: 22 / 255, green: 35 / 255, blue: 46 / 255, alpha: 0.62)
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(caption)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            caption.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setImage(_ image: UIImage) {
        imageView.image = image
    }
}
