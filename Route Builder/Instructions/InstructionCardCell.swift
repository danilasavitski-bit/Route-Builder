import UIKit

final class InstructionCardCell: UITableViewCell, UITextViewDelegate {
    static let reuseID = "InstructionCardCell"

    private(set) var stopID = ""
    var onTextChange: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onRemove: (() -> Void)?

    private let card = UIView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let addressLabel = UILabel()
    private let textView = UITextView()
    private let counterLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let removeButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        card.backgroundColor = Theme.card
        card.layer.cornerRadius = Theme.radius
        card.layer.borderWidth = 1
        card.layer.borderColor = Theme.hairline.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 18, weight: .heavy)
        nameLabel.textColor = Theme.text
        nameLabel.numberOfLines = 2
        countLabel.font = .systemFont(ofSize: 16, weight: .bold)
        countLabel.textColor = Theme.teal
        addressLabel.font = .systemFont(ofSize: 14)
        addressLabel.textColor = Theme.secondary
        addressLabel.numberOfLines = 2

        textView.font = .systemFont(ofSize: 16)
        textView.textColor = Theme.text
        textView.backgroundColor = Theme.background
        textView.layer.cornerRadius = Theme.radius
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.isScrollEnabled = false
        textView.delegate = self

        counterLabel.font = .systemFont(ofSize: 12)
        counterLabel.textColor = Theme.secondary
        clearButton.setTitle("Clear all", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        clearButton.setTitleColor(Theme.teal, for: .normal)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)

        errorLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        errorLabel.textColor = Theme.danger
        errorLabel.numberOfLines = 0
        errorLabel.text = "Add instructions for this stop before finishing"

        removeButton.setTitle("Remove from route", for: .normal)
        removeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        removeButton.setTitleColor(Theme.tealPressed, for: .normal)
        removeButton.contentHorizontalAlignment = .leading
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)

        let titleRow = UIStackView(arrangedSubviews: [nameLabel, countLabel])
        titleRow.axis = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8
        let metaRow = UIStackView(arrangedSubviews: [counterLabel, clearButton])
        metaRow.axis = .horizontal
        metaRow.distribution = .equalSpacing
        let stack = UIStackView(arrangedSubviews: [titleRow, addressLabel, textView, metaRow, errorLabel, removeButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(card)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 88)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(stop: RouteStop, invalid: Bool) {
        stopID = stop.stopID
        nameLabel.text = stop.name
        countLabel.text = "\(stop.packages)×"
        addressLabel.text = stop.address
        if textView.text != stop.instructions, !textView.isFirstResponder {
            textView.text = stop.instructions
        }
        counterLabel.text = "\(textView.text.count)/200"
        errorLabel.isHidden = !invalid
    }

    func setInvalid(_ invalid: Bool) {
        errorLabel.isHidden = !invalid
    }

    func textViewDidChange(_ textView: UITextView) {
        let limited = String(textView.text.prefix(200))
        if textView.text != limited {
            textView.text = limited
        }
        counterLabel.text = "\(textView.text.count)/200"
        onTextChange?(textView.text)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let swiftRange = Range(range, in: current) else { return false }
        let next = current.replacingCharacters(in: swiftRange, with: text)
        return next.count <= 200
    }

    @objc private func clearTapped() {
        textView.text = ""
        counterLabel.text = "0/200"
        onClear?()
    }

    @objc private func removeTapped() {
        onRemove?()
    }
}
