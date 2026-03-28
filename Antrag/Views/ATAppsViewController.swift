//
//  ATViewController.swift
//  Antrag
//
//  Created by samara on 7.06.2025.
//

import UIKit
import class SwiftUI.UIHostingController
import IDeviceSwift

// MARK: Class extension: Enum
extension ATAppsViewController {
	enum AppType: String, CaseIterable, Identifiable {
		case system = "System"
		case user = "User"
		
		var id: String {
			rawValue
		}
		
		var stringValue: String {
			.localized(rawValue)
		}
	}
}

// MARK: - Class
class ATAppsViewController: UITableViewController {
	var apps: [AppInfo] = []
	var allSortedApps: [AppInfo] = [] // backup
	var sortedApps: [AppInfo] = [] // main
	var appType: AppType = .user
	
	var appsManager: InstallationAppProxy {
		let listApps = InstallationAppProxy()
		listApps.delegate = self
		return listApps
	}
	
	private var _didLoad = false
	
	override func viewDidLoad() {
		super.viewDidLoad()
		setupTableView()
		setupNavigation()
		setupSearchController()
		setupListeners()
	}
	
	// MARK: Setup
	
	func setupNavigation() {
		let segmentedControl = ATSegmentedControl(items: [AppType.system.stringValue, AppType.user.stringValue])
		segmentedControl.selectedSegmentIndex = 1
		segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
		navigationItem.titleView = segmentedControl
		
		let reloadButton = UIBarButtonItem(systemImageName: "arrow.clockwise.circle.fill", target: self, action: #selector(reloadAction))
		navigationItem.leftBarButtonItem = reloadButton
		
		let settingsButton = UIBarButtonItem(systemImageName: "gear.circle.fill", target: self, action: #selector(settingsAction))
		navigationItem.rightBarButtonItem = settingsButton
	}
	
	func setupSearchController() {
		let searchController = UISearchController(searchResultsController: nil)
		searchController.searchResultsUpdater = self
		searchController.obscuresBackgroundDuringPresentation = false
		navigationItem.searchController = searchController
		definesPresentationContext = true
	}
	
	func setupTableView() {
		tableView.separatorStyle = .none
		tableView.register(
			ATAppsTableViewCell.self,
			forCellReuseIdentifier: ATAppsTableViewCell.reuseIdentifier
		)
	}
	
	func setupListeners() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(listApplicationsAction),
			name: .heartbeat,
			object: nil
		)
		
		DispatchQueue.main.async {
			NotificationCenter.default.post(name: .heartbeat, object: nil)
		}
	}
	
	// MARK: Actions
	
	@objc func segmentChanged(_ sender: UISegmentedControl) {
		appType = sender.selectedSegmentIndex == 0 ? .system : .user
		filterAndReload()
	}
	
	@objc func settingsAction() {
		let nav = UIHostingController(rootView: ATSettingsView())
		nav.modalPresentationStyle = .pageSheet
		
		if let sheet = nav.sheetPresentationController {
			sheet.prefersGrabberVisible = true
		}
		
		present(nav, animated: true)
	}
	
	@objc func reloadAction() {
		if HeartbeatManager.shared.isRsd {
			_didLoad = false
			listApplicationsAction()
		} else {
			_didLoad = false
			HeartbeatManager.shared.start(true)
		}
	}
	
	@objc func listApplicationsAction() {
		guard !_didLoad else { return }
		_didLoad = true
		
		Task {
			do {
				try await appsManager.listApps()
			} catch {
				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: nil,
						message: "\(error)",
						action: {
							HeartbeatManager.shared.start(true)
						}
					)
				}
			}
		}
	}
}

// MARK: - Class extension: TableView
extension ATAppsViewController {
	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		80
	}
	
	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		sortedApps.count
	}
	
	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		cell.clipsToBounds = false
	}
	
	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard let cell = tableView.dequeueReusableCell(
			withIdentifier: ATAppsTableViewCell.reuseIdentifier,
			for: indexPath
		) as? ATAppsTableViewCell else {
			return UITableViewCell()
		}
		
		let app = sortedApps[indexPath.row]
		cell.configure(with: app)
		return cell
	}
	
	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let app = sortedApps[indexPath.row]
		
		tableView.deselectRow(at: indexPath, animated: true)
		
		let detailNavigationController = UINavigationController(rootViewController: ATAppInfoViewController(app: app))
		if #available(iOS 18.0, *) {
			detailNavigationController.preferredTransition = .zoom(sourceViewProvider: { context in
				guard let cell = self.tableView.cellForRow(at: indexPath) else { return nil }
				return cell
			})
		}
		
		present(detailNavigationController, animated: true)
	}
	
	override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
		let app = sortedApps[indexPath.row]
		var actions: [UIContextualAction] = []
		
		if let id = app.CFBundleIdentifier {
			let deleteAction = UIContextualAction(style: .destructive, title: .localized("Delete")) { _,_,_ in
				Task {
					do {
						try await InstallationAppProxy.deleteApp(for: id)
						await MainActor.run {
							self.sortedApps.remove(at: indexPath.row)
							
							if let fullIndex = self.apps.firstIndex(where: { $0.CFBundleIdentifier == id }) {
								self.apps.remove(at: fullIndex)
							}
							
							self.tableView.deleteRows(at: [indexPath], with: .automatic)
						}
					} catch {
						await MainActor.run {
							UIAlertController.showAlertWithOk(
								title: nil,
								message: error.localizedDescription
							)
						}
					}
				}
			}

			deleteAction.image = UIImage(systemName: "trash.fill")
			deleteAction.backgroundColor = .systemRed
			actions.append(deleteAction)
			
			let openAction = UIContextualAction(style: .normal, title: .localized("Open")) { _,_,_ in
				UIApplication.openApp(with: id)
			}
			openAction.image = UIImage(systemName: "arrow.up.forward")
			actions.append(openAction)
		}
		
		let configuration = UISwipeActionsConfiguration(actions: actions)
		configuration.performsFirstActionWithFullSwipe = false
		
		return configuration
	}
	
	@available(iOS 17.0, *)
	override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
		var config: UIContentUnavailableConfiguration?
		if sortedApps.count == 0 {
			var empty = UIContentUnavailableConfiguration.empty()
			empty.background.backgroundColor = .systemBackground
			empty.image = UIImage(systemName: "nosign.app")
			empty.text = .localized("No Apps Found")
			empty.secondaryText = .localized("Please make sure you are connected to the VPN and have a pairing file.")
			empty.background = .listSidebarCell()
			
			config = empty
			contentUnavailableConfiguration = config
			return
		} else {
			contentUnavailableConfiguration = nil
			return
		}
	}
}

extension ATAppsViewController: UISearchResultsUpdating {
	func updateSearchResults(for searchController: UISearchController) {
		guard let searchText = searchController.searchBar.text?.lowercased(), !searchText.isEmpty else {
			sortedApps = allSortedApps
			tableView.reloadData()
			return
		}
		
		sortedApps = allSortedApps.filter { app in
			app.CFBundleDisplayName?.lowercased().contains(searchText) == true ||
			app.CFBundleExecutable?.lowercased().contains(searchText) == true ||
			app.CFBundleIdentifier?.lowercased().contains(searchText) == true
		}
		tableView.reloadData()
	}
}

