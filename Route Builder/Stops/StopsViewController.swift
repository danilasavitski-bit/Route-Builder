import UIKit

final class StopsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let viewModel: StopsViewModel
    private let store: RouteDraftStore
    var onContinue: () -> Void

    private let modeSwitch = ModeSwitch()
    private let searchField = UITextField()
    private let searchErrorLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let indexStack = UIStackView()
    private let chipScroll = UIScrollView()
    private let chipStack = UIStackView()
    private let continueButton = UIButton(type: .system)
    private var chipHeight: NSLayoutConstraint?
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
        modeSwitch.translatesAutoresizingMaskIntoConstraints = false
        modeSwitch.onOne = { [weak self] in self?.chooseOneStop() }
        modeSwitch.onMulti = { [weak self] in self?.chooseMultiStop() }
        view.addSubview(modeSwitch)
        NSLayoutConstraint.activate([
            modeSwitch.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            modeSwitch.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            modeSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            modeSwitch.heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    private func buildSearch() {
        searchField.placeholder = "Search by name, street, or phone"
        searchField.font = .systemFont(ofSize: 14)
        searchField.textColor = Theme.text
        searchField.backgroundColor = Theme.card
        searchField.layer.cornerRadius = Theme.radius
        searchField.layer.borderWidth = 1
        searchField.layer.borderColor = Theme.hairline.cgColor
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        searchField.leftViewMode = .always
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = Theme.secondary
        icon.contentMode = .scaleAspectFit
        let iconWrap = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 18))
        icon.frame = CGRect(x: 6, y: 0, width: 18, height: 18)
        iconWrap.addSubview(icon)
        searchField.rightView = iconWrap
        searchField.rightViewMode = .always
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .search
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
            searchField.topAnchor.constraint(equalTo: modeSwitch.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            searchField.heightAnchor.constraint(equalToConstant: 46),
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
            button.titleLabel?.font = .systemFont(ofSize: 9.5, weight: .regular)
            button.setTitleColor(Theme.secondary, for: .normal)
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

        continueButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.backgroundColor = Theme.teal
        continueButton.layer.cornerRadius = Theme.radius
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        continueButton.translatesAutoresizingMaskIntoConstraints = false

        let bar = UIView()
        bar.backgroundColor = Theme.card
        bar.translatesAutoresizingMaskIntoConstraints = false
        let hairline = UIView()
        hairline.backgroundColor = Theme.hairline
        hairline.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hairline)
        bar.addSubview(chipScroll)
        bar.addSubview(continueButton)
        view.addSubview(bar)
        let chips = chipScroll.heightAnchor.constraint(equalToConstant: 0)
        chipHeight = chips

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchErrorLabel.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bar.topAnchor),

            indexStack.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 4),
            indexStack.bottomAnchor.constraint(equalTo: tableView.bottomAnchor, constant: -4),
            indexStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 1),
            indexStack.widthAnchor.constraint(equalToConstant: 16),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            hairline.topAnchor.constraint(equalTo: bar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            chips,

            chipScroll.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            chipScroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            chipScroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
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
        modeSwitch.setMode(store.draft.mode)
        searchField.isEnabled = viewModel.state != .loading
        searchErrorLabel.isHidden = !viewModel.searchFailed
        let count = store.draft.stops.count
        continueButton.setTitle("Continue (\(count) stops)", for: .normal)
        let canContinue = count > 0 && viewModel.state == .loaded
        continueButton.isEnabled = canContinue
        continueButton.backgroundColor = canContinue ? Theme.teal : Theme.disabledFill
        continueButton.setTitleColor(canContinue ? .white : Theme.disabledText, for: .normal)
        rebuildChips()
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
                return messageView(
                    title: "No stop found",
                    subtitle: nil,
                    actionTitle: "Try another street or enter an address manually",
                    action: #selector(manualTapped),
                    quietAction: true
                )
            }
            return nil
        }
    }

    private func messageView(title: String, subtitle: String? = nil, actionTitle: String?, action: Selector?, quietAction: Bool = false) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
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
            button.titleLabel?.font = .systemFont(ofSize: quietAction ? 13 : 16, weight: quietAction ? .regular : .bold)
            button.setTitleColor(quietAction ? Theme.secondary : Theme.teal, for: .normal)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
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
        let empty = store.draft.stops.isEmpty
        chipScroll.isHidden = empty
        chipHeight?.constant = empty ? 0 : 58
        for stop in store.draft.stops {
            let chip = RouteChip(name: stop.name, packages: stop.packages)
            chip.accessibilityIdentifier = stop.stopID
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipStack.addArrangedSubview(chip)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections[section].stops.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let wrap = UIView()
        wrap.backgroundColor = Theme.background
        let label = UILabel()
        label.text = viewModel.sections[section].letter
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = Theme.secondary
        label.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 22),
            label.centerYAnchor.constraint(equalTo: wrap.centerYAnchor)
        ])
        return wrap
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        28
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: StopCell.reuseID, for: indexPath) as! StopCell
        let stop = viewModel.sections[indexPath.section].stops[indexPath.row]
        let packages = store.draft.stops.first { $0.stopID == stop.id }?.packages
        cell.configure(stop: stop, packages: packages, query: viewModel.query)
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
        var anchor = CGRect(x: 28, y: 240, width: 40, height: 44)
        if let cell = tableView.visibleCells.first(where: { ($0 as? StopCell)?.stopID == stop.id }) {
            anchor = cell.convert(cell.bounds, to: nil)
        }
        let sheet = PackageCountViewController(value: routeStop.packages, maxValue: routeStop.packagesMax, anchor: anchor)
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

    @objc private func manualTapped() {
        let sheet = ManualAddressViewController()
        sheet.modalPresentationStyle = .pageSheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        sheet.onSave = { [weak self] name, address, phone in
            self?.viewModel.addManual(name: name, address: address, phone: phone)
        }
        present(sheet, animated: true)
    }

    @objc private func chipTapped(_ sender: UIControl) {
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

private final class ModeSwitch: UIView {
    var onOne: (() -> Void)?
    var onMulti: (() -> Void)?

    private let oneButton = ModeSegment(title: "One stop", subtitle: "Single delivery", showsBadge: false)
    private let multiButton = ModeSegment(title: "Multi-stop route", subtitle: "Several stops", showsBadge: true)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = Theme.hairline.cgColor
        let row = UIStackView(arrangedSubviews: [oneButton, multiButton])
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        oneButton.addTarget(self, action: #selector(oneTapped), for: .touchUpInside)
        multiButton.addTarget(self, action: #selector(multiTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setMode(_ mode: SelectionMode) {
        oneButton.setSelected(mode == .oneStop)
        multiButton.setSelected(mode == .multiStop)
    }

    @objc private func oneTapped() { onOne?() }
    @objc private func multiTapped() { onMulti?() }
}

private final class ModeSegment: UIControl {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String, showsBadge: Bool) {
        super.init(frame: .zero)
        layer.cornerRadius = 9
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textAlignment = .center
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 0
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        if showsBadge {
            let badge = UILabel()
            badge.text = "New"
            badge.font = .systemFont(ofSize: 11, weight: .bold)
            badge.textColor = Theme.text
            badge.backgroundColor = Theme.badge
            badge.textAlignment = .center
            badge.layer.cornerRadius = 8
            badge.clipsToBounds = true
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: topAnchor, constant: -6),
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                badge.widthAnchor.constraint(equalToConstant: 34),
                badge.heightAnchor.constraint(equalToConstant: 16)
            ])
        }
        setSelected(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSelected(_ selected: Bool) {
        backgroundColor = selected ? Theme.teal : .clear
        titleLabel.textColor = selected ? .white : Theme.text
        subtitleLabel.textColor = selected ? .white : Theme.secondary
    }
}

private final class RouteChip: UIControl {
    init(name: String, packages: Int) {
        super.init(frame: .zero)
        backgroundColor = .white
        layer.cornerRadius = 12
        layer.borderWidth = 1
        layer.borderColor = Theme.hairline.cgColor

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = Theme.text
        nameLabel.lineBreakMode = .byTruncatingTail

        let count = UILabel()
        count.text = "\(packages)×"
        count.font = Theme.mono(11)
        count.textColor = Theme.teal
        count.backgroundColor = Theme.selectedRow
        count.layer.cornerRadius = 9
        count.clipsToBounds = true
        count.textAlignment = .center

        let close = UILabel()
        close.text = "✕"
        close.font = .systemFont(ofSize: 13)
        close.textColor = Theme.secondary

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottom = UIStackView(arrangedSubviews: [count, spacer, close])
        bottom.axis = .horizontal
        bottom.spacing = 8
        let column = UIStackView(arrangedSubviews: [nameLabel, bottom])
        column.axis = .vertical
        column.spacing = 6
        column.isUserInteractionEnabled = false
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 128),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            count.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            count.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}
