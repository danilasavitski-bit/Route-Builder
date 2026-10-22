import UIKit
import CoreImage

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
    private let cameraButton = UIButton(type: .system)
    private let cameraBorder = CAShapeLayer()
    private let footerLabel = UILabel()
    private let blurView = UIImageView()
    private let removeStrip = UILabel()
    private var wantsBlur = false
    private var shownPhotoKey: String?
    private var shownDropOffPath: String?
    private var imageTasks: [URLSessionDataTask] = []
    private static let blurContext = CIContext(options: [.cacheIntermediates: false])

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

        cameraButton.setTitle("  Photo of the drop-off point", for: .normal)
        cameraButton.setImage(UIImage(systemName: "camera"), for: .normal)
        cameraButton.tintColor = Theme.secondary
        cameraButton.setTitleColor(Theme.text, for: .normal)
        cameraButton.titleLabel?.font = .systemFont(ofSize: 14)
        cameraButton.contentHorizontalAlignment = .left
        cameraButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        cameraButton.addTarget(self, action: #selector(cameraTapped), for: .touchUpInside)
        cameraBorder.strokeColor = Theme.hairline.cgColor
        cameraBorder.fillColor = UIColor.white.cgColor
        cameraBorder.lineWidth = 1.5
        cameraBorder.lineDashPattern = [5, 4]
        cameraButton.layer.insertSublayer(cameraBorder, at: 0)

        footerLabel.text = "Instructions save automatically and go to the driver when you finish"
        footerLabel.font = .systemFont(ofSize: 10.5)
        footerLabel.textColor = Theme.secondary
        footerLabel.textAlignment = .center
        footerLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            nameRow, addressLabel, photosTitle, photosRow, textView, errorRow, metaRow, dropOffImage, cameraButton, footerLabel
        ])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        blurView.isHidden = true
        blurView.isUserInteractionEnabled = false
        blurView.contentMode = .scaleToFill
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
        contentView.addSubview(blurView)
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            removeStrip.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            removeStrip.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            removeStrip.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeStrip.widthAnchor.constraint(equalToConstant: 110),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
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
        cameraBorder.frame = cameraButton.bounds
        cameraBorder.path = UIBezierPath(roundedRect: cameraButton.bounds, cornerRadius: 10).cgPath
        card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: 16).cgPath
        blurView.frame = card.frame
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelImageLoads()
        shownPhotoKey = nil
        shownDropOffPath = ""
        onTextChange = nil
        onClear = nil
        onCamera = nil
        wantsBlur = false
        card.alpha = 1
        card.transform = .identity
        blurView.transform = .identity
        blurView.isHidden = true
        blurView.image = nil
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
        contentView.transform = .identity
        let blur = !active && !textView.isFirstResponder
        guard blur != wantsBlur else { return }
        wantsBlur = blur
        applyBlur()
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
                DispatchQueue.main.async { [weak self] in
                    tile.setImage(image)
                    self?.applyBlur()
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
        applyBlur()
    }

    private var blurRetryScheduled = false

    private func applyBlur() {
        guard wantsBlur else {
            card.alpha = 1
            contentView.alpha = 1
            blurView.isHidden = true
            blurView.image = nil
            return
        }
        guard card.bounds.width > 1, card.bounds.height > 1 else {
            guard !blurRetryScheduled else { return }
            blurRetryScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.blurRetryScheduled = false
                guard self?.wantsBlur == true else { return }
                self?.applyBlur()
            }
            return
        }
        card.alpha = 1
        blurView.isHidden = true
        guard let image = Self.blurredSnapshot(of: card) else { return }
        blurView.image = image
        blurView.frame = card.frame
        blurView.isHidden = false
        contentView.alpha = 0.65
    }

    private static func blurredSnapshot(of view: UIView) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.traitCollection.displayScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        let source = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let image = CIImage(image: source),
              let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(3 * source.scale, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: image.extent),
              let cgImage = blurContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: source.scale, orientation: .up)
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

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = min(0, pan.translation(in: self).x)
        switch pan.state {
        case .changed:
            card.transform = CGAffineTransform(translationX: translation, y: 0)
            blurView.transform = card.transform
        case .ended, .cancelled:
            let remove = translation < -100 && pan.state == .ended
            UIView.animate(withDuration: 0.2) {
                self.card.transform = .identity
                self.blurView.transform = .identity
            }
            if remove {
                onRemove?()
            }
        default:
            break
        }
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
