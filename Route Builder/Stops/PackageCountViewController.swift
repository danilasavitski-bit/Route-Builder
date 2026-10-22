import UIKit

final class PackageCountViewController: UIViewController {
    var onSave: ((Int) -> Void)?

    private let maxValue: Int
    private var value: Int
    private let valueLabel = UILabel()
    private let minusButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)

    init(value: Int, maxValue: Int) {
        let limit = max(1, maxValue)
        self.maxValue = limit
        self.value = min(limit, max(1, value))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.card

        let titleLabel = UILabel()
        titleLabel.text = "Number of packages"
        titleLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center

        valueLabel.font = .systemFont(ofSize: 40, weight: .bold)
        valueLabel.textColor = Theme.text
        valueLabel.textAlignment = .center

        configureStepper(minusButton, title: "−", action: #selector(decrease))
        configureStepper(plusButton, title: "+", action: #selector(increase))

        let stepper = UIStackView(arrangedSubviews: [minusButton, valueLabel, plusButton])
        stepper.axis = .horizontal
        stepper.alignment = .center
        stepper.distribution = .equalCentering
        stepper.spacing = 24

        let save = UIButton(type: .system)
        save.setTitle("Save", for: .normal)
        save.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        save.setTitleColor(.white, for: .normal)
        save.backgroundColor = Theme.teal
        save.layer.cornerRadius = Theme.radius
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, stepper, save])
        stack.axis = .vertical
        stack.spacing = 28
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            minusButton.widthAnchor.constraint(equalToConstant: 44),
            minusButton.heightAnchor.constraint(equalToConstant: 44),
            plusButton.widthAnchor.constraint(equalToConstant: 44),
            plusButton.heightAnchor.constraint(equalToConstant: 44),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            save.heightAnchor.constraint(equalToConstant: 52)
        ])

        if let sheet = sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        render()
    }

    private func configureStepper(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 28, weight: .medium)
        button.setTitleColor(Theme.teal, for: .normal)
        button.backgroundColor = Theme.background
        button.layer.cornerRadius = 22
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func render() {
        valueLabel.text = "\(value)"
        minusButton.isEnabled = value > 1
        plusButton.isEnabled = value < maxValue
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
}
