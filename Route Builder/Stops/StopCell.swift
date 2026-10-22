import UIKit

final class StopCell: UITableViewCell {
    static let reuseID = "StopCell"

    private(set) var stopID = ""
    var onPill: (() -> Void)?

    private let box = UIView()
    private let check = UIImageView()
    private let avatar = UILabel()
    private let nameLabel = UILabel()
    private let addressLabel = UILabel()
    private let phoneLabel = UILabel()
    private let pillButton = UIButton(type: .system)
    private let hairline = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .white
        contentView.backgroundColor = .white

        box.layer.cornerRadius = 6
        box.layer.borderWidth = 1.5
        box.translatesAutoresizingMaskIntoConstraints = false
        check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        check.tintColor = .white
        check.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(check)

        avatar.font = .systemFont(ofSize: 12, weight: .bold)
        avatar.textColor = Theme.text
        avatar.textAlignment = .center
        avatar.layer.cornerRadius = 11
        avatar.clipsToBounds = true
        avatar.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 14)
        nameLabel.textColor = Theme.text
        addressLabel.font = .systemFont(ofSize: 12)
        addressLabel.textColor = Theme.secondary
        phoneLabel.font = .systemFont(ofSize: 13)
        phoneLabel.textColor = Theme.secondary
        phoneLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        [nameLabel, addressLabel, phoneLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        pillButton.titleLabel?.font = Theme.mono(12)
        pillButton.setTitleColor(Theme.teal, for: .normal)
        pillButton.backgroundColor = .white
        pillButton.layer.cornerRadius = 11
        pillButton.layer.borderWidth = 1
        pillButton.layer.borderColor = Theme.teal.cgColor
        pillButton.contentEdgeInsets = UIEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        pillButton.translatesAutoresizingMaskIntoConstraints = false
        pillButton.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)

        hairline.backgroundColor = Theme.hairline
        hairline.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [nameLabel, addressLabel])
        textStack.axis = .vertical
        textStack.spacing = 0
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let trailingStack = UIStackView(arrangedSubviews: [phoneLabel, pillButton])
        trailingStack.axis = .horizontal
        trailingStack.spacing = 0
        trailingStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(box)
        contentView.addSubview(avatar)
        contentView.addSubview(textStack)
        contentView.addSubview(trailingStack)
        contentView.addSubview(hairline)

        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            box.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 23),
            box.heightAnchor.constraint(equalToConstant: 23),
            check.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            avatar.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 12),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            textStack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8),

            trailingStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            trailingStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(stop: Stop, packages: Int?, query: String) {
        stopID = stop.id
        avatar.text = stop.initials
        avatar.backgroundColor = Theme.avatarColor(for: stop.id)
        nameLabel.attributedText = highlighted(stop.name, query: query, font: nameLabel.font, color: Theme.text)
        addressLabel.text = stop.address
        phoneLabel.text = stop.phone
        let selected = packages != nil
        backgroundColor = selected ? Theme.selectedRow : .white
        contentView.backgroundColor = backgroundColor
        box.backgroundColor = selected ? Theme.teal : .white
        box.layer.borderColor = (selected ? Theme.teal : Theme.checkboxBorder).cgColor
        check.isHidden = !selected
        phoneLabel.isHidden = selected
        pillButton.isHidden = !selected
        if let packages {
            pillButton.setTitle("\(packages)×", for: .normal)
        }
    }

    private func highlighted(_ text: String, query: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        guard !query.isEmpty, let range = text.range(of: query) else { return result }
        result.addAttribute(.backgroundColor, value: Theme.highlight, range: NSRange(range, in: text))
        return result
    }

    @objc private func pillTapped() {
        onPill?()
    }
}
