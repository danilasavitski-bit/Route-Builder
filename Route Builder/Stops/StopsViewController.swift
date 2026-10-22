import UIKit

final class StopsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let viewModel: StopsViewModel
    private let store: RouteDraftStore
    var onContinue: () -> Void

    private let modeRow = UIStackView()
    private let oneStopCard = ModeCard(title: "One stop", subtitle: "Single delivery")
    private let multiStopCard = ModeCard(title: "Multi-stop route", subtitle: "Several stops")
    private let searchField = UITextField()
    private let searchErrorLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let indexStack = UIStackView()
    private let chipScroll = UIScrollView()
    private let chipStack = UIStackView()
    private let continueButton = UIButton(type: .system)
    private var didStartLoad = false

    init(viewModel: StopsViewModel, store: RouteDraftStore, onContinue: @escaping () -> Void) {
        self.viewModel = viewModel
        self.store = store
        self.onContinue = onContinue
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildModeRow()
        buildSearch()
        buildTable()
        buildIndex()
        buildBottomBar()
        viewModel.onChange = { [weak self] in
            self?.render()
        }
        render()
        guard !didStartLoad else { return }
        didStartLoad = true
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task { await viewModel.load() }
    }

    private func buildModeRow() {
        modeRow.axis = .horizontal
        modeRow.spacing = 8
        modeRow.distribution = .fillEqually
        modeRow.translatesAutoresizingMaskIntoConstraints = false
        modeRow.addArrangedSubview(oneStopCard)
        modeRow.addArrangedSubview(multiStopCard)
        oneStopCard.addTarget(self, action: #selector(chooseOneStop), for: .touchUpInside)
        multiStopCard.addTarget(self, action: #selector(chooseMultiStop), for: .touchUpInside)
        view.addSubview(modeRow)
        NSLayoutConstraint.activate([
            modeRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            modeRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            modeRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            modeRow.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func buildSearch() {
        searchField.placeholder = "Search by name, street, or phone"
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = Theme.text
        searchField.backgroundColor = Theme.card
        searchField.layer.cornerRadius = Theme.radius
        searchField.layer.borderWidth = 1
        searchField.layer.borderColor = Theme.hairline.cgColor
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        searchField.leftViewMode = .always
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchErrorLabel.font = .systemFont(ofSize: 13)
        searchErrorLabel.textColor = Theme.danger
        searchErrorLabel.numberOfLines = 0
        searchErrorLabel.text = "Search failed. The list below is unchanged."
        searchErrorLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchField)
        view.addSubview(searchErrorLabel)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: modeRow.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            searchField.heightAnchor.constraint(equalToConstant: 44),
            searchErrorLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            searchErrorLabel.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            searchErrorLabel.trailingAnchor.constraint(equalTo: searchField.trailingAnchor)
        ])
    }

    private func buildTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.sectionHeaderTopPadding = 0
        tableView.register(StopCell.self, forCellReuseIdentifier: StopCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    private func buildIndex() {
        indexStack.axis = .vertical
        indexStack.distribution = .fillEqually
        indexStack.translatesAutoresizingMaskIntoConstraints = false
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let button = UIButton(type: .system)
            button.setTitle(String(letter), for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 9, weight: .bold)
            button.tag = Int(letter.asciiValue ?? 65)
            button.addTarget(self, action: #selector(indexTapped(_:)), for: .touchUpInside)
            indexStack.addArrangedSubview(button)
        }
        view.addSubview(indexStack)
    }

    private func buildBottomBar() {
        chipScroll.showsHorizontalScrollIndicator = false
        chipScroll.translatesAutoresizingMaskIntoConstraints = false
        chipStack.axis = .horizontal
        chipStack.spacing = 8
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        chipScroll.addSubview(chipStack)

        continueButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.backgroundColor = Theme.teal
        continueButton.layer.cornerRadius = Theme.radius
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        continueButton.translatesAutoresizingMaskIntoConstraints = false

        let bar = UIView()
        bar.backgroundColor = Theme.card
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(chipScroll)
        bar.addSubview(continueButton)
        view.addSubview(bar)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchErrorLabel.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bar.topAnchor),

            indexStack.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 8),
            indexStack.bottomAnchor.constraint(equalTo: tableView.bottomAnchor, constant: -8),
            indexStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            indexStack.widthAnchor.constraint(equalToConstant: 18),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            chipScroll.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            chipScroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            chipScroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            chipScroll.heightAnchor.constraint(equalToConstant: 36),
            chipStack.topAnchor.constraint(equalTo: chipScroll.topAnchor),
            chipStack.bottomAnchor.constraint(equalTo: chipScroll.bottomAnchor),
            chipStack.leadingAnchor.constraint(equalTo: chipScroll.leadingAnchor),
            chipStack.trailingAnchor.constraint(equalTo: chipScroll.trailingAnchor),
            chipStack.heightAnchor.constraint(equalTo: chipScroll.heightAnchor),

            continueButton.topAnchor.constraint(equalTo: chipScroll.bottomAnchor, constant: 8),
            continueButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            continueButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            continueButton.bottomAnchor.constraint(equalTo: bar.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            continueButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func render() {
        let mode = store.draft.mode
        oneStopCard.setSelected(mode == .oneStop)
        multiStopCard.setSelected(mode == .multiStop)
        searchField.isEnabled = viewModel.state != .loading
        searchErrorLabel.isHidden = !viewModel.searchFailed
        let count = store.draft.stops.count
        continueButton.setTitle("Continue (\(count) stops)", for: .normal)
        let canContinue = count > 0 && viewModel.state == .loaded
        continueButton.isEnabled = canContinue
        continueButton.alpha = canContinue ? 1 : 0.4
        rebuildChips()
        tintIndex()
        tableView.backgroundView = backgroundView()
        tableView.reloadData()
    }

    private func backgroundView() -> UIView? {
        switch viewModel.state {
        case .loading:
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            return spinner
        case .failed(let message):
            return messageView(title: message, actionTitle: "Retry", action: #selector(retryTapped))
        case .loaded:
            if !viewModel.query.isEmpty, viewModel.sections.isEmpty, !viewModel.searchFailed {
                return messageView(title: "No stop found", subtitle: "Try another street", actionTitle: nil, action: nil)
            }
            return nil
        }
    }

    private func messageView(title: String, subtitle: String? = nil, actionTitle: String?, action: Selector?) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        var rows: [UIView] = [titleLabel]
        if let subtitle {
            let label = UILabel()
            label.text = subtitle
            label.font = .systemFont(ofSize: 14)
            label.textColor = Theme.secondary
            label.textAlignment = .center
            rows.append(label)
        }
        if let actionTitle, let action {
            let button = UIButton(type: .system)
            button.setTitle(actionTitle, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
            button.setTitleColor(Theme.teal, for: .normal)
            button.addTarget(self, action: action, for: .touchUpInside)
            rows.append(button)
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        let container = UIView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        return container
    }

    private func rebuildChips() {
        chipStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chipScroll.isHidden = store.draft.stops.isEmpty
        for stop in store.draft.stops {
            let chip = UIButton(type: .system)
            chip.setTitle("\(stop.name)  \(stop.packages)×  ✕", for: .normal)
            chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            chip.setTitleColor(Theme.text, for: .normal)
            chip.backgroundColor = Theme.background
            chip.layer.cornerRadius = 16
            chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            chip.accessibilityIdentifier = stop.stopID
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipStack.addArrangedSubview(chip)
        }
    }

    private func tintIndex() {
        let present = Set(viewModel.sections.map(\.letter))
        for case let button as UIButton in indexStack.arrangedSubviews {
            let letter = button.title(for: .normal) ?? ""
            let active = present.contains(letter)
            button.setTitleColor(active ? Theme.teal : Theme.secondary, for: .normal)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections[section].stops.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let label = UILabel()
        label.text = "  " + viewModel.sections[section].letter
        label.font = .systemFont(ofSize: 13, weight: .heavy)
        label.textColor = Theme.secondary
        label.backgroundColor = Theme.background
        return label
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        28
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: StopCell.reuseID, for: indexPath) as! StopCell
        let stop = viewModel.sections[indexPath.section].stops[indexPath.row]
        let packages = store.draft.stops.first { $0.stopID == stop.id }?.packages
        cell.configure(stop: stop, packages: packages)
        cell.onPill = { [weak self] in
            self?.openPackages(for: stop)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let stop = viewModel.sections[indexPath.section].stops[indexPath.row]
        viewModel.select(stop)
    }

    private func openPackages(for stop: Stop) {
        if !store.draft.isSelected(stop.id) {
            viewModel.select(stop)
        }
        guard let routeStop = store.draft.stops.first(where: { $0.stopID == stop.id }) else { return }
        let sheet = PackageCountViewController(value: routeStop.packages, maxValue: routeStop.packagesMax)
        sheet.modalPresentationStyle = .pageSheet
        sheet.onSave = { [weak self] packages in
            self?.viewModel.savePackages(stopID: stop.id, packages: packages)
        }
        present(sheet, animated: true)
    }

    @objc private func searchChanged() {
        viewModel.searchTextChanged(searchField.text ?? "")
    }

    @objc private func chooseOneStop() {
        viewModel.setMode(.oneStop)
    }

    @objc private func chooseMultiStop() {
        viewModel.setMode(.multiStop)
    }

    @objc private func continueTapped() {
        guard !store.draft.stops.isEmpty, viewModel.state == .loaded else { return }
        onContinue()
    }

    @objc private func retryTapped() {
        Task { await viewModel.load() }
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard let identifier = sender.accessibilityIdentifier else { return }
        viewModel.remove(stopID: identifier)
    }

    @objc private func indexTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal),
              let section = viewModel.sections.firstIndex(where: { $0.letter == title }),
              viewModel.sections[section].stops.isEmpty == false else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .top, animated: true)
    }
}

private final class ModeCard: UIControl {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        backgroundColor = Theme.card
        layer.cornerRadius = Theme.radius
        layer.borderWidth = 1
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = Theme.text
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = Theme.secondary
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSelected(_ selected: Bool) {
        layer.borderColor = (selected ? Theme.teal : Theme.hairline).cgColor
        layer.borderWidth = selected ? 2 : 1
    }
}
