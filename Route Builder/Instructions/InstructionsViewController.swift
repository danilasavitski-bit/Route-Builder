import UIKit

final class InstructionsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let viewModel: InstructionsViewModel
    private let store: RouteDraftStore

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let successLabel = UILabel()
    private let finishButton = UIButton(type: .system)
    private var renderedIDs: [String] = []

    init(viewModel: InstructionsViewModel, store: RouteDraftStore) {
        self.viewModel = viewModel
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        emptyLabel.text = "Select stops before writing instructions."
        emptyLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        emptyLabel.textColor = Theme.secondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        successLabel.font = .systemFont(ofSize: 22, weight: .heavy)
        successLabel.textColor = Theme.text
        successLabel.textAlignment = .center
        successLabel.numberOfLines = 0
        successLabel.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 280
        tableView.register(InstructionCardCell.self, forCellReuseIdentifier: InstructionCardCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        finishButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        finishButton.titleLabel?.numberOfLines = 2
        finishButton.titleLabel?.textAlignment = .center
        finishButton.setTitleColor(.white, for: .normal)
        finishButton.backgroundColor = Theme.teal
        finishButton.layer.cornerRadius = Theme.radius
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        finishButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(successLabel)
        view.addSubview(finishButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: finishButton.topAnchor, constant: -8),

            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            successLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            successLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            successLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            finishButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            finishButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            finishButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            finishButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])

        viewModel.onChange = { [weak self] in
            self?.render()
        }
        render()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyFocus()
    }

    func render() {
        let stops = store.draft.stops
        let ids = stops.map(\.stopID)
        let succeeded: String? = {
            if case .succeeded(let routeID) = viewModel.submitState { return routeID }
            return nil
        }()

        emptyLabel.isHidden = !stops.isEmpty || succeeded != nil
        successLabel.isHidden = succeeded == nil
        successLabel.text = succeeded.map { "Route \($0) sent." }
        tableView.isHidden = stops.isEmpty || succeeded != nil
        finishButton.isHidden = stops.isEmpty || succeeded != nil

        switch viewModel.submitState {
        case .idle:
            finishButton.setTitle("Finish instructions", for: .normal)
            finishButton.backgroundColor = Theme.teal
            finishButton.isEnabled = true
        case .sending:
            finishButton.setTitle("Sending…", for: .normal)
            finishButton.backgroundColor = Theme.teal
            finishButton.isEnabled = false
        case .failed(let message):
            finishButton.setTitle(message, for: .normal)
            finishButton.backgroundColor = Theme.danger
            finishButton.isEnabled = true
        case .succeeded:
            break
        }

        if ids != renderedIDs {
            renderedIDs = ids
            tableView.reloadData()
        } else {
            for case let cell as InstructionCardCell in tableView.visibleCells {
                cell.setInvalid(viewModel.invalidStopIDs.contains(cell.stopID))
            }
        }

        if let identifier = viewModel.consumeScrollRequest(),
           let row = stops.firstIndex(where: { $0.stopID == identifier }) {
            tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: true)
        }
        applyFocus()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        applyFocus()
    }

    private func applyFocus() {
        guard !tableView.isHidden else { return }
        let centerY = tableView.bounds.midY + tableView.contentOffset.y
        let cells = tableView.visibleCells
        guard let active = cells.min(by: { abs($0.center.y - centerY) < abs($1.center.y - centerY) }) else { return }
        for cell in cells {
            let focused = cell === active
            cell.contentView.transform = focused ? .identity : CGAffineTransform(scaleX: 0.94, y: 0.94)
            cell.contentView.alpha = focused ? 1 : 0.55
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.draft.stops.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: InstructionCardCell.reuseID, for: indexPath) as! InstructionCardCell
        let stop = store.draft.stops[indexPath.row]
        cell.configure(stop: stop, invalid: viewModel.invalidStopIDs.contains(stop.stopID))
        cell.onTextChange = { [weak self] text in
            self?.viewModel.instructionsChanged(stopID: stop.stopID, text: text)
            self?.tableView.beginUpdates()
            self?.tableView.endUpdates()
        }
        cell.onClear = { [weak self] in
            self?.viewModel.clear(stopID: stop.stopID)
        }
        cell.onRemove = { [weak self] in
            self?.viewModel.remove(stopID: stop.stopID)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let stop = store.draft.stops[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "Remove from route") { [weak self] _, _, completion in
            self?.viewModel.remove(stopID: stop.stopID)
            completion(true)
        }
        action.backgroundColor = Theme.tealPressed
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func finishTapped() {
        Task { await viewModel.finish() }
    }
}
