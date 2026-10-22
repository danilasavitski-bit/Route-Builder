import UIKit

final class PackageCountViewController: UIViewController {
    var onSave: ((Int) -> Void)?

    private let maxValue: Int
    private var value: Int
    private let anchor: CGRect
    private let valueLabel = UILabel()
    private let minusButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private let card = UIView()
    private var cardLeading: NSLayoutConstraint?
    private var cardTop: NSLayoutConstraint?

    init(value: Int, maxValue: Int, anchor: CGRect) {
        let limit = max(1, maxValue)
        self.maxValue = limit
        self.value = min(limit, max(1, value))
        self.anchor = anchor
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.scrim

        let dismissControl = UIControl()
        dismissControl.translatesAutoresizingMaskIntoConstraints = false
        dismissControl.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(dismissControl)

        card.backgroundColor = .white
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = Theme.hairline.cgColor
        card.layer.shadowColor = UIColor(red: 10 / 255, green: 25 / 255, blue: 35 / 255, alpha: 1).cgColor
        card.layer.shadowOpacity = 0.2
        card.layer.shadowRadius = 15
        card.layer.shadowOffset = CGSize(width: 0, height: 10)
        card.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Number of packages"
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = Theme.secondary
        titleLabel.textAlignment = .center

        valueLabel.font = Theme.mono(24)
        valueLabel.textColor = Theme.text
        valueLabel.textAlignment = .center

        styleStepper(minusButton, title: "−", filled: false, action: #selector(decrease))
        styleStepper(plusButton, title: "+", filled: true, action: #selector(increase))

        let stepper = UIStackView(arrangedSubviews: [minusButton, valueLabel, plusButton])
        stepper.axis = .horizontal
        stepper.alignment = .center
        stepper.spacing = 12

        let save = UIButton(type: .system)
        save.setTitle("Save", for: .normal)
        save.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        save.setTitleColor(.white, for: .normal)
        save.backgroundColor = Theme.teal
        save.layer.cornerRadius = 11
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, stepper, save])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        view.addSubview(card)

        let leading = card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14)
        let top = card.topAnchor.constraint(equalTo: view.topAnchor, constant: 220)
        cardLeading = leading
        cardTop = top
        NSLayoutConstraint.activate([
            dismissControl.topAnchor.constraint(equalTo: view.topAnchor),
            dismissControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dismissControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dismissControl.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leading,
            top,
            card.widthAnchor.constraint(equalToConstant: 214),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            minusButton.widthAnchor.constraint(equalToConstant: 44),
            minusButton.heightAnchor.constraint(equalToConstant: 44),
            plusButton.widthAnchor.constraint(equalToConstant: 44),
            plusButton.heightAnchor.constraint(equalToConstant: 44),
            save.heightAnchor.constraint(equalToConstant: 44)
        ])
        render()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width: CGFloat = 214
        let height = max(card.bounds.height, 160)
        let local = view.convert(anchor, from: nil)
        let x = max(14, min(local.minX, view.bounds.width - width - 14))
        var y = local.maxY + 10
        if y + height > view.bounds.height - 24 {
            y = max(24, local.minY - height - 10)
        }
        if cardLeading?.constant != x {
            cardLeading?.constant = x
        }
        if cardTop?.constant != y {
            cardTop?.constant = y
        }
    }

    private func styleStepper(_ button: UIButton, title: String, filled: Bool, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .medium)
        button.layer.cornerRadius = 11
        if filled {
            button.backgroundColor = Theme.teal
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = .white
            button.setTitleColor(Theme.text, for: .normal)
            button.layer.borderWidth = 1
            button.layer.borderColor = Theme.hairline.cgColor
        }
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func render() {
        valueLabel.text = "\(value)"
        minusButton.isEnabled = value > 1
        plusButton.isEnabled = value < maxValue
        minusButton.alpha = minusButton.isEnabled ? 1 : 0.35
        plusButton.alpha = plusButton.isEnabled ? 1 : 0.35
    }

    @objc private func decrease() {
        value = max(1, value - 1)
        render()
    }

    @objc private func increase() {
        value = min(maxValue, value + 1)
        render()
    }

    @objc private func saveTapped() {
        onSave?(value)
        dismiss(animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
