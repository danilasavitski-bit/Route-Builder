import UIKit

final class ManualAddressViewController: UIViewController {
    var onSave: ((String, String, String) -> Void)?

    private let nameField = UITextField()
    private let addressField = UITextField()
    private let phoneField = UITextField()
    private let saveButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.card

        let titleLabel = UILabel()
        titleLabel.text = "Enter an address"
        titleLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center

        configure(nameField, placeholder: "Name")
        configure(addressField, placeholder: "Street address")
        configure(phoneField, placeholder: "Phone")
        phoneField.keyboardType = .phonePad
        nameField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        addressField.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)

        saveButton.setTitle("Add to route", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = Theme.teal
        saveButton.layer.cornerRadius = Theme.radius
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, nameField, addressField, phoneField, saveButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            nameField.heightAnchor.constraint(equalToConstant: 48),
            addressField.heightAnchor.constraint(equalToConstant: 48),
            phoneField.heightAnchor.constraint(equalToConstant: 48),
            saveButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        fieldsChanged()
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 16)
        field.textColor = Theme.text
        field.backgroundColor = Theme.background
        field.layer.cornerRadius = Theme.radius
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.autocorrectionType = .no
        field.returnKeyType = .next
    }

    @objc private func fieldsChanged() {
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let address = addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ready = !name.isEmpty && !address.isEmpty
        saveButton.isEnabled = ready
        saveButton.alpha = ready ? 1 : 0.4
    }

    @objc private func saveTapped() {
        onSave?(nameField.text ?? "", addressField.text ?? "", phoneField.text ?? "")
        dismiss(animated: true)
    }
}
