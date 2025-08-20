//
//  AppDelegate.swift
//  Whist
//
//  Created by Tony Buffard on 2025-02-22.
//

import Cocoa
import GameKit
import FirebaseCore

class AppDelegate: NSObject, NSApplicationDelegate, GKLocalPlayerListener {
    
    // Store the pending invite URL if launched via URL or command-line.
    var pendingInviteURL: URL?
    
    // Check for command-line arguments before the app fully launches.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        for arg in args {
            if arg.starts(with: "--gc-invite=") {
                let inviteURLString = String(arg.dropFirst("--gc-invite=".count))
                if let url = URL(string: inviteURLString) {
                    pendingInviteURL = url
                    logger.log("Found pending invite from command-line: \(url)")
                }
            }
        }
        // Defer removal of the "View" menu.
        DispatchQueue.main.async {
            if let mainMenu = NSApplication.shared.mainMenu {
                for item in mainMenu.items {
                    if let submenu = item.submenu,
                       // Check for the "Copy" command, which is unique to the Edit menu.
                       submenu.items.contains(where: { $0.action == #selector(NSText.copy(_:)) }) {
                        mainMenu.removeItem(item)
                        break
                    }
                }
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
//        FirebaseApp.configure()
        // Just check for pending invites
        if let inviteURL = pendingInviteURL {
            logger.log("Processing pending invite URL at launch: \(inviteURL)")
        }
    }
    
    // This method is invoked when the app is launched via a URL.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // Check for your custom URL scheme. For example, "gamecenter://invite?inviteID=..."
            if url.scheme?.lowercased() == "gamecenter" {
                pendingInviteURL = url
                logger.log("Found pending invite from URL: \(url)")
            }
        }
    }
    
    /// Parse the pending invite URL (if any) to extract an invite ID.
    /// We assume the URL is in the form:
    ///    gamecenter://invite?inviteID=YOUR_INVITE_ID&senderID=...
    func checkForPendingInvite() -> String? {
        if let url = pendingInviteURL {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems
            if let inviteID = queryItems?.first(where: { $0.name.lowercased() == "inviteid" })?.value {
                // Clear the stored URL after processing.
                pendingInviteURL = nil
                logger.log("Extracted inviteID: \(inviteID)")
                return inviteID
            }
        }
        return nil
    }
    
    /// Handle the invitation using the extracted invite ID.
    /// Note: There is no public API to convert an invite ID to a GKInvite, so here you must implement
    /// your own logic—perhaps by contacting your server or showing a custom UI—to let the player join the match.
    func handleInvite(withID inviteID: String) {
        logger.log("Handling Game Center invite with ID: \(inviteID)")
    }
}
