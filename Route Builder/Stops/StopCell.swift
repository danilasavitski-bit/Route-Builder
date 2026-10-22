import UIKit

final class StopCell: UITableViewCell {
    static let reuseID = "StopCell"

    var onPill: (() -> Void)?

    private let card = UIView()
    private let initialsLabel = UILabel()
    private let nameLabel = UILabel()
    private let addressLabel = UILabel()
    private let phoneLabel = UILabel()
    private let pillButton = UIButton(type: .system)

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

        initialsLabel.font = .systemFont(ofSize: 13, weight: .bold)
        initialsLabel.textColor = .white
        initialsLabel.textAlignment = .center
        initialsLabel.backgroundColor = Theme.teal
        initialsLabel.layer.cornerRadius = 18
        initialsLabel.clipsToBounds = true
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = Theme.text
        addressLabel.font = .systemFont(ofSize: 13, weight: .regular)
        addressLabel.textColor = Theme.secondary
        phoneLabel.font = .systemFont(ofSize: 13, weight: .regular)
        phoneLabel.textColor = Theme.secondary
        [nameLabel, addressLabel, phoneLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        pillButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        pillButton.setTitleColor(Theme.teal, for: .normal)
        pillButton.backgroundColor = Theme.background
        pillButton.layer.cornerRadius = 14
        pillButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        pillButton.translatesAutoresizingMaskIntoConstraints = false
        pillButton.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, addressLabel, phoneLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(card)
        card.addSubview(initialsLabel)
        card.addSubview(textStack)
        card.addSubview(pillButton)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            initialsLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            initialsLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            initialsLabel.widthAnchor.constraint(equalToConstant: 36),
            initialsLabel.heightAnchor.constraint(equalToConstant: 36),

            textStack.leadingAnchor.constraint(equalTo: initialsLabel.trailingAnchor, constant: 10),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: pillButton.leadingAnchor, constant: -8),

            pillButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            pillButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            pillButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(stop: Stop, packages: Int?) {
        initialsLabel.text = stop.initials
        nameLabel.text = stop.name
        addressLabel.text = stop.address
        phoneLabel.text = stop.phone
        if let packages {
            pillButton.setTitle("\(packages)×", for: .normal)
            pillButton.isHidden = false
        } else {
            pillButton.setTitle(nil, for: .normal)
            pillButton.isHidden = true
        }
    }

    @objc private func pillTapped() {
        onPill?()
    }
}
